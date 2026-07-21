import XCTest
@testable import NoteTakrKit

final class EventPickerSupportTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testDefaultWindowSpansTodayMinusSevenThroughTodayPlusSeven() throws {
        let now = try date(2026, 6, 20, 14, 30)
        let window = EventPickerWindow.defaultWindow(now: now, calendar: calendar)

        XCTAssertEqual(window.start, try date(2026, 6, 13, 0, 0))
        XCTAssertEqual(window.end, try date(2026, 6, 28, 0, 0))
    }

    func testExtendingWindowMovesOneWeekAtATime() throws {
        let window = EventPickerWindow(
            start: try date(2026, 6, 13, 0, 0),
            end: try date(2026, 6, 28, 0, 0)
        )

        XCTAssertEqual(
            window.extendingEarlier(calendar: calendar).start,
            try date(2026, 6, 6, 0, 0)
        )
        XCTAssertEqual(
            window.extendingLater(calendar: calendar).end,
            try date(2026, 7, 5, 0, 0)
        )
    }

    func testFilteringSearchesUsefulFieldsAndSortsChronologically() throws {
        let window = EventPickerWindow(
            start: try date(2026, 6, 13, 0, 0),
            end: try date(2026, 6, 28, 0, 0)
        )
        let later = event(id: "later", title: "Planning", start: try date(2026, 6, 21, 9, 0))
        let earlier = event(
            id: "earlier",
            title: "Design Crit",
            start: try date(2026, 6, 18, 16, 0),
            participants: [Participant(name: "Anaïs", email: "anais@example.com")]
        )
        let outside = event(id: "outside", title: "Design Review", start: try date(2026, 6, 28, 0, 0))

        let filtered = EventPickerFiltering.events(
            [later, outside, earlier],
            in: window,
            query: "anais"
        )

        XCTAssertEqual(filtered.map(\.id), ["earlier"])
    }

    func testFilteringKeepsLoadedPastAndFutureEventsWhenQueryIsEmpty() throws {
        let window = EventPickerWindow(
            start: try date(2026, 6, 13, 0, 0),
            end: try date(2026, 6, 28, 0, 0)
        )
        let past = event(id: "past", title: "Past", start: try date(2026, 6, 14, 10, 0))
        let future = event(id: "future", title: "Future", start: try date(2026, 6, 27, 23, 30))

        let filtered = EventPickerFiltering.events([future, past], in: window, query: "")

        XCTAssertEqual(filtered.map(\.id), ["past", "future"])
    }

    func testFocusPrefersCurrentEventThenNextThenMostRecent() throws {
        let now = try date(2026, 6, 20, 12, 0)
        let past = UpcomingEvent(
            id: "past",
            title: "Past",
            start: try date(2026, 6, 20, 9, 0),
            end: try date(2026, 6, 20, 10, 0)
        )
        let current = UpcomingEvent(
            id: "current",
            title: "Current",
            start: try date(2026, 6, 20, 11, 30),
            end: try date(2026, 6, 20, 12, 30)
        )
        let future = UpcomingEvent(
            id: "future",
            title: "Future",
            start: try date(2026, 6, 20, 13, 0)
        )

        XCTAssertEqual(EventPickerSelection.focusedIndex(in: [past, current, future], now: now), 1)
        XCTAssertEqual(EventPickerSelection.focusedIndex(in: [past, future], now: now), 1)
        XCTAssertEqual(EventPickerSelection.focusedIndex(in: [past], now: now), 0)
        XCTAssertNil(EventPickerSelection.focusedIndex(in: [], now: now))
    }

    func testDotStateUsesEventEndToIdentifyCurrentEvent() throws {
        let now = try date(2026, 6, 20, 12, 0)
        let current = UpcomingEvent(
            id: "current",
            title: "Current",
            start: try date(2026, 6, 20, 11, 30),
            end: try date(2026, 6, 20, 12, 30)
        )
        let past = event(id: "past", title: "Past", start: try date(2026, 6, 20, 10, 0))
        let future = event(id: "future", title: "Future", start: try date(2026, 6, 20, 13, 0))

        XCTAssertEqual(EventPickerSelection.dotState(for: current, now: now), .current)
        XCTAssertEqual(EventPickerSelection.dotState(for: past, now: now), .past)
        XCTAssertEqual(EventPickerSelection.dotState(for: future, now: now), .upcoming)
    }

    func testFocusPrefersMostRecentlyStartedWhenCurrentEventsOverlap() throws {
        let now = try date(2026, 6, 20, 12, 0)
        let allDay = UpcomingEvent(
            id: "all-day",
            title: "All day",
            start: try date(2026, 6, 20, 0, 0),
            end: try date(2026, 6, 21, 0, 0)
        )
        let actualMeeting = UpcomingEvent(
            id: "actual",
            title: "Actual meeting",
            start: try date(2026, 6, 20, 11, 45),
            end: try date(2026, 6, 20, 12, 30)
        )

        XCTAssertEqual(
            EventPickerSelection.focusedIndex(in: [allDay, actualMeeting], now: now),
            1
        )
    }

    func testDateTimeEditingRejectsUnsubmittedEndBeforeStart() throws {
        let start = try date(2026, 6, 20, 10, 0)
        let priorValidEnd = try date(2026, 6, 20, 11, 0)

        let resolved = DateTimeEditing.resolve(
            startDate: start,
            startTimeText: "10:00",
            endDate: priorValidEnd,
            endTimeText: "09:30",
            hasEnd: true,
            calendar: calendar
        )

        XCTAssertNil(resolved, "Validation must include HH:mm text even before TextField submit")
    }

    func testDateTimeEditingAppliesBothPendingTimeFieldsAtomically() throws {
        let resolved = try XCTUnwrap(DateTimeEditing.resolve(
            startDate: date(2026, 6, 20, 10, 0),
            startTimeText: "13:15",
            endDate: date(2026, 6, 20, 11, 0),
            endTimeText: "14:45",
            hasEnd: true,
            calendar: calendar
        ))

        XCTAssertEqual(resolved.start, try date(2026, 6, 20, 13, 15))
        XCTAssertEqual(resolved.end, try date(2026, 6, 20, 14, 45))
    }

    func testDateTimeEditingRejectsMalformedTimeText() throws {
        XCTAssertNil(DateTimeEditing.applying(
            timeText: "10:",
            to: try date(2026, 6, 20, 10, 0),
            calendar: calendar
        ))
    }

    private func event(
        id: String,
        title: String,
        start: Date,
        participants: [Participant] = []
    ) -> UpcomingEvent {
        UpcomingEvent(id: id, title: title, start: start, participants: participants)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return try XCTUnwrap(components.date)
    }
}
