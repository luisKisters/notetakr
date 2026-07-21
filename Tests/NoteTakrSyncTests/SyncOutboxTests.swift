import XCTest
import NoteTakrCore
import NoteTakrKit
@testable import NoteTakrSync

final class SyncOutboxTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncOutboxTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testEnqueuePersistsFileAndPendingReturnsIt() throws {
        let outbox = SyncOutbox(rootURL: tempDir)
        let payload = try makePayload(localId: "11111111-1111-1111-1111-111111111111")

        try outbox.enqueue(payload)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outbox.fileURL(for: payload.localId).path))
        let pending = try outbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first, payload)
    }

    func testEnqueueSameLocalIdOverwrites() throws {
        let outbox = SyncOutbox(rootURL: tempDir)
        let first = try makePayload(localId: "22222222-2222-2222-2222-222222222222", body: "v1")
        let second = try makePayload(localId: "22222222-2222-2222-2222-222222222222", body: "v2")

        try outbox.enqueue(first)
        try outbox.enqueue(second)

        let pending = try outbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.contentHash, second.contentHash)
        XCTAssertEqual(pending.first?.markdownBody, "v2")
    }

    func testPendingSurvivesReinitialization() throws {
        let firstOutbox = SyncOutbox(rootURL: tempDir)
        let payload = try makePayload(localId: "33333333-3333-3333-3333-333333333333")

        try firstOutbox.enqueue(payload)
        let secondOutbox = SyncOutbox(rootURL: tempDir)

        XCTAssertEqual(try secondOutbox.pending(), [payload])
    }

    func testCompleteRemovesItem() throws {
        let outbox = SyncOutbox(rootURL: tempDir)
        let payload = try makePayload(localId: "44444444-4444-4444-4444-444444444444")
        try outbox.enqueue(payload)

        try outbox.complete(localId: payload.localId)

        XCTAssertFalse(FileManager.default.fileExists(atPath: outbox.fileURL(for: payload.localId).path))
        XCTAssertTrue(try outbox.pending().isEmpty)
    }

    func testEnqueueDeleteOverwritesPendingPayload() throws {
        let outbox = SyncOutbox(rootURL: tempDir)
        let payload = try makePayload(localId: "45454545-4545-4545-4545-454545454545")
        try outbox.enqueue(payload)

        try outbox.enqueueDelete(localId: payload.localId)

        XCTAssertTrue(try outbox.pending().isEmpty)
        XCTAssertEqual(try outbox.pendingOperations(), [.delete(localId: payload.localId)])
    }

    func testPathLikeLocalIdStaysInsideOutbox() throws {
        let outbox = SyncOutbox(rootURL: tempDir)
        let payload = MeetingPayload(
            localId: "../escape",
            title: "Unsafe",
            startedAt: Date(timeIntervalSince1970: 1_774_200_000),
            markdownBody: "body",
            contentHash: "hash"
        )
        let escapedURL = outbox.outboxURL
            .appendingPathComponent("../escape.json")
            .standardizedFileURL

        try outbox.enqueue(payload)

        XCTAssertFalse(FileManager.default.fileExists(atPath: escapedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outbox.fileURL(for: payload.localId).path))
        XCTAssertTrue(
            outbox.fileURL(for: payload.localId)
                .standardizedFileURL
                .path
                .hasPrefix(outbox.outboxURL.standardizedFileURL.path + "/")
        )
    }

    func testCompleteWithPathLikeLocalIdDoesNotRemoveOutsideOutbox() throws {
        let outbox = SyncOutbox(rootURL: tempDir)
        try FileManager.default.createDirectory(at: outbox.outboxURL, withIntermediateDirectories: true)
        let escapedURL = outbox.outboxURL
            .appendingPathComponent("../escape.json")
            .standardizedFileURL
        try Data("sentinel".utf8).write(to: escapedURL)

        try outbox.complete(localId: "../escape")

        XCTAssertTrue(FileManager.default.fileExists(atPath: escapedURL.path))
    }

    private func makePayload(localId: String, body: String = "body") throws -> MeetingPayload {
        let id = UUID(uuidString: localId)!
        let session = MeetingSession(
            id: id,
            title: "Outbox",
            date: Date(timeIntervalSince1970: 1_774_200_000),
            status: .stopped,
            transcriptSegments: [
                TranscriptSegment(timestamp: 0, speaker: "Alice", text: "Hello")
            ]
        )
        let note = MeetingNote(
            id: localId,
            title: "Outbox",
            date: Date(timeIntervalSince1970: 1_774_200_000),
            participants: [
                NoteTakrKit.Participant(name: "Alice", email: "alice@example.com")
            ],
            body: body
        )
        return try SyncEnvelope.payload(session: session, note: note)
    }
}
