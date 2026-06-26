import XCTest
@testable import NoteTakrCore

final class SessionStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: SessionStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteTakrTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = SessionStore(baseURL: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSaveAndLoadSession() throws {
        let session = MeetingSession(
            title: "Team Standup",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try store.save(session)
        let loaded = try store.load(id: session.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.title, "Team Standup")
        XCTAssertEqual(loaded?.id, session.id)
    }

    func testLoadAllEmpty() throws {
        let sessions = try store.loadAll()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testLoadAllFromNonExistentDir() throws {
        let store2 = SessionStore(baseURL: tempDir.appendingPathComponent("nonexistent"))
        let sessions = try store2.loadAll()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testLoadAllMultipleSortedNewestFirst() throws {
        let s1 = MeetingSession(title: "Standup", date: Date(timeIntervalSince1970: 1_700_000_000))
        let s2 = MeetingSession(title: "Retro", date: Date(timeIntervalSince1970: 1_700_100_000))
        try store.save(s1)
        try store.save(s2)
        let sessions = try store.loadAll()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].title, "Retro")
        XCTAssertEqual(sessions[1].title, "Standup")
    }

    func testFolderSanitization() {
        XCTAssertEqual(SessionStore.sanitizeTitle("Team Standup"), "Team-Standup")
        XCTAssertEqual(SessionStore.sanitizeTitle(""), "unnamed")
        XCTAssertEqual(SessionStore.sanitizeTitle("!!!"), "unnamed")
        XCTAssertEqual(SessionStore.sanitizeTitle("Q3 Review: Strategy!"), "Q3-Review-Strategy")
        XCTAssertEqual(SessionStore.sanitizeTitle("normal-title_123"), "normal-title_123")
    }

    func testDeterministicFolderName() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID(uuidString: "12345678-0000-0000-0000-000000000000")!
        let session = MeetingSession(id: id, title: "Standup", date: date)
        let name = SessionStore.folderName(for: session)
        XCTAssertTrue(name.hasPrefix("2023-11-"), "Expected ISO date prefix, got \(name)")
        XCTAssertTrue(name.contains("Standup"), "Expected title slug in \(name)")
        XCTAssertTrue(name.contains("12345678"), "Expected UUID prefix in \(name)")
    }

    func testDeleteSession() throws {
        let session = MeetingSession(
            title: "To Delete",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try store.save(session)
        XCTAssertEqual(try store.loadAll().count, 1)
        try store.delete(session)
        XCTAssertEqual(try store.loadAll().count, 0)
    }

    func testDeleteNonExistentSessionIsNoop() throws {
        let session = MeetingSession(title: "Ghost", date: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNoThrow(try store.delete(session))
    }

    func testReloadAfterRestart() throws {
        let session = MeetingSession(
            title: "Persisted",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            status: .stopped,
            personalNotes: "Notes here"
        )
        try store.save(session)

        let store2 = SessionStore(baseURL: tempDir)
        let loaded = try store2.load(id: session.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.personalNotes, "Notes here")
        XCTAssertEqual(loaded?.status, .stopped)
    }

    func testInterruptedSessionRecovery() throws {
        var recording = MeetingSession(
            title: "In Progress",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        recording.status = .recording

        var paused = MeetingSession(
            title: "Was Paused",
            date: Date(timeIntervalSince1970: 1_700_050_000)
        )
        paused.status = .paused

        let stopped = MeetingSession(
            title: "Already Done",
            date: Date(timeIntervalSince1970: 1_700_100_000),
            status: .stopped
        )

        try store.save(recording)
        try store.save(paused)
        try store.save(stopped)

        try store.recoverInterruptedSessions()

        let sessions = try store.loadAll()
        let byTitle = Dictionary(uniqueKeysWithValues: sessions.map { ($0.title, $0) })
        XCTAssertEqual(byTitle["In Progress"]?.status, .failed)
        XCTAssertEqual(byTitle["Was Paused"]?.status, .failed)
        XCTAssertEqual(byTitle["Already Done"]?.status, .stopped)
    }

    func testSessionNotFoundReturnsNil() throws {
        let result = try store.load(id: UUID())
        XCTAssertNil(result)
    }

    func testSavePreservesTranscriptSegments() throws {
        var session = MeetingSession(title: "With Transcript", date: Date(timeIntervalSince1970: 1_700_000_000))
        session.transcriptSegments = [
            TranscriptSegment(timestamp: 0, speaker: "Alice", text: "Hello"),
            TranscriptSegment(timestamp: 5, text: "World")
        ]
        try store.save(session)
        let loaded = try store.load(id: session.id)
        XCTAssertEqual(loaded?.transcriptSegments.count, 2)
        XCTAssertEqual(loaded?.transcriptSegments[0].speaker, "Alice")
        XCTAssertNil(loaded?.transcriptSegments[1].speaker)
    }

    func testRenameSpeakerPersistsMatchingSegmentsOnly() throws {
        var session = MeetingSession(title: "With Speakers", date: Date(timeIntervalSince1970: 1_700_000_000))
        session.transcriptSegments = [
            TranscriptSegment(timestamp: 0, speaker: "Speaker 1", text: "Hello"),
            TranscriptSegment(timestamp: 5, speaker: "Speaker 2", text: "World"),
            TranscriptSegment(timestamp: 10, speaker: "Speaker 1", text: "Again")
        ]
        try store.save(session)

        let updated = try store.renameSpeaker(in: session.id, from: "Speaker 1", to: "Connor")

        XCTAssertEqual(updated?.transcriptSegments.map(\.speaker), ["Connor", "Speaker 2", "Connor"])
        XCTAssertEqual(updated?.transcriptSegments.map(\.text), ["Hello", "World", "Again"])

        let loaded = try store.load(id: session.id)
        XCTAssertEqual(loaded?.transcriptSegments.map(\.speaker), ["Connor", "Speaker 2", "Connor"])
    }

    func testFolderSanitizationLongTitle() {
        let longTitle = String(repeating: "a", count: 100)
        let sanitized = SessionStore.sanitizeTitle(longTitle)
        XCTAssertLessThanOrEqual(sanitized.count, 64)
    }
}
