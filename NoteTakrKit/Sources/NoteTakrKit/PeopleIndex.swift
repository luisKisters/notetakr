import Foundation

public enum ParticipantIdentity {
    public static func key(for participant: Participant) -> String {
        if let crm = normalizedCRM(participant.crm) {
            return "crm:\(crm)"
        }
        if let email = normalizedEmail(participant.email) {
            return "email:\(email)"
        }
        return "name:\(normalizedName(participant.displayName))"
    }

    public static func matches(_ lhs: Participant, _ rhs: Participant) -> Bool {
        if let lhsCRM = normalizedCRM(lhs.crm),
           let rhsCRM = normalizedCRM(rhs.crm) {
            return lhsCRM == rhsCRM
        }
        if let lhsEmail = normalizedEmail(lhs.email),
           let rhsEmail = normalizedEmail(rhs.email) {
            return lhsEmail == rhsEmail
        }
        return normalizedName(lhs.displayName) == normalizedName(rhs.displayName)
    }

    static func normalizedEmail(_ email: String?) -> String? {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func normalizedCRM(_ crm: String?) -> String? {
        let trimmed = crm?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

public struct PersonIndexEntry: Identifiable, Equatable {
    public var participant: Participant
    public var noteCount: Int
    public var calendarEventCount: Int
    public var latestMeetingDate: Date?

    public init(
        participant: Participant,
        noteCount: Int = 0,
        calendarEventCount: Int = 0,
        latestMeetingDate: Date? = nil
    ) {
        self.participant = participant
        self.noteCount = noteCount
        self.calendarEventCount = calendarEventCount
        self.latestMeetingDate = latestMeetingDate
    }

    public var id: String {
        ParticipantIdentity.key(for: participant)
    }

    public var displayName: String {
        participant.displayName
    }

    public var hasLocalHistory: Bool {
        noteCount > 0
    }
}

public struct PeopleIndex: Equatable {
    public var entries: [PersonIndexEntry]

    public init(notes: [MeetingNote], events: [UpcomingEvent]) {
        var builders: [PersonBuilder] = []

        for note in notes {
            let uniqueParticipants = Self.unique(note.participants)
            for participant in uniqueParticipants {
                Self.merge(
                    participant,
                    into: &builders,
                    noteDate: note.date,
                    isCalendarAttendee: false
                )
            }
        }

        for event in events {
            let uniqueParticipants = Self.unique(event.participants)
            for participant in uniqueParticipants {
                Self.merge(
                    participant,
                    into: &builders,
                    noteDate: event.start,
                    isCalendarAttendee: true
                )
            }
        }

        entries = builders
            .map(\.entry)
            .sorted(by: Self.defaultSort)
    }

    public init(entries: [PersonIndexEntry]) {
        self.entries = entries.sorted(by: Self.defaultSort)
    }

    public func suggestions(
        matching query: String = "",
        excluding selectedParticipants: [Participant] = [],
        limit: Int = 6
    ) -> [PersonIndexEntry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedKeys = Set(selectedParticipants.map(ParticipantIdentity.key(for:)))

        let filtered = entries.filter { entry in
            guard !selectedKeys.contains(entry.id) else { return false }
            guard !selectedParticipants.contains(where: { ParticipantIdentity.matches($0, entry.participant) }) else {
                return false
            }
            guard !trimmedQuery.isEmpty else { return true }
            if Self.contains(entry.displayName, trimmedQuery) { return true }
            if let email = entry.participant.email, Self.contains(email, trimmedQuery) { return true }
            return false
        }

        return Array(filtered.sorted { lhs, rhs in
            let lhsRank = Self.queryRank(lhs, query: trimmedQuery)
            let rhsRank = Self.queryRank(rhs, query: trimmedQuery)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return Self.defaultSort(lhs, rhs)
        }.prefix(limit))
    }

    public func entry(for participant: Participant) -> PersonIndexEntry? {
        entries.first { ParticipantIdentity.matches($0.participant, participant) }
    }

    private static func unique(_ participants: [Participant]) -> [Participant] {
        var result: [Participant] = []
        for participant in participants {
            guard !participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard !result.contains(where: { ParticipantIdentity.matches($0, participant) }) else { continue }
            result.append(participant)
        }
        return result
    }

    private static func merge(
        _ participant: Participant,
        into builders: inout [PersonBuilder],
        noteDate: Date,
        isCalendarAttendee: Bool
    ) {
        if let index = builders.firstIndex(where: { $0.matches(participant) }) {
            builders[index].merge(participant, date: noteDate, isCalendarAttendee: isCalendarAttendee)
        } else {
            builders.append(PersonBuilder(participant: participant, date: noteDate, isCalendarAttendee: isCalendarAttendee))
        }
    }

    private static func contains(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func queryRank(_ entry: PersonIndexEntry, query: String) -> Int {
        guard !query.isEmpty else { return 0 }
        let name = entry.displayName
        if name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
            return 0
        }
        if let email = entry.participant.email,
           email.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
            return 1
        }
        return 2
    }

    private static func defaultSort(_ lhs: PersonIndexEntry, _ rhs: PersonIndexEntry) -> Bool {
        if lhs.noteCount != rhs.noteCount { return lhs.noteCount > rhs.noteCount }
        switch (lhs.latestMeetingDate, rhs.latestMeetingDate) {
        case (.some(let lhsDate), .some(let rhsDate)) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }
        if lhs.calendarEventCount != rhs.calendarEventCount {
            return lhs.calendarEventCount > rhs.calendarEventCount
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}

private struct PersonBuilder {
    var participant: Participant
    var noteCount: Int
    var calendarEventCount: Int
    var latestMeetingDate: Date?

    init(participant: Participant, date: Date, isCalendarAttendee: Bool) {
        self.participant = Self.normalized(participant)
        noteCount = isCalendarAttendee ? 0 : 1
        calendarEventCount = isCalendarAttendee ? 1 : 0
        latestMeetingDate = date
    }

    var entry: PersonIndexEntry {
        PersonIndexEntry(
            participant: participant,
            noteCount: noteCount,
            calendarEventCount: calendarEventCount,
            latestMeetingDate: latestMeetingDate
        )
    }

    func matches(_ other: Participant) -> Bool {
        ParticipantIdentity.matches(participant, other)
    }

    mutating func merge(_ other: Participant, date: Date, isCalendarAttendee: Bool) {
        let normalizedOther = Self.normalized(other)
        participant = Self.preferredParticipant(existing: participant, incoming: normalizedOther)
        if isCalendarAttendee {
            calendarEventCount += 1
        } else {
            noteCount += 1
        }
        if latestMeetingDate.map({ date > $0 }) ?? true {
            latestMeetingDate = date
        }
    }

    private static func normalized(_ participant: Participant) -> Participant {
        let email = trimmedNonEmpty(participant.email)
        let crm = trimmedNonEmpty(participant.crm)
        let name = Participant.displayName(name: trimmedNonEmpty(participant.name), email: email)
        return Participant(name: name, email: email, crm: crm)
    }

    private static func preferredParticipant(existing: Participant, incoming: Participant) -> Participant {
        let email = trimmedNonEmpty(existing.email) ?? trimmedNonEmpty(incoming.email)
        let crm = trimmedNonEmpty(existing.crm) ?? trimmedNonEmpty(incoming.crm)

        let existingName = existing.displayName
        let incomingName = incoming.displayName
        let name: String
        if looksLikeEmail(existingName), !looksLikeEmail(incomingName) {
            name = incomingName
        } else {
            name = existingName
        }

        return Participant(name: name, email: email, crm: crm)
    }

    private static func looksLikeEmail(_ value: String) -> Bool {
        value.contains("@")
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
