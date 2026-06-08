import XCTest
import NoteTakrCore

final class SessionViewTests: XCTestCase {

    func testFixtureSessionCreation() {
        let session = MeetingSession(
            title: "Design Review",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            status: .stopped,
            transcriptSegments: [
                TranscriptSegment(timestamp: 0, speaker: "Alice", text: "Let's start."),
                TranscriptSegment(timestamp: 5.5, speaker: nil, text: "Agreed.")
            ],
            personalNotes: "Good discussion."
        )
        XCTAssertEqual(session.title, "Design Review")
        XCTAssertEqual(session.transcriptSegments.count, 2)
        XCTAssertEqual(session.status, .stopped)
        XCTAssertTrue(session.personalNotes.contains("Good"))
    }

    func testFixtureSessionsLoadFromStore() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteTakrViewTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SessionStore(baseURL: tempDir)
        let session1 = MeetingSession(title: "Meeting A", date: Date(timeIntervalSince1970: 1_700_000_000))
        let session2 = MeetingSession(title: "Meeting B", date: Date(timeIntervalSince1970: 1_700_100_000))
        try store.save(session1)
        try store.save(session2)

        let loaded = try store.loadAll()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].title, "Meeting B")
        XCTAssertEqual(loaded[1].title, "Meeting A")
    }

    func testAllStatusValues() {
        let statuses = SessionStatus.allCases
        XCTAssertEqual(statuses.count, 5)
    }
}
