import NoteTakrKit

/// Pure mapping from Core CalendarEvent to Kit UpcomingEvent.
/// Extracted here so it is testable on Linux without AppKit or EventKit.
public extension CalendarEvent {
    func toUpcomingEvent() -> UpcomingEvent {
        UpcomingEvent(
            id: id,
            title: title,
            start: startDate,
            end: endDate,
            participants: attendees.map { NoteTakrKit.Participant(name: $0.name, email: $0.email, crm: $0.crm) },
            locationText: location,
            meetingLink: url?.absoluteString
        )
    }
}

public extension Array where Element == CalendarEvent {
    func toUpcomingEvents() -> [UpcomingEvent] { map { $0.toUpcomingEvent() } }
}
