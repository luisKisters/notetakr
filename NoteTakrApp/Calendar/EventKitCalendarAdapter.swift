#if canImport(EventKit)
import EventKit
import NoteTakrCore

public final class EventKitCalendarAdapter: CalendarAdapter {
    private let store = EKEventStore()

    public init() {}

    public var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    public func requestAccess() async throws {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestFullAccessToEvents()
        } else {
            granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { result, _ in
                    continuation.resume(returning: result)
                }
            }
        }
        guard granted else { throw CalendarError.accessDenied }
    }

    public func fetchUpcomingEvents(from: Date, to: Date) async throws -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).map(CalendarEvent.init(ekEvent:))
    }
}

private extension CalendarEvent {
    init(ekEvent: EKEvent) {
        self.init(
            id: ekEvent.eventIdentifier ?? UUID().uuidString,
            title: ekEvent.title ?? "Untitled",
            startDate: ekEvent.startDate ?? Date(),
            endDate: ekEvent.endDate ?? Date(),
            url: ekEvent.url,
            notes: ekEvent.notes
        )
    }
}
#endif
