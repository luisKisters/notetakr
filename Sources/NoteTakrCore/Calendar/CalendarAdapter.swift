import Foundation

public enum CalendarError: Error, Equatable {
    case accessDenied
    case unavailable
}

public protocol CalendarAdapter {
    func requestAccess() async throws
    func fetchUpcomingEvents(from: Date, to: Date) async throws -> [CalendarEvent]
}
