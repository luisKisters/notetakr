import Foundation
import NoteTakrCore
import NoteTakrKit

public final class SyncService: @unchecked Sendable {
    public typealias SessionLoader = @Sendable (String) throws -> MeetingSession?
    public typealias NoteLoader = @Sendable (String) throws -> MeetingNote?
    public typealias SummaryPersister = @Sendable (String, String) throws -> Void
    public typealias Sleep = @Sendable (TimeInterval) async -> Void
    public typealias Clock = @Sendable () -> Date

    private let backend: any SyncBackend
    public let outbox: SyncOutbox
    private let loadSession: SessionLoader
    private let loadNote: NoteLoader
    private let persistSummary: SummaryPersister
    private let sleep: Sleep
    private let now: Clock

    private let lock = NSLock()
    private var inFlight: Set<String> = []
    private var dirtyWhileInFlight: [String: MeetingPayload] = [:]

    public init(
        backend: any SyncBackend,
        outbox: SyncOutbox,
        loadSession: @escaping SessionLoader,
        loadNote: @escaping NoteLoader,
        persistSummary: @escaping SummaryPersister,
        sleep: @escaping Sleep = { seconds in
            let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        now: @escaping Clock = { Date() }
    ) {
        self.backend = backend
        self.outbox = outbox
        self.loadSession = loadSession
        self.loadNote = loadNote
        self.persistSummary = persistSummary
        self.sleep = sleep
        self.now = now
    }

    @discardableResult
    public func markDirty(localId: String) throws -> Bool {
        _ = now()
        guard backend.accountState.isSignedIn else { return false }
        guard let session = try loadSession(localId),
              let note = try loadNote(localId) else { return false }
        guard session.localOnly != true, note.localOnly != true else { return false }

        let payload = try SyncEnvelope.payload(session: session, note: note)
        if isInFlight(localId: localId) {
            recordDirtyWhileInFlight(payload)
            return false
        }

        try outbox.enqueue(payload)
        return true
    }

    public func run() async {
        let summaryTask = Task {
            await consumeSummaryUpdates()
        }
        defer { summaryTask.cancel() }

        while !Task.isCancelled {
            await runOnce()
            await sleep(5)
        }
    }

    public func runOnce() async {
        guard backend.accountState.isSignedIn else { return }

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

    public func consumeSummaryUpdates() async {
        for await update in backend.summaryUpdates() {
            guard !Task.isCancelled else { return }
            try? persistSummary(update.localId, update.text)
        }
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
}
