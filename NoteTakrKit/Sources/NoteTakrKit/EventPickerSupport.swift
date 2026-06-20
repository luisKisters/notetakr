import Foundation

public struct EventPickerWindow: Equatable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public static func defaultWindow(now: Date, calendar: Calendar = .current) -> EventPickerWindow {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let endBase = calendar.date(byAdding: .day, value: 8, to: today) ?? today
        return EventPickerWindow(start: start, end: endBase)
    }

    public func extendingEarlier(calendar: Calendar = .current) -> EventPickerWindow {
        EventPickerWindow(
            start: calendar.date(byAdding: .day, value: -7, to: start) ?? start,
            end: end
        )
    }

    public func extendingLater(calendar: Calendar = .current) -> EventPickerWindow {
        EventPickerWindow(
            start: start,
            end: calendar.date(byAdding: .day, value: 7, to: end) ?? end
        )
    }
}

public enum EventPickerFiltering {
    public static func events(
        _ events: [UpcomingEvent],
        in window: EventPickerWindow,
        query: String
    ) -> [UpcomingEvent] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return events
            .filter { event in
                event.start >= window.start && event.start < window.end
            }
            .filter { event in
                guard !trimmed.isEmpty else { return true }
                if contains(event.title, trimmed) { return true }
                if let location = event.locationText, contains(location, trimmed) { return true }
                return event.participants.contains { participant in
                    contains(participant.name, trimmed)
                        || participant.email.map { contains($0, trimmed) } == true
                }
            }
            .sorted {
                if $0.start == $1.start { return $0.title < $1.title }
                return $0.start < $1.start
            }
    }

    private static func contains(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
