import Foundation
import NoteTakrCore
import NoteTakrKit

public final class SyncService: @unchecked Sendable {
    public typealias SessionLoader = @Sendable (String) throws -> MeetingSession?
    public typealias NoteLoader = @Sendable (String) throws -> MeetingNote?
    public typealias SummaryPersister = @Sendable (String, String, String?) throws -> Void
    public typealias SummaryFailurePersister = @Sendable (String, String, String?) -> Void
    public typealias CrmPushStatusPersister = @Sendable (String, CrmPushStatus) throws -> Void
    public typealias Sleep = @Sendable (TimeInterval) async -> Void

    private let backend: any SyncBackend
    public let outbox: SyncOutbox
    private let loadSession: SessionLoader
    private let loadNote: NoteLoader
    private let persistSummary: SummaryPersister
    private let persistSummaryFailure: SummaryFailurePersister?
    private let persistCrmPushStatus: CrmPushStatusPersister?
    private let peopleCacheSource: ConvexPeopleCacheSource?
    private let peopleCacheDidRefresh: (@Sendable () -> Void)?
    private let peopleCacheRefreshInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let sleep: Sleep

    private let lock = NSLock()
    private var inFlight: Set<String> = []
    private var dirtyWhileInFlight: [String: MeetingPayload] = [:]
    private var deleteWhileInFlight: Set<String> = []
    private var retryFailureCounts: [String: Int] = [:]
    private var summaryUpdatesTask: Task<Void, Never>?
    private var summaryUpdatesGeneration = 0
    private var lastPeopleCacheRefreshAt: Date?

    private enum PayloadState {
        case syncable(MeetingPayload)
        case deleteRemote
        case missing
    }

    private struct FinishedInFlight {
        var dirty: MeetingPayload?
        var deleteRequested: Bool
    }

