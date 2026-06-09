import XCTest
@testable import NoteTakrCore

final class MeetingModeTests: XCTestCase {

    // MARK: - MeetingTitleResolver

    func testResolvePrefersExplicitMeetingName() {
        let title = MeetingTitleResolver.resolve(
            meetingName: "Weekly Sync",
            calendarEventTitle: "Some Calendar Event"
        )
        XCTAssertEqual(title, "Weekly Sync")
    }

    func testResolveFallsBackToCalendarEvent() {
        let title = MeetingTitleResolver.resolve(
            meetingName: nil,
            calendarEventTitle: "Design Review"
        )
        XCTAssertEqual(title, "Design Review")
    }

    func testResolveTreatsWhitespaceMeetingNameAsEmpty() {
        let title = MeetingTitleResolver.resolve(
            meetingName: "   ",
            calendarEventTitle: "Design Review"
        )
        XCTAssertEqual(title, "Design Review")
    }

    func testResolveFallsBackToUnnamedMeeting() {
        let title = MeetingTitleResolver.resolve(
            meetingName: nil,
            calendarEventTitle: nil
        )
        XCTAssertEqual(title, "Unnamed Meeting")
    }

    func testResolveFromEventConvenience() {
        let event = CalendarEvent(
            id: "1",
            title: "Standup",
            startDate: Date(),
            endDate: Date().addingTimeInterval(900)
        )
        XCTAssertEqual(MeetingTitleResolver.resolve(meetingName: nil, event: event), "Standup")
        XCTAssertEqual(MeetingTitleResolver.resolve(meetingName: nil, event: nil), "Unnamed Meeting")
    }

    // MARK: - MeetingMode

    func testOnlineCapturesSystemAudio() {
        XCTAssertTrue(MeetingMode.online.capturesSystemAudio)
    }

    func testInPersonDoesNotCaptureSystemAudio() {
        XCTAssertFalse(MeetingMode.inPerson.capturesSystemAudio)
    }

    // MARK: - Session persistence

    func testSessionDefaultsToOnlineMode() {
        let session = MeetingSession(title: "Test", date: Date())
        XCTAssertEqual(session.meetingMode, .online)
    }

    func testSessionMeetingModeRoundTrips() throws {
        let session = MeetingSession(title: "Room Chat", date: Date(), meetingMode: .inPerson)
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(MeetingSession.self, from: data)
        XCTAssertEqual(decoded.meetingMode, .inPerson)
    }

    func testLegacySessionWithoutMeetingModeDecodesAsOnline() throws {
        // Simulates a session.json written before meetingMode existed.
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Legacy",
          "date": 0,
          "status": "stopped",
          "transcriptSegments": [],
          "personalNotes": "",
          "audioFilePaths": []
        }
        """
        let decoded = try JSONDecoder().decode(MeetingSession.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.meetingMode, .online)
    }
}
