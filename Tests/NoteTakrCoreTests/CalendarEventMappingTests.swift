import XCTest
import NoteTakrCore
import NoteTakrKit

final class CalendarEventMappingTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - toUpcomingEvent mapping

    func testBasicFieldsAreMapped() {
        let end = epoch.addingTimeInterval(3_600)
        let event = CalendarEvent(
            id: "ev-1",
            title: "Standup",
            startDate: epoch,
            endDate: end
        )
        let upcoming = event.toUpcomingEvent()

        XCTAssertEqual(upcoming.id, "ev-1")
        XCTAssertEqual(upcoming.title, "Standup")
        XCTAssertEqual(upcoming.start, epoch)
        XCTAssertEqual(upcoming.end, end)
        XCTAssertTrue(upcoming.participants.isEmpty)
        XCTAssertNil(upcoming.locationText)
        XCTAssertNil(upcoming.meetingLink)
    }

    func testOptionalFieldsAreMapped() {
        let event = CalendarEvent(
            id: "ev-2",
            title: "Design Review",
            startDate: epoch,
            endDate: epoch.addingTimeInterval(1_800),
            location: "Zoom Room 4",
            url: URL(string: "https://zoom.us/j/12345"),
            attendees: [
                NoteTakrCore.Participant(name: "Alice", email: "alice@example.com"),
                NoteTakrCore.Participant(name: "Bob")
            ]
        )
        let upcoming = event.toUpcomingEvent()

        XCTAssertEqual(upcoming.locationText, "Zoom Room 4")
        XCTAssertEqual(upcoming.meetingLink, "https://zoom.us/j/12345")
        XCTAssertEqual(upcoming.participants.count, 2)
        XCTAssertEqual(upcoming.participants[0].name, "Alice")
        XCTAssertEqual(upcoming.participants[0].email, "alice@example.com")
        XCTAssertEqual(upcoming.participants[1].name, "Bob")
        XCTAssertNil(upcoming.participants[1].email)
    }

    func testNilUrlProducesNilMeetingLink() {
        let event = CalendarEvent(
            id: "ev-3",
            title: "No link",
            startDate: epoch,
            endDate: epoch.addingTimeInterval(900)
        )
        XCTAssertNil(event.toUpcomingEvent().meetingLink)
    }

    // MARK: - Array mapping

    func testArrayMappingPreservesOrder() {
        let events = (1...3).map { i in
            CalendarEvent(
                id: "ev-\(i)",
                title: "Event \(i)",
                startDate: epoch.addingTimeInterval(Double(i) * 3_600),
                endDate: epoch.addingTimeInterval(Double(i) * 3_600 + 1_800)
            )
        }
        let upcoming = events.toUpcomingEvents()

        XCTAssertEqual(upcoming.count, 3)
        XCTAssertEqual(upcoming.map { $0.id }, ["ev-1", "ev-2", "ev-3"])
        XCTAssertEqual(upcoming.map { $0.title }, ["Event 1", "Event 2", "Event 3"])
    }

    func testEmptyArrayMapsToEmpty() {
        let events: [CalendarEvent] = []
        XCTAssertTrue(events.toUpcomingEvents().isEmpty)
    }

    // MARK: - Mock adapter sync simulation

    func testMockAdapterEventsFilteredByWindow() async throws {
        let now = epoch
        let inWindow = CalendarEvent(
            id: "in",
            title: "In Window",
            startDate: now.addingTimeInterval(3_600),
            endDate: now.addingTimeInterval(7_200)
        )
        let outOfWindow = CalendarEvent(
            id: "out",
            title: "Out of Window",
            startDate: now.addingTimeInterval(8 * 86_400),
            endDate: now.addingTimeInterval(8 * 86_400 + 3_600)
        )
        let adapter = MockCalendarAdapter(events: [inWindow, outOfWindow], accessGranted: true)

        let fetched = try await adapter.fetchUpcomingEvents(
            from: now,
            to: now.addingTimeInterval(7 * 86_400)
        )
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, "in")

        let upcoming = fetched.toUpcomingEvents()
        XCTAssertEqual(upcoming.count, 1)
        XCTAssertEqual(upcoming[0].id, "in")
        XCTAssertEqual(upcoming[0].title, "In Window")
    }

    func testMockAdapterDeniedReturnsNoAccess() {
        let adapter = MockCalendarAdapter(accessGranted: false)
        XCTAssertFalse(adapter.hasAccess)
    }

    func testMockAdapterGrantedReturnsAccess() {
        let adapter = MockCalendarAdapter(accessGranted: true)
        XCTAssertTrue(adapter.hasAccess)
    }
}
