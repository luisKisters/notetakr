import Foundation

/// Resolves the title shown for a meeting note from the strongest signal
/// available, in priority order:
///
/// 1. An explicit meeting name the user typed.
/// 2. The title of the linked calendar event.
/// 3. The fallback `"Unnamed Meeting"`.
///
/// This is the single source of truth for the floating note header so the UI,
/// the persisted session, and the rendered note never disagree.
public enum MeetingTitleResolver {
    public static let fallback = "Unnamed Meeting"

    /// Resolves a display title from an optional user-supplied name and an
    /// optional calendar-event title. Whitespace-only inputs are treated as empty.
    public static func resolve(
        meetingName: String?,
        calendarEventTitle: String?
    ) -> String {
        if let name = meetingName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if let event = calendarEventTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !event.isEmpty {
            return event
        }
        return fallback
    }

    /// Convenience overload that pulls the calendar title from an event.
    public static func resolve(
        meetingName: String?,
        event: CalendarEvent?
    ) -> String {
        resolve(meetingName: meetingName, calendarEventTitle: event?.title)
    }
}
