import XCTest
@testable import NoteTakrCore

final class SpeakerLabelResolverTests: XCTestCase {
    func testSeveralMeaningfulInRoomVoicesStayAnonymousAndShowAsMicrophoneSpeakers() {
        let session = MeetingSession(title: "Room", date: Date(), inPerson: true)
        let resolved = SpeakerLabelResolver.resolve(
            segments: [
                segment("Speaker 1", words: 51),
                segment("Speaker 2", words: 80),
            ],
            session: session,
            userName: "Luis",
            inferNamesFromCalendar: true
        )

        XCTAssertEqual(resolved.map(\.speaker), ["In-room speaker 1", "In-room speaker 2"])
        XCTAssertTrue(SpeakerLabelResolver.hasMultipleInRoomSpeakers(resolved))
    }

    func testFiftyWordInterjectionDoesNotTriggerMultipleInRoomDetection() {
        let session = MeetingSession(title: "Room", date: Date(), inPerson: true)
        let resolved = SpeakerLabelResolver.resolve(
            segments: [
                segment("Speaker 1", words: 51),
                segment("Speaker 2", words: 50),
            ],
            session: session,
            userName: "Luis",
            inferNamesFromCalendar: true
        )

        XCTAssertEqual(resolved[0].speaker, "Luis (You)")
        XCTAssertEqual(resolved[1].speaker, "Speaker 2")
        XCTAssertFalse(SpeakerLabelResolver.hasMultipleInRoomSpeakers(resolved))
    }

    func testSoleCalendarParticipantNamesTheOnlyMeaningfulInRoomVoice() {
        let session = MeetingSession(
            title: "Coffee",
            date: Date(),
            participants: [Participant(name: "Anna")],
            inPerson: true
        )
        let resolved = SpeakerLabelResolver.resolve(
            segments: [segment("Speaker 1", words: 70)],
            session: session,
            userName: "Luis",
            inferNamesFromCalendar: true
        )

        XCTAssertEqual(resolved[0].speaker, "Anna")
    }

    func testRemoteOneOnOneUsesConfiguredNameAndSoleOtherCalendarAttendee() {
        let session = MeetingSession(
            title: "Call",
            date: Date(),
            participants: [Participant(name: "Luis Kisters"), Participant(name: "Anna")],
            inPerson: false
        )
        let resolved = SpeakerLabelResolver.resolve(
            segments: [
                segment("Speaker 1 (You)", words: 12),
                segment("Speaker 2", words: 65),
            ],
            session: session,
            userName: "Luis",
            inferNamesFromCalendar: true
        )

        XCTAssertEqual(resolved.map(\.speaker), ["Luis (You)", "Anna"])
    }

    func testRemoteCallDoesNotGuessCalendarNameWhenSeveralOthersSpeakMeaningfully() {
        let session = MeetingSession(
            title: "Call",
            date: Date(),
            participants: [Participant(name: "Anna")],
            inPerson: false
        )
        let resolved = SpeakerLabelResolver.resolve(
            segments: [
                segment("Speaker 1 (You)", words: 12),
                segment("Speaker 2", words: 51),
                segment("Speaker 3", words: 60),
            ],
            session: session,
            userName: "Luis",
            inferNamesFromCalendar: true
        )

        XCTAssertEqual(resolved.map(\.speaker), ["Luis (You)", "Speaker 2", "Speaker 3"])
    }

    private func segment(_ speaker: String, words: Int) -> TranscriptSegment {
        TranscriptSegment(
            timestamp: 0,
            speaker: speaker,
            text: Array(repeating: "word", count: words).joined(separator: " ")
        )
    }
}
