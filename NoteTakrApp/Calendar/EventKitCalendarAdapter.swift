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
            id: Self.occurrenceID(for: ekEvent),
            title: ekEvent.title ?? "Untitled",
            startDate: ekEvent.startDate ?? Date(),
            endDate: ekEvent.endDate ?? Date(),
            url: ekEvent.url,
            notes: ekEvent.notes,
            attendees: (ekEvent.attendees ?? []).map(Participant.init(ekParticipant:)),
            organizerEmail: ekEvent.organizer.flatMap { Participant.email(from: $0) }
        )
    }

    /// EventKit reuses one `eventIdentifier` across every occurrence of a
    /// recurring event. Append the occurrence start so each occurrence has a
    /// stable, unique id (safe for SwiftUI lists and for linking to a session).
    static func occurrenceID(for ekEvent: EKEvent) -> String {
        let base = ekEvent.eventIdentifier ?? UUID().uuidString
        guard let start = ekEvent.startDate else { return base }
        return "\(base)@\(Int(start.timeIntervalSince1970))"
    }
}

private extension Participant {
    init(ekParticipant: EKParticipant) {
        self.init(
            name: ekParticipant.name ?? Participant.email(from: ekParticipant) ?? "Unknown",
            email: Participant.email(from: ekParticipant)
        )
    }

    /// Attendee emails are best-effort: EventKit exposes them via the participant's
    /// `mailto:` URL, and some accounts expose a name only.
    static func email(from participant: EKParticipant) -> String? {
        let components = URLComponents(url: participant.url, resolvingAgainstBaseURL: false)
        guard components?.scheme?.lowercased() == "mailto" else { return nil }
        let path = components?.path ?? ""
        return path.isEmpty ? nil : path
    }
}
#endif
