import XCTest
import NoteTakrCore
import NoteTakrKit
@testable import NoteTakrSync

final class SyncEnvelopeTests: XCTestCase {
    func testPayloadCarriesAllContentFields() throws {
        let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let startedAt = Date(timeIntervalSince1970: 1_774_200_600)
        let session = MeetingSession(
            id: sessionID,
            title: "Session Title",
            date: startedAt,
            status: .stopped,
            transcriptSegments: [
                TranscriptSegment(timestamp: 1.5, speaker: "Alice", text: "Hello"),
                TranscriptSegment(timestamp: 62, speaker: nil, text: "No speaker")
            ],
            linkedEventID: "evt_session",
            participants: [
                NoteTakrCore.Participant(name: "Ignored", email: "ignored@example.com")
            ]
        )
        let note = MeetingNote(
            id: sessionID.uuidString,
            title: "Edited Note Title",
            date: startedAt.addingTimeInterval(30),
            calendarEvent: "evt_note",
            participants: [
                NoteTakrKit.Participant(name: "Alice", email: "alice@example.com"),
                NoteTakrKit.Participant(name: "Bob")
            ],
            crmPushOptOut: true,
            body: "## Notes\n\nDecision made."
        )

        let payload = try SyncEnvelope.payload(session: session, note: note)

        XCTAssertEqual(payload.localId, sessionID.uuidString)
        XCTAssertEqual(payload.title, "Edited Note Title")
        XCTAssertEqual(payload.startedAt, note.date)
        XCTAssertEqual(payload.calendarEventId, "evt_note")
        XCTAssertEqual(payload.participants, [
            MeetingPayload.Participant(name: "Alice", email: "alice@example.com"),
            MeetingPayload.Participant(name: "Bob", email: nil)
        ])
        XCTAssertEqual(payload.markdownBody, "## Notes\n\nDecision made.")
        XCTAssertEqual(payload.crmPushOptOut, true)
        XCTAssertEqual(payload.transcriptSegments, [
            MeetingPayload.TranscriptSegment(seq: 0, startMs: 1_500, speaker: "Alice", text: "Hello"),
            MeetingPayload.TranscriptSegment(seq: 1, startMs: 62_000, speaker: nil, text: "No speaker")
        ])
        XCTAssertFalse(payload.contentHash.isEmpty)
    }

    func testContentHashIsStableForEqualContent() throws {
        let first = try SyncEnvelope.payload(session: fixtureSession(), note: fixtureNote())
        let second = try SyncEnvelope.payload(session: fixtureSession(), note: fixtureNote())

        XCTAssertEqual(first.contentHash, second.contentHash)
    }

    func testContentHashChangesWhenBodyChanges() throws {
        let original = try SyncEnvelope.payload(session: fixtureSession(), note: fixtureNote())
        var edited = fixtureNote()
        edited.body = "Changed body"

        let changed = try SyncEnvelope.payload(session: fixtureSession(), note: edited)

        XCTAssertNotEqual(original.contentHash, changed.contentHash)
    }

    func testContentHashChangesWhenCrmPushOptOutChanges() throws {
        let original = try SyncEnvelope.payload(session: fixtureSession(), note: fixtureNote())
        var edited = fixtureNote()
        edited.crmPushOptOut = true

        let changed = try SyncEnvelope.payload(session: fixtureSession(), note: edited)

        XCTAssertNotEqual(original.contentHash, changed.contentHash)
        XCTAssertEqual(changed.crmPushOptOut, true)
    }

    private func fixtureSession() -> MeetingSession {
        MeetingSession(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            title: "Planning",
            date: Date(timeIntervalSince1970: 1_774_200_000),
            status: .stopped,
            transcriptSegments: [
                TranscriptSegment(timestamp: 0, speaker: "Luis", text: "Kickoff"),
                TranscriptSegment(timestamp: 12.25, speaker: "Mina", text: "Next step")
            ],
            linkedEventID: "calendar-1"
        )
    }

    private func fixtureNote() -> MeetingNote {
        MeetingNote(
            id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            title: "Planning",
            date: Date(timeIntervalSince1970: 1_774_200_000),
            calendarEvent: "calendar-1",
            participants: [
                NoteTakrKit.Participant(name: "Luis", email: "luis@example.com"),
                NoteTakrKit.Participant(name: "Mina", email: "mina@example.com")
            ],
            body: "Initial body"
        )
    }
}
