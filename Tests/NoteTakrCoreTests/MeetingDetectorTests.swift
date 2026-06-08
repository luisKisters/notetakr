import XCTest
@testable import NoteTakrCore

final class MeetingDetectorTests: XCTestCase {

    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEvent(
        title: String,
        urlString: String? = nil,
        notes: String? = nil,
        offsetSeconds: TimeInterval = 0
    ) -> CalendarEvent {
        CalendarEvent(
            id: UUID().uuidString,
            title: title,
            startDate: baseDate.addingTimeInterval(offsetSeconds),
            endDate: baseDate.addingTimeInterval(offsetSeconds + 3600),
            url: urlString.flatMap { URL(string: $0) },
            notes: notes
        )
    }

    // MARK: - URL matching

    func testURLMatchGoogleMeet() {
        let event = makeEvent(title: "Team Catch-up", urlString: "https://meet.google.com/abc-defg-hij")
        let result = MeetingDetector.score(event)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.score, 10)
        if case .urlMatch(let provider) = result?.detectedVia {
            XCTAssertEqual(provider, "Google Meet")
        } else {
            XCTFail("Expected urlMatch")
        }
    }

    func testURLMatchZoomJoin() {
        let event = makeEvent(title: "Architecture session", urlString: "https://zoom.us/j/12345678")
        let result = MeetingDetector.score(event)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.score, 10)
        if case .urlMatch(let provider) = result?.detectedVia {
            XCTAssertEqual(provider, "Zoom")
        } else {
            XCTFail("Expected urlMatch")
        }
    }

    func testURLMatchZoomPersonal() {
        let event = makeEvent(title: "Pair session", urlString: "https://zoom.us/my/johndoe")
        let result = MeetingDetector.score(event)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.score, 10)
        if case .urlMatch(let provider) = result?.detectedVia {
            XCTAssertEqual(provider, "Zoom")
        } else {
            XCTFail("Expected urlMatch")
        }
    }

    func testURLMatchMicrosoftTeams() {
        let event = makeEvent(title: "Sprint Review", urlString: "https://teams.microsoft.com/l/meetup-join/abc")
        let result = MeetingDetector.score(event)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.score, 10)
        if case .urlMatch(let provider) = result?.detectedVia {
            XCTAssertEqual(provider, "Microsoft Teams")
        } else {
            XCTFail("Expected urlMatch")
        }
    }

    func testURLMatchInNotes() {
        let event = makeEvent(
            title: "Weekly catch-up",
            notes: "Join via https://meet.google.com/xyz-abc"
        )
        let result = MeetingDetector.score(event)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.score, 10)
    }

    // MARK: - Keyword matching

    func testKeywordStandup() {
        let event = makeEvent(title: "Daily Standup")
        let result = MeetingDetector.score(event)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.score, 0)
        if case .keyword(let kw) = result?.detectedVia {
            XCTAssertEqual(kw, "standup")
        } else {
            XCTFail("Expected keyword detection")
        }
    }

    func testKeywordSync() {
        let event = makeEvent(title: "Weekly Sync")
        let result = MeetingDetector.score(event)
        XCTAssertNotNil(result)
        if case .keyword(let kw) = result?.detectedVia {
            XCTAssertEqual(kw, "sync")
        } else {
            XCTFail("Expected keyword detection")
        }
    }

    func testKeywordMeeting() {
        let event = makeEvent(title: "All Hands Meeting")
        let result = MeetingDetector.score(event)
        XCTAssertNotNil(result)
    }

    func testKeywordInterview() {
        let event = makeEvent(title: "Interview with Alice")
        let result = MeetingDetector.score(event)
        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(result!.score, 3)
    }

    func testKeywordCall() {
        let event = makeEvent(title: "Quick Call")
        let result = MeetingDetector.score(event)
        XCTAssertNotNil(result)
    }

    func testKeywordOneOnOne() {
        let event = makeEvent(title: "1:1 with Manager")
        let result = MeetingDetector.score(event)
        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(result!.score, 3)
    }

    // MARK: - Non-meeting events

    func testNonMeetingLunch() {
        let event = makeEvent(title: "Lunch")
        XCTAssertNil(MeetingDetector.score(event))
    }

    func testNonMeetingBirthday() {
        let event = makeEvent(title: "Alice's Birthday")
        XCTAssertNil(MeetingDetector.score(event))
    }

    func testNonMeetingBlocker() {
        let event = makeEvent(title: "Focus Time")
        XCTAssertNil(MeetingDetector.score(event))
    }

    // MARK: - Empty calendar

    func testEmptyCalendarReturnsNoMeetings() {
        XCTAssertTrue(MeetingDetector.detectMeetings(from: []).isEmpty)
    }

    func testEmptyCalendarNextMeetingNil() {
        XCTAssertNil(MeetingDetector.nextMeeting(from: [], after: Date()))
    }

    // MARK: - Sorting

    func testDetectedMeetingsSortedByStartDate() {
        let late = makeEvent(title: "Late Standup", offsetSeconds: 7200)
        let early = makeEvent(title: "Early Meeting", urlString: "https://meet.google.com/x", offsetSeconds: 0)
        let middle = makeEvent(title: "Midday Sync", offsetSeconds: 3600)

        let results = MeetingDetector.detectMeetings(from: [late, early, middle])
        XCTAssertEqual(results.count, 3)
        XCTAssertLessThanOrEqual(results[0].event.startDate, results[1].event.startDate)
        XCTAssertLessThanOrEqual(results[1].event.startDate, results[2].event.startDate)
    }

    // MARK: - URL match takes precedence over keyword

    func testURLMatchTakesPrecedenceOverKeyword() {
        let event = makeEvent(
            title: "Standup call sync meeting",
            urlString: "https://meet.google.com/abc"
        )
        let result = MeetingDetector.score(event)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.score, 10)
        if case .urlMatch = result?.detectedVia {
            // expected
        } else {
            XCTFail("Expected URL match to take precedence")
        }
    }

    // MARK: - nextMeeting filter

    func testNextMeetingAfterGivenDate() {
        let past = makeEvent(title: "Past Standup", offsetSeconds: -3600)
        let future1 = makeEvent(title: "Future Sync", offsetSeconds: 1800)
        let future2 = makeEvent(title: "Later Meeting", offsetSeconds: 5400)

        let next = MeetingDetector.nextMeeting(from: [past, future1, future2], after: baseDate)
        XCTAssertNotNil(next)
        XCTAssertEqual(next?.event.title, "Future Sync")
    }

    func testNextMeetingAllInPastReturnsNil() {
        let e1 = makeEvent(title: "Old Standup", offsetSeconds: -7200)
        let e2 = makeEvent(title: "Older Meeting", offsetSeconds: -3600)
        let next = MeetingDetector.nextMeeting(from: [e1, e2], after: baseDate)
        XCTAssertNil(next)
    }

    // MARK: - Mock adapter

    func testMockAdapterGrantsAccess() async throws {
        let adapter = MockCalendarAdapter(accessGranted: true)
        try await adapter.requestAccess()
    }

    func testMockAdapterDeniesAccess() async {
        let adapter = MockCalendarAdapter(accessGranted: false)
        do {
            try await adapter.requestAccess()
            XCTFail("Expected error")
        } catch CalendarError.accessDenied {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMockAdapterFiltersEventsByDateRange() async throws {
        let inside = makeEvent(title: "Team Meeting", offsetSeconds: 1800)
        let outside = makeEvent(title: "Old Standup", offsetSeconds: -3600)
        let adapter = MockCalendarAdapter(events: [inside, outside])

        let from = baseDate
        let to = baseDate.addingTimeInterval(3600)
        let results = try await adapter.fetchUpcomingEvents(from: from, to: to)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Team Meeting")
    }
}
