import XCTest
@testable import NoteTakrKit

final class PeopleIndexTests: XCTestCase {
    func testMergesPastNotesAndCalendarAttendeesByEmail() {
        let older = MeetingNote(
            id: "n1",
            title: "Older",
            date: date(2026, 6, 1),
            participants: [Participant(name: "Sarah Chen", email: "SARAH@acme.com")]
        )
        let newer = MeetingNote(
            id: "n2",
            title: "Newer",
            date: date(2026, 6, 10),
            participants: [Participant(name: "Sarah C.", email: "sarah@acme.com")]
        )
        let event = UpcomingEvent(
            id: "e1",
            title: "Upcoming",
            start: date(2026, 6, 15),
            participants: [Participant(name: "Sarah Chen", email: "sarah@acme.com")]
        )

        let index = PeopleIndex(notes: [older, newer], events: [event])

        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries[0].participant.email, "SARAH@acme.com")
        XCTAssertEqual(index.entries[0].noteCount, 2)
        XCTAssertEqual(index.entries[0].calendarEventCount, 1)
    }

    func testSuggestionsRankLocalHistoryBeforeCalendarOnlyPeople() {
        let note = MeetingNote(
            id: "n1",
            title: "Past",
            date: date(2026, 6, 1),
            participants: [Participant(name: "Zoe Local")]
        )
        let event = UpcomingEvent(
            id: "e1",
            title: "Calendar",
            start: date(2026, 6, 20),
            participants: [Participant(name: "Amy Calendar")]
        )

        let suggestions = PeopleIndex(notes: [note], events: [event]).suggestions()

        XCTAssertEqual(suggestions.map(\.displayName), ["Zoe Local", "Amy Calendar"])
    }

    func testSuggestionsFilterByNameAndEmailDiacriticInsensitively() {
        let note = MeetingNote(
            id: "n1",
            title: "Past",
            date: date(2026, 6, 1),
            participants: [
                Participant(name: "Anaïs Nin", email: "anais@example.com"),
                Participant(name: "Bob Stone", email: "bob@example.com")
            ]
        )

        let byName = PeopleIndex(notes: [note], events: []).suggestions(matching: "anais")
        let byEmail = PeopleIndex(notes: [note], events: []).suggestions(matching: "bob@")

        XCTAssertEqual(byName.map(\.displayName), ["Anaïs Nin"])
        XCTAssertEqual(byEmail.map(\.displayName), ["Bob Stone"])
    }

    func testSuggestionsExcludeAlreadySelectedParticipant() {
        let note = MeetingNote(
            id: "n1",
            title: "Past",
            date: date(2026, 6, 1),
            participants: [
                Participant(name: "Alice", email: "alice@example.com"),
                Participant(name: "Bob", email: "bob@example.com")
            ]
        )

        let suggestions = PeopleIndex(notes: [note], events: []).suggestions(
            excluding: [Participant(name: "Alice", email: "alice@example.com")]
        )

        XCTAssertEqual(suggestions.map(\.displayName), ["Bob"])
    }

    func testCRMIdentityDeduplicatesPeople() {
        let first = MeetingNote(
            id: "n1",
            title: "Past",
            date: date(2026, 6, 1),
            participants: [Participant(name: "Sarah", crm: "local:person/1")]
        )
        let second = UpcomingEvent(
            id: "e1",
            title: "Upcoming",
            start: date(2026, 6, 20),
            participants: [Participant(name: "Sarah Chen", email: "sarah@example.com", crm: "local:person/1")]
        )

        let index = PeopleIndex(notes: [first], events: [second])

        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries[0].participant.crm, "local:person/1")
        XCTAssertEqual(index.entries[0].participant.email, "sarah@example.com")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
