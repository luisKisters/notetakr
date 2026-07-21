import Foundation
import XCTest
import NoteTakrCore
import NoteTakrKit
@testable import NoteTakrSync

final class SyncServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncServiceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSignedOutMakesZeroBackendCalls() async throws {
        let store = SyncFixtureStore()
        let backend = MockSyncBackend(accountState: .signedOut)
        let service = makeService(store: store, backend: backend)

        for index in 0..<3 {
            let id = UUID()
            store.put(session: makeSession(id: id, title: "Meeting \(index)"))
            store.put(note: makeNote(id: id, body: "Body \(index)"))
            try service.markDirty(localId: id.uuidString)
        }

        await service.runOnce()

        XCTAssertEqual(backend.upsertCount, 0)
    }

    func testLocalOnlyMeetingsAreNeverEnqueued() throws {
        let store = SyncFixtureStore()
        let backend = MockSyncBackend(accountState: .signedIn(email: "luis@example.test"))
        let outbox = SyncOutbox(rootURL: tempDir)
        let service = makeService(store: store, backend: backend, outbox: outbox)
        let id = UUID()
        store.put(session: makeSession(id: id, localOnly: false))
        store.put(note: makeNote(id: id, localOnly: true))

        try service.markDirty(localId: id.uuidString)

        XCTAssertTrue(try outbox.pending().isEmpty)
    }

    func testLocalOnlyDirtyClearsPendingOutboxItem() throws {
        let store = SyncFixtureStore()
        let backend = MockSyncBackend(accountState: .signedIn(email: "luis@example.test"))
        let outbox = SyncOutbox(rootURL: tempDir)
        let service = makeService(store: store, backend: backend, outbox: outbox)
        let id = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!
        store.put(session: makeSession(id: id))
        store.put(note: makeNote(id: id, body: "syncable"))
        try service.markDirty(localId: id.uuidString)
        XCTAssertFalse(try outbox.pending().isEmpty)

        store.put(note: makeNote(id: id, body: "private", localOnly: true))
        try service.markDirty(localId: id.uuidString)

        XCTAssertTrue(try outbox.pending().isEmpty)
    }

    func testDrainPushesAllPendingAndCompletes() async throws {
        let store = SyncFixtureStore()
        let backend = MockSyncBackend(accountState: .signedIn(email: "luis@example.test"))
        let outbox = SyncOutbox(rootURL: tempDir)
        let service = makeService(store: store, backend: backend, outbox: outbox)
        let firstId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let firstSession = makeSession(id: firstId)
        let firstNote = makeNote(id: firstId, body: "one")
        let secondSession = makeSession(id: secondId)
        let secondNote = makeNote(id: secondId, body: "two")
        store.put(session: firstSession)
        store.put(note: firstNote)
        store.put(session: secondSession)
        store.put(note: secondNote)
        let first = try SyncEnvelope.payload(session: firstSession, note: firstNote)
        let second = try SyncEnvelope.payload(session: secondSession, note: secondNote)
        try outbox.enqueue(first)
        try outbox.enqueue(second)

        await service.runOnce()

        XCTAssertEqual(backend.upsertCount, 2)
        XCTAssertEqual(backend.upsertedPayloads.map(\.localId), [first.localId, second.localId])
        XCTAssertTrue(try outbox.pending().isEmpty)
    }

    func testFailedPushRetriesWithExponentialBackoff() async throws {
        let store = SyncFixtureStore()
        let backend = MockSyncBackend(accountState: .signedIn(email: "luis@example.test"))
        backend.failuresBeforeSuccess = 2
        let sleepRecorder = SleepRecorder()
        let outbox = SyncOutbox(rootURL: tempDir)
        let service = makeService(
            store: store,
            backend: backend,
            outbox: outbox,
            sleep: { delay in sleepRecorder.record(delay) }
        )
        let id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let session = makeSession(id: id)
        let note = makeNote(id: id)
        store.put(session: session)
        store.put(note: note)
        let payload = try SyncEnvelope.payload(session: session, note: note)
        try outbox.enqueue(payload)

        await service.runOnce()

        XCTAssertEqual(sleepRecorder.delays, [1, 2])
        XCTAssertEqual(backend.upsertCount, 3)
        XCTAssertTrue(try outbox.pending().isEmpty)
    }

    func testFailedPushDoesNotRetryAfterMeetingBecomesLocalOnly() async throws {
        let store = SyncFixtureStore()
        let backend = MockSyncBackend(accountState: .signedIn(email: "luis@example.test"))
        backend.failuresBeforeSuccess = 1
        let sleepRecorder = SleepRecorder()
        let outbox = SyncOutbox(rootURL: tempDir)
        let id = UUID(uuidString: "34343434-3434-3434-3434-343434343434")!
        let session = makeSession(id: id)
        let syncableNote = makeNote(id: id, body: "syncable")
        let localOnlyNote = makeNote(id: id, body: "private", localOnly: true)
        store.put(session: session)
        store.put(note: syncableNote)
        try outbox.enqueue(SyncEnvelope.payload(session: session, note: syncableNote))

        let service = makeService(
            store: store,
            backend: backend,
            outbox: outbox,
            sleep: { delay in
                sleepRecorder.record(delay)
                store.put(note: localOnlyNote)
            }
        )

        await service.runOnce()

        XCTAssertEqual(sleepRecorder.delays, [1])
        XCTAssertEqual(backend.upsertCount, 1)
        XCTAssertTrue(try outbox.pending().isEmpty)
    }

    func testDirtyWhileInFlightRequeues() async throws {
        let store = SyncFixtureStore()
        let backend = MockSyncBackend(accountState: .signedIn(email: "luis@example.test"))
        let outbox = SyncOutbox(rootURL: tempDir)
        let service = makeService(store: store, backend: backend, outbox: outbox)
        let id = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        store.put(session: makeSession(id: id))
        store.put(note: makeNote(id: id, body: "v1"))
        try service.markDirty(localId: id.uuidString)

        let firstPushStarted = AsyncGate()
        let releaseFirstPush = AsyncGate()
        backend.upsertHandler = { payload in
            if payload.localId == id.uuidString, payload.markdownBody == "v1" {
                firstPushStarted.open()
                await releaseFirstPush.wait()
            }
        }

        let drainTask = Task {
            await service.runOnce()
        }
        await firstPushStarted.wait()

        store.put(note: makeNote(id: id, body: "v2"))
        try service.markDirty(localId: id.uuidString)
        releaseFirstPush.open()
        await drainTask.value

        XCTAssertEqual(backend.upsertedPayloads.map(\.markdownBody), ["v1", "v2"])
        XCTAssertTrue(try outbox.pending().isEmpty)
    }

    func testSummaryUpdateIsPersistedToSession() async {
        let store = SyncFixtureStore()
        let backend = MockSyncBackend(accountState: .signedIn(email: "luis@example.test"))
        let service = makeService(store: store, backend: backend)
        let localId = "55555555-5555-5555-5555-555555555555"

        let listener = Task {
            await service.consumeSummaryUpdates()
        }
        backend.emitSummaryUpdate(
            SummaryUpdate(
                localId: localId,
                text: "Server summary",
                contentHash: "hash-1",
                crmPushStatus: .pushed
            )
        )
        backend.finishSummaryUpdates()
        await listener.value

        XCTAssertEqual(store.persistedSummaries, [localId: "Server summary"])
        XCTAssertEqual(store.persistedSummaryContentHashes, [localId: "hash-1"])
        XCTAssertEqual(store.persistedCrmPushStatuses, [localId: .pushed])
    }

    func testSummaryFailureIsPersistedWithoutWritingSummary() async {
        let store = SyncFixtureStore()
        let backend = MockSyncBackend(accountState: .signedIn(email: "luis@example.test"))
        let service = makeService(store: store, backend: backend)
        let localId = "56565656-5656-5656-5656-565656565656"

        let listener = Task {
            await service.consumeSummaryUpdates()
        }
        backend.emitSummaryUpdate(
            SummaryUpdate(
                localId: localId,
                status: .failed,
                message: "OpenRouter summary request failed: 502",
                contentHash: "hash-failed"
            )
        )
        backend.finishSummaryUpdates()
        await listener.value

        XCTAssertTrue(store.persistedSummaries.isEmpty)
        XCTAssertEqual(store.persistedSummaryFailures, [
            localId: "OpenRouter summary request failed: 502"
        ])
        XCTAssertEqual(store.persistedSummaryFailureContentHashes, [
            localId: "hash-failed"
        ])
    }

    func testPeopleCacheRefreshNotifiesAfterSnapshotWrite() async throws {
        let store = SyncFixtureStore()
        let backend = MockSyncBackend(accountState: .signedIn(email: "luis@example.test"))
        backend.peopleSnapshot = [
            ConvexCachedPerson(
                remoteId: "person-1",
                name: "Ada Lovelace",
                emails: ["ada@example.com"]
            )
        ]
        let peopleCache = ConvexPeopleCacheSource(rootURL: tempDir)
        let refreshCounter = LockedCounter()
        let service = makeService(
            store: store,
            backend: backend,
            peopleCacheSource: peopleCache,
            peopleCacheDidRefresh: {
                refreshCounter.increment()
            }
        )

        await service.runOnce()

        XCTAssertEqual(peopleCache.allPeople(), [
            Person(
                name: "Ada Lovelace",
                emails: ["ada@example.com"],
                sourceRefs: [SourceRef(provider: "crm", remoteId: "person-1")]
            )
        ])
        XCTAssertEqual(refreshCounter.value, 1)
    }

    func testSignedOutDoesNotSubscribeToSummaryUpdates() async {
        let store = SyncFixtureStore()
        let backend = MockSyncBackend(accountState: .signedOut)
        let service = makeService(store: store, backend: backend)

        await service.consumeSummaryUpdates()

        XCTAssertEqual(backend.summarySubscriptionCount, 0)
    }

    private func makeService(
        store: SyncFixtureStore,
        backend: MockSyncBackend,
        outbox: SyncOutbox? = nil,
        peopleCacheSource: ConvexPeopleCacheSource? = nil,
        peopleCacheDidRefresh: (@Sendable () -> Void)? = nil,
        sleep: (@Sendable (TimeInterval) async -> Void)? = nil
    ) -> SyncService {
        SyncService(
            backend: backend,
            outbox: outbox ?? SyncOutbox(rootURL: tempDir),
            loadSession: { try store.loadSession(localId: $0) },
            loadNote: { try store.loadNote(localId: $0) },
            persistSummary: { localId, text, contentHash in
                try store.persistSummary(localId: localId, text: text, contentHash: contentHash)
            },
            persistSummaryFailure: { localId, message, contentHash in
                store.persistSummaryFailure(localId: localId, message: message, contentHash: contentHash)
            },
            persistCrmPushStatus: { localId, status in try store.persistCrmPushStatus(localId: localId, status: status) },
            peopleCacheSource: peopleCacheSource,
            peopleCacheDidRefresh: peopleCacheDidRefresh,
            sleep: sleep ?? { _ in }
        )
    }

    private func makeSession(
        id: UUID,
        title: String = "Sync Meeting",
        localOnly: Bool? = nil
    ) -> MeetingSession {
        MeetingSession(
            id: id,
            title: title,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            status: .stopped,
            transcriptSegments: [
                TranscriptSegment(timestamp: 0, speaker: "Alice", text: "Hello")
            ],
            localOnly: localOnly
        )
    }

    private func makeNote(
        id: UUID,
        body: String = "body",
        localOnly: Bool? = nil
    ) -> MeetingNote {
        MeetingNote(
            id: id.uuidString,
            title: "Sync Meeting",
            date: Date(timeIntervalSince1970: 1_800_000_000),
            participants: [
                NoteTakrKit.Participant(name: "Alice", email: "alice@example.test")
            ],
            localOnly: localOnly,
            body: body
        )
    }
}