    public init(
        backend: any SyncBackend,
        outbox: SyncOutbox,
        loadSession: @escaping SessionLoader,
        loadNote: @escaping NoteLoader,
        persistSummary: @escaping SummaryPersister,
        persistSummaryFailure: SummaryFailurePersister? = nil,
        persistCrmPushStatus: CrmPushStatusPersister? = nil,
        peopleCacheSource: ConvexPeopleCacheSource? = nil,
        peopleCacheDidRefresh: (@Sendable () -> Void)? = nil,
        peopleCacheRefreshInterval: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping Sleep = { seconds in
            let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.backend = backend
        self.outbox = outbox
        self.loadSession = loadSession
        self.loadNote = loadNote
        self.persistSummary = persistSummary
        self.persistSummaryFailure = persistSummaryFailure
        self.persistCrmPushStatus = persistCrmPushStatus
        self.peopleCacheSource = peopleCacheSource
        self.peopleCacheDidRefresh = peopleCacheDidRefresh
        self.peopleCacheRefreshInterval = max(0, peopleCacheRefreshInterval)
        self.now = now
        self.sleep = sleep
    }

    @discardableResult
    public func markDirty(localId: String) throws -> Bool {
        guard backend.accountState.isSignedIn else { return false }
        switch try currentPayloadState(localId: localId) {
        case .syncable(let payload):
            if isInFlight(localId: localId) {
                recordDirtyWhileInFlight(payload)
                return false
            }

            try outbox.enqueue(payload)
            return true
        case .deleteRemote:
            discardPending(localId: localId)
            try outbox.enqueueDelete(localId: localId)
            if isInFlight(localId: localId) {
                recordDeleteWhileInFlight(localId: localId)
            }
            return true
        case .missing:
            discardPending(localId: localId)
            try outbox.complete(localId: localId)
            return false
        }
    }

    public func run() async {
        defer { cancelSummaryUpdates() }

        while !Task.isCancelled {
            if backend.accountState.isSignedIn {
                startSummaryUpdatesIfNeeded()
                await runOnce()
            } else {
                cancelSummaryUpdates()
                resetPeopleCacheRefreshThrottle()
            }
            await sleep(5)
        }
    }

    public func resetPeopleCacheRefreshThrottle() {
        locked {
            lastPeopleCacheRefreshAt = nil
        }
    }

    public func runOnce() async {
        guard backend.accountState.isSignedIn else { return }
        await refreshPeopleCacheIfPossible()

        while !Task.isCancelled, backend.accountState.isSignedIn {
            let pending: [SyncOutboxOperation]
            do {
                pending = try outbox.pendingOperations()
            } catch {
                return
            }

            guard !pending.isEmpty else { return }
            var startedWork = false
            var retryDelays: [TimeInterval] = []
            for operation in pending {
                guard backend.accountState.isSignedIn else { return }
                guard beginInFlight(localId: operation.localId) else { continue }
                startedWork = true
                if let delay = await process(operation) {
                    retryDelays.append(delay)
                }
            }

            if !startedWork {
                return
            }
            if let delay = retryDelays.min() {
                await sleep(delay)
            }
        }
    }

    private func refreshPeopleCacheIfPossible() async {
        guard let peopleCacheSource,
              let peopleFetcher = backend as? any SyncPeopleFetching else {
            return
        }
        guard reservePeopleCacheRefreshIfDue() else {
            return
        }
        guard let people = try? await peopleFetcher.fetchPeopleSnapshot() else {
            return
        }
        guard (try? peopleCacheSource.refresh(people: people)) != nil else {
            return
        }
        peopleCacheDidRefresh?()
    }

    public func consumeSummaryUpdates() async {
        guard backend.accountState.isSignedIn else { return }
        for await update in backend.summaryUpdates() {
            guard !Task.isCancelled, backend.accountState.isSignedIn else { return }
            if update.status == .failed {
                let message = update.message?.trimmingCharacters(in: .whitespacesAndNewlines)
                persistSummaryFailure?(
                    update.localId,
                    message?.isEmpty == false ? message! : "Cloud summary generation failed.",
                    update.contentHash
                )
                continue
            }
            guard !update.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            try? persistSummary(update.localId, update.text, update.contentHash)
            if let status = update.crmPushStatus {
                try? persistCrmPushStatus?(update.localId, status)
            }
        }
    }

    public func startSummaryUpdatesIfNeeded() {
        guard backend.accountState.isSignedIn else { return }
        _ = locked {
            guard summaryUpdatesTask == nil else { return false }
            summaryUpdatesGeneration += 1
            let generation = summaryUpdatesGeneration
            summaryUpdatesTask = Task { [weak self] in
                await self?.consumeSummaryUpdates()
                self?.clearFinishedSummaryTask(generation: generation)
            }
            return true
        }
    }

    public func cancelSummaryUpdates() {
        let task = locked {
            let task = summaryUpdatesTask
            summaryUpdatesTask = nil
            summaryUpdatesGeneration += 1
            return task
        }
        task?.cancel()
    }

    private func process(_ operation: SyncOutboxOperation) async -> TimeInterval? {
        switch operation {
        case .upsert(let payload):
            return await processUpsert(localId: payload.localId)
        case .delete(let localId):
            return await processDelete(localId: localId)
        }
    }

    private func processUpsert(localId: String) async -> TimeInterval? {
        do {
            switch try currentPayloadState(localId: localId) {
            case .syncable(let currentPayload):
                try? outbox.enqueue(currentPayload)
                try await backend.upsertMeeting(currentPayload)
                finishSuccessfulPush(localId: localId)
                return nil
            case .deleteRemote:
                try? outbox.enqueueDelete(localId: localId)
                try await backend.deleteMeeting(localId: localId)
                finishSuccessfulDelete(localId: localId)
                return nil
            case .missing:
                finishNoLongerSyncable(localId: localId)
                return nil
            }
        } catch {
            return finishFailedAttempt(localId: localId)
        }
    }

    private func processDelete(localId: String) async -> TimeInterval? {
        do {
            switch try currentPayloadState(localId: localId) {
            case .syncable(let currentPayload):
                try? outbox.enqueue(currentPayload)
                try await backend.upsertMeeting(currentPayload)
                finishSuccessfulPush(localId: localId)
                return nil
            case .deleteRemote, .missing:
                try await backend.deleteMeeting(localId: localId)
                finishSuccessfulDelete(localId: localId)
                return nil
            }
        } catch {
            return finishFailedAttempt(localId: localId)
        }
    }

    private func currentPayloadState(localId: String) throws -> PayloadState {
        guard let session = try loadSession(localId),
              let note = try loadNote(localId) else {
            return .missing
        }
        guard (note.localOnly ?? session.localOnly) != true else {
            return .deleteRemote
        }
        return .syncable(try SyncEnvelope.payload(session: session, note: note))
    }

    private func reservePeopleCacheRefreshIfDue() -> Bool {
        locked {
            let current = now()
            if let lastPeopleCacheRefreshAt,
               current.timeIntervalSince(lastPeopleCacheRefreshAt) < peopleCacheRefreshInterval {
                return false
            }
            lastPeopleCacheRefreshAt = current
            return true
        }
    }

    private func finishNoLongerSyncable(localId: String) {
        discardPending(localId: localId)
        try? outbox.complete(localId: localId)
        _ = finishInFlight(localId: localId)
        resetRetryFailure(localId: localId)
    }

    private func finishSuccessfulPush(localId: String) {
        let finished = finishInFlight(localId: localId)
        resetRetryFailure(localId: localId)

        if finished.deleteRequested {
            try? outbox.enqueueDelete(localId: localId)
        } else if let dirty = finished.dirty {
            try? outbox.enqueue(dirty)
        } else {
            try? outbox.complete(localId: localId)
        }
    }

    private func finishSuccessfulDelete(localId: String) {
        let finished = finishInFlight(localId: localId)
        resetRetryFailure(localId: localId)

        if let dirty = finished.dirty {
            try? outbox.enqueue(dirty)
        } else {
            try? outbox.complete(localId: localId)
        }
    }

    private func finishFailedAttempt(localId: String) -> TimeInterval {
        let finished = finishInFlight(localId: localId)
        if finished.deleteRequested {
            try? outbox.enqueueDelete(localId: localId)
        } else if let dirty = finished.dirty {
            try? outbox.enqueue(dirty)
        }
        return recordRetryFailure(localId: localId)
    }

    private func backoffDelay(afterFailureCount failureCount: Int) -> TimeInterval {
        var delay: TimeInterval = 1
        if failureCount > 0 {
            for _ in 0..<min(failureCount, 9) {
                delay *= 2
            }
        }
        return min(delay, 300)
    }

    private func isInFlight(localId: String) -> Bool {
        locked {
            inFlight.contains(localId)
        }
    }

    private func beginInFlight(localId: String) -> Bool {
        locked {
            guard !inFlight.contains(localId) else { return false }
            inFlight.insert(localId)
            return true
        }
    }

    private func recordDirtyWhileInFlight(_ payload: MeetingPayload) {
        locked {
            deleteWhileInFlight.remove(payload.localId)
            dirtyWhileInFlight[payload.localId] = payload
        }
    }

    private func recordDeleteWhileInFlight(localId: String) {
        locked {
            dirtyWhileInFlight.removeValue(forKey: localId)
            deleteWhileInFlight.insert(localId)
        }
    }

    private func discardPending(localId: String) {
        locked {
            dirtyWhileInFlight.removeValue(forKey: localId)
            deleteWhileInFlight.remove(localId)
        }
    }

    private func recordRetryFailure(localId: String) -> TimeInterval {
        locked {
            let failureCount = retryFailureCounts[localId, default: 0]
            retryFailureCounts[localId] = failureCount + 1
            return backoffDelay(afterFailureCount: failureCount)
        }
    }

    private func resetRetryFailure(localId: String) {
        _ = locked {
            retryFailureCounts.removeValue(forKey: localId)
        }
    }

    @discardableResult
    private func finishInFlight(localId: String) -> FinishedInFlight {
        locked {
            inFlight.remove(localId)
            return FinishedInFlight(
                dirty: dirtyWhileInFlight.removeValue(forKey: localId),
                deleteRequested: deleteWhileInFlight.remove(localId) != nil
            )
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func clearFinishedSummaryTask(generation: Int) {
        locked {
            guard summaryUpdatesGeneration == generation else { return }
            summaryUpdatesTask = nil
        }
    }
}
