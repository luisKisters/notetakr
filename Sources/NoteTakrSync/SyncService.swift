import Foundation
import NoteTakrCore
import NoteTakrKit

public final class SyncService: @unchecked Sendable {
    public typealias SessionLoader = @Sendable (String) throws -> MeetingSession?
    public typealias NoteLoader = @Sendable (String) throws -> MeetingNote?
    public typealias SummaryPersister = @Sendable (String, String, String?) throws -> Void
    public typealias SummaryFailurePersister = @Sendable (String, String) -> Void
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
    private let sleep: Sleep

    private let lock = NSLock()
    private var inFlight: Set<String> = []
    private var dirtyWhileInFlight: [String: MeetingPayload] = [:]
    private var summaryUpdatesTask: Task<Void, Never>?
    private var summaryUpdatesGeneration = 0

    public init(
        backend: any SyncBackend,
        outbox: SyncOutbox,
        loadSession: @escaping SessionLoader,
        loadNote: @escaping NoteLoader,
        persistSummary: @escaping SummaryPersister,
        persistSummaryFailure: SummaryFailurePersister? = nil,
        persistCrmPushStatus: CrmPushStatusPersister? = nil,
        peopleCacheSource: ConvexPeopleCacheSource? = nil,
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
        self.sleep = sleep
    }

    @discardableResult
    public func markDirty(localId: String) throws -> Bool {
        guard backend.accountState.isSignedIn else { return false }
        guard let payload = try currentSyncablePayload(localId: localId) else {
            discardPending(localId: localId)
            try outbox.complete(localId: localId)
            return false
        }

        if isInFlight(localId: localId) {
            recordDirtyWhileInFlight(payload)
            return false
        }

        try outbox.enqueue(payload)
        return true
    }

    public func run() async {
        defer { cancelSummaryUpdates() }

        while !Task.isCancelled {
            if backend.accountState.isSignedIn {
                startSummaryUpdatesIfNeeded()
                await runOnce()
            } else {
                cancelSummaryUpdates()
            }
            await sleep(5)
        }
    }

    public func runOnce() async {
        guard backend.accountState.isSignedIn else { return }
        await refreshPeopleCacheIfPossible()

        while !Task.isCancelled, backend.accountState.isSignedIn {
            let pending: [MeetingPayload]
            do {
                pending = try outbox.pending()
            } catch {
                return
            }

            guard !pending.isEmpty else { return }
            var startedWork = false
            for payload in pending {
                guard backend.accountState.isSignedIn else { return }
                guard beginInFlight(localId: payload.localId) else { continue }
                startedWork = true
                await pushWithRetry(payload)
            }

            if !startedWork {
                return
            }
        }
    }

    private func refreshPeopleCacheIfPossible() async {
        guard let peopleCacheSource,
              let peopleFetcher = backend as? any SyncPeopleFetching else {
            return
        }
        guard let people = try? await peopleFetcher.fetchPeopleSnapshot() else {
            return
        }
        try? peopleCacheSource.refresh(people: people)
    }

    public func consumeSummaryUpdates() async {
        guard backend.accountState.isSignedIn else { return }
        for await update in backend.summaryUpdates() {
            guard !Task.isCancelled, backend.accountState.isSignedIn else { return }
            if update.status == .failed {
                let message = update.message?.trimmingCharacters(in: .whitespacesAndNewlines)
                persistSummaryFailure?(update.localId, message?.isEmpty == false ? message! : "Cloud summary generation failed.")
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

    private func pushWithRetry(_ initialPayload: MeetingPayload) async {
        var payload = takeDirty(localId: initialPayload.localId) ?? initialPayload
        var failureCount = 0

        while !Task.isCancelled, backend.accountState.isSignedIn {
            if let newer = takeDirty(localId: payload.localId) {
                payload = newer
                try? outbox.enqueue(newer)
            }

            do {
                guard let currentPayload = try currentSyncablePayload(localId: payload.localId) else {
                    finishNoLongerSyncable(localId: payload.localId)
                    return
                }
                payload = currentPayload
                try? outbox.enqueue(currentPayload)
                try await backend.upsertMeeting(payload)
                finishSuccessfulPush(localId: payload.localId)
                return
            } catch {
                if let newer = takeDirty(localId: payload.localId) {
                    payload = newer
                    try? outbox.enqueue(newer)
                }
                let delay = backoffDelay(afterFailureCount: failureCount)
                failureCount += 1
                await sleep(delay)
            }
        }

        finishInFlight(localId: payload.localId)
    }

    private func currentSyncablePayload(localId: String) throws -> MeetingPayload? {
        guard let session = try loadSession(localId),
              let note = try loadNote(localId) else {
            return nil
        }
        guard session.localOnly != true, note.localOnly != true else {
            return nil
        }
        return try SyncEnvelope.payload(session: session, note: note)
    }

    private func finishNoLongerSyncable(localId: String) {
        discardPending(localId: localId)
        try? outbox.complete(localId: localId)
        _ = finishInFlight(localId: localId)
    }

    private func finishSuccessfulPush(localId: String) {
        if let dirty = takeDirty(localId: localId) {
            try? outbox.enqueue(dirty)
        } else {
            try? outbox.complete(localId: localId)
        }

        if let lateDirty = finishInFlight(localId: localId) {
            try? outbox.enqueue(lateDirty)
        }
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
            dirtyWhileInFlight[payload.localId] = payload
        }
    }

    private func discardPending(localId: String) {
        _ = locked {
            dirtyWhileInFlight.removeValue(forKey: localId)
        }
    }

    private func takeDirty(localId: String) -> MeetingPayload? {
        locked {
            dirtyWhileInFlight.removeValue(forKey: localId)
        }
    }

    @discardableResult
    private func finishInFlight(localId: String) -> MeetingPayload? {
        locked {
            inFlight.remove(localId)
            return dirtyWhileInFlight.removeValue(forKey: localId)
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