private final class SyncFixtureStore: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [String: MeetingSession] = [:]
    private var notes: [String: MeetingNote] = [:]
    private(set) var persistedSummaries: [String: String] = [:]
    private(set) var persistedSummaryContentHashes: [String: String] = [:]
    private(set) var persistedSummaryFailures: [String: String] = [:]
    private(set) var persistedSummaryFailureContentHashes: [String: String] = [:]
    private(set) var persistedCrmPushStatuses: [String: CrmPushStatus] = [:]

    func put(session: MeetingSession) {
        lock.withLock {
            sessions[session.id.uuidString] = session
        }
    }

    func put(note: MeetingNote) {
        lock.withLock {
            notes[note.id] = note
        }
    }

    func loadSession(localId: String) throws -> MeetingSession? {
        lock.withLock {
            sessions[localId]
        }
    }

    func loadNote(localId: String) throws -> MeetingNote? {
        lock.withLock {
            notes[localId]
        }
    }

    func persistSummary(localId: String, text: String, contentHash: String?) throws {
        lock.withLock {
            persistedSummaries[localId] = text
            if let contentHash {
                persistedSummaryContentHashes[localId] = contentHash
            }
        }
    }

    func persistSummaryFailure(localId: String, message: String, contentHash: String?) {
        lock.withLock {
            persistedSummaryFailures[localId] = message
            if let contentHash {
                persistedSummaryFailureContentHashes[localId] = contentHash
            }
        }
    }

    func persistCrmPushStatus(localId: String, status: CrmPushStatus) throws {
        lock.withLock {
            persistedCrmPushStatuses[localId] = status
        }
    }
}

private final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedDelays: [TimeInterval] = []

    var delays: [TimeInterval] {
        lock.withLock { recordedDelays }
    }

    func record(_ delay: TimeInterval) {
        lock.withLock {
            recordedDelays.append(delay)
        }
    }
}

private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResume: Bool = lock.withLock {
                if isOpen {
                    return true
                }
                self.continuation = continuation
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func open() {
        let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
            isOpen = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume()
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock {
            count += 1
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
