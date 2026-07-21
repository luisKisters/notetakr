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

public enum EventPickerSelection {
    /// The event a calendar picker should focus when it opens: an event in
    /// progress, otherwise the next event, otherwise the most recent one.
    public static func focusedIndex(in events: [UpcomingEvent], now: Date) -> Int? {
        guard !events.isEmpty else { return nil }

        let current = events.indices
            .filter { index in
                let event = events[index]
                return event.start <= now && (event.end ?? event.start) > now
            }
            .max { events[$0].start < events[$1].start }
        if let current {
            return current
        }
        if let next = events.firstIndex(where: { $0.start >= now }) {
            return next
        }
        return events.indices.last
    }

    public static func dotState(for event: UpcomingEvent, now: Date) -> DotState {
        if event.start <= now && (event.end ?? event.start) > now {
            return .current
        }
        return event.start > now ? .upcoming : .past
    }
}

public struct ResolvedDateTimeSelection: Equatable {
    public let start: Date
    public let end: Date?

    public init(start: Date, end: Date?) {
        self.start = start
        self.end = end
    }
}

/// Resolves the editable date/time fields as one atomic value. The UI keeps the
/// date picker and the HH:mm fields separate, so validation must include text
/// that has not yet produced a TextField submit event.
public enum DateTimeEditing {
    public static func resolve(
        startDate: Date,
        startTimeText: String,
        endDate: Date,
        endTimeText: String,
        hasEnd: Bool,
        calendar: Calendar = .current
    ) -> ResolvedDateTimeSelection? {
        guard let start = applying(timeText: startTimeText, to: startDate, calendar: calendar) else {
            return nil
        }
        guard hasEnd else {
            return ResolvedDateTimeSelection(start: start, end: nil)
        }
        guard let end = applying(timeText: endTimeText, to: endDate, calendar: calendar),
              end >= start else {
            return nil
        }
        return ResolvedDateTimeSelection(start: start, end: end)
    }

    public static func applying(
        timeText: String,
        to date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let trimmed = timeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              let hour = Int(pieces[0]),
              let minute = Int(pieces[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }
}
