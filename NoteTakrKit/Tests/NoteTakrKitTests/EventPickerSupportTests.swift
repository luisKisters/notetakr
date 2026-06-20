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
