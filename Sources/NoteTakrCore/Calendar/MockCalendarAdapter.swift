import Foundation

public final class MockCalendarAdapter: CalendarAdapter {
    public var events: [CalendarEvent]
    public var accessGranted: Bool

    public init(events: [CalendarEvent] = [], accessGranted: Bool = true) {
        self.events = events
        self.accessGranted = accessGranted
    }

    public func requestAccess() async throws {
        guard accessGranted else { throw CalendarError.accessDenied }
    }

    public func fetchUpcomingEvents(from: Date, to: Date) async throws -> [CalendarEvent] {
        events.filter { $0.startDate >= from && $0.startDate <= to }
    }
}
