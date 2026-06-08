import XCTest
@testable import NoteTakrCore

final class SessionModelTests: XCTestCase {

    func testSessionCreationDefaults() {
        let session = MeetingSession(title: "Team Standup", date: .distantPast)
        XCTAssertFalse(session.id.uuidString.isEmpty)
        XCTAssertEqual(session.title, "Team Standup")
        XCTAssertEqual(session.status, .idle)
        XCTAssertTrue(session.transcriptSegments.isEmpty)
        XCTAssertTrue(session.personalNotes.isEmpty)
        XCTAssertTrue(session.audioFilePaths.isEmpty)
    }

    func testSessionStatusTransitions() {
        var session = MeetingSession(title: "Test", date: .distantPast)
        XCTAssertEqual(session.status, .idle)
        session.status = .recording
        XCTAssertEqual(session.status, .recording)
        session.status = .paused
        XCTAssertEqual(session.status, .paused)
        session.status = .stopped
        XCTAssertEqual(session.status, .stopped)
        session.status = .failed
        XCTAssertEqual(session.status, .failed)
    }

    func testAllStatusCases() {
        let cases = SessionStatus.allCases
        XCTAssertTrue(cases.contains(.idle))
        XCTAssertTrue(cases.contains(.recording))
        XCTAssertTrue(cases.contains(.paused))
        XCTAssertTrue(cases.contains(.stopped))
        XCTAssertTrue(cases.contains(.failed))
        XCTAssertEqual(cases.count, 5)
    }

    func testSessionCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = MeetingSession(
            title: "Sync Meeting",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            status: .stopped,
            transcriptSegments: [
                TranscriptSegment(timestamp: 5.0, speaker: "Alice", text: "Hello"),
                TranscriptSegment(timestamp: 12.5, speaker: nil, text: "World")
            ],
            personalNotes: "Important discussion",
            audioFilePaths: ["/tmp/mic.m4a", "/tmp/sys.m4a"]
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MeetingSession.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.personalNotes, original.personalNotes)
        XCTAssertEqual(decoded.audioFilePaths, original.audioFilePaths)
        XCTAssertEqual(decoded.transcriptSegments.count, 2)
        XCTAssertEqual(decoded.transcriptSegments[0].speaker, "Alice")
        XCTAssertEqual(decoded.transcriptSegments[0].text, "Hello")
        XCTAssertNil(decoded.transcriptSegments[1].speaker)
    }

    func testTranscriptSegmentCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let segment = TranscriptSegment(timestamp: 12.5, speaker: "Bob", text: "World")
        let data = try encoder.encode(segment)
        let decoded = try decoder.decode(TranscriptSegment.self, from: data)
        XCTAssertEqual(decoded.id, segment.id)
        XCTAssertEqual(decoded.timestamp, 12.5)
        XCTAssertEqual(decoded.speaker, "Bob")
        XCTAssertEqual(decoded.text, "World")
    }

    func testTranscriptSegmentWithNilSpeaker() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let segment = TranscriptSegment(timestamp: 0, text: "No speaker")
        let data = try encoder.encode(segment)
        let decoded = try decoder.decode(TranscriptSegment.self, from: data)
        XCTAssertNil(decoded.speaker)
        XCTAssertEqual(decoded.text, "No speaker")
    }

    func testSessionMetadataFromSession() {
        let session = MeetingSession(
            title: "Demo",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            status: .stopped,
            transcriptSegments: [
                TranscriptSegment(timestamp: 0, text: "Hello"),
                TranscriptSegment(timestamp: 5, text: "World")
            ],
            personalNotes: "Some notes"
        )
        let meta = SessionMetadata(from: session, duration: 120)
        XCTAssertEqual(meta.title, "Demo")
        XCTAssertEqual(meta.transcriptSegmentCount, 2)
        XCTAssertEqual(meta.duration, 120)
        XCTAssertTrue(meta.hasPersonalNotes)
    }

    func testSessionMetadataNoNotes() {
        let session = MeetingSession(title: "Quick Call", date: .distantPast)
        let meta = SessionMetadata(from: session)
        XCTAssertFalse(meta.hasPersonalNotes)
        XCTAssertNil(meta.duration)
        XCTAssertEqual(meta.transcriptSegmentCount, 0)
    }

    func testSessionEquality() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let s1 = MeetingSession(id: id, title: "Meeting", date: date)
        let s2 = MeetingSession(id: id, title: "Meeting", date: date)
        XCTAssertEqual(s1, s2)
    }

    func testSessionInequalityOnTitle() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let s1 = MeetingSession(id: id, title: "Meeting A", date: date)
        let s2 = MeetingSession(id: id, title: "Meeting B", date: date)
        XCTAssertNotEqual(s1, s2)
    }
}
