import XCTest
@testable import NoteTakrKit

/// Tests the calendar event bridge: UpcomingEvent fields and UpcomingEventsProviding sync.
/// Runs on Linux (no AppKit / CalendarEvent dependency).
final class CalendarBridgeTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - UpcomingEvent structure

    func testUpcomingEventFieldsRoundTrip() {
        let start = epoch
        let end = epoch.addingTimeInterval(3_600)
        let event = UpcomingEvent(
            id: "cal-1",
            title: "Design Review",
            start: start,
            end: end,
            participants: [Participant(name: "Alice", email: "alice@example.com")],
            locationText: "Room 4",
            meetingLink: "https://meet.example.com/room4"
        )

        XCTAssertEqual(event.id, "cal-1")
        XCTAssertEqual(event.title, "Design Review")
        XCTAssertEqual(event.start, start)
        XCTAssertEqual(event.end, end)
        XCTAssertEqual(event.participants.count, 1)
        XCTAssertEqual(event.participants[0].name, "Alice")
        XCTAssertEqual(event.participants[0].email, "alice@example.com")
        XCTAssertEqual(event.locationText, "Room 4")
        XCTAssertEqual(event.meetingLink, "https://meet.example.com/room4")
    }

    func testUpcomingEventOptionalFieldsDefault() {
        let event = UpcomingEvent(id: "cal-2", title: "Standup", start: epoch)
        XCTAssertNil(event.end)
        XCTAssertTrue(event.participants.isEmpty)
        XCTAssertNil(event.locationText)
        XCTAssertNil(event.meetingLink)
    }

    func testUpcomingEventEquality() {
        let a = UpcomingEvent(id: "x", title: "T", start: epoch, end: nil)
        let b = UpcomingEvent(id: "x", title: "T", start: epoch, end: nil)
        let c = UpcomingEvent(id: "y", title: "T", start: epoch, end: nil)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - UpcomingEventsProviding bridge

    func testEventsProviderDeliversToSwitcher() {
        let events = [
            UpcomingEvent(id: "e1", title: "Standup", start: epoch.addingTimeInterval(1_800)),
            UpcomingEvent(id: "e2", title: "Retrospective", start: epoch.addingTimeInterval(7_200)),
        ]
        let provider = StubEventsProvider(events: events)
        XCTAssertEqual(provider.listEvents().count, 2)
        XCTAssertEqual(provider.listEvents()[0].id, "e1")
        XCTAssertEqual(provider.listEvents()[1].id, "e2")
    }

    func testEmptyEventsProviderReturnsEmptyList() {
        let provider = StubEventsProvider(events: [])
        XCTAssertTrue(provider.listEvents().isEmpty)
    }

    // MARK: - Sync simulation: events update propagate to provider

    func testProviderEventsUpdateAfterSync() {
        let provider = MutableEventsProvider()
        XCTAssertTrue(provider.listEvents().isEmpty)

        let batch: [UpcomingEvent] = [
            UpcomingEvent(id: "sync-1", title: "All Hands", start: epoch),
        ]
        provider.events = batch
        XCTAssertEqual(provider.listEvents().count, 1)
        XCTAssertEqual(provider.listEvents()[0].title, "All Hands")

        provider.events = []
        XCTAssertTrue(provider.listEvents().isEmpty)
    }

    func testMultipleParticipantsAreMappedCorrectly() {
        let participants = [
            Participant(name: "Alice", email: "alice@acme.com"),
            Participant(name: "Bob"),
            Participant(name: "Carol", email: "carol@acme.com"),
        ]
        let event = UpcomingEvent(
            id: "e-multi",
            title: "Team Meeting",
            start: epoch,
            participants: participants
        )
        XCTAssertEqual(event.participants[0].name, "Alice")
        XCTAssertEqual(event.participants[0].email, "alice@acme.com")
        XCTAssertEqual(event.participants[1].name, "Bob")
        XCTAssertNil(event.participants[1].email)
        XCTAssertEqual(event.participants[2].name, "Carol")
    }
}

// MARK: - Test doubles

private struct StubEventsProvider: UpcomingEventsProviding {
    let events: [UpcomingEvent]
    func listEvents() -> [UpcomingEvent] { events }
}

private final class MutableEventsProvider: UpcomingEventsProviding {
    var events: [UpcomingEvent] = []
    func listEvents() -> [UpcomingEvent] { events }
}
