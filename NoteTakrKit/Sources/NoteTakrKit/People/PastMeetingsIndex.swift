import Foundation

public struct PastMeetingsIndexEntry: Equatable, Sendable {
    public var person: Person
    public var coMeetingCount: Int
    public var lastMeetingDate: Date
    public var score: Double

    public init(person: Person, coMeetingCount: Int, lastMeetingDate: Date, score: Double) {
        self.person = person
        self.coMeetingCount = coMeetingCount
        self.lastMeetingDate = lastMeetingDate
        self.score = score
    }
}

public struct PastMeetingsIndex: Equatable, Sendable {
    public static let providerId = "pastMeetings"

    public var entries: [PastMeetingsIndexEntry]

    public init(notes: [MeetingNote], now: Date = Date()) {
        var builders: [String: PastMeetingPersonBuilder] = [:]

        for note in notes {
            var seenEmailsInNote = Set<String>()

            for participant in note.participants {
                guard let email = Person.normalizedEmail(participant.email),
                      !seenEmailsInNote.contains(email) else {
                    continue
                }

                seenEmailsInNote.insert(email)
                if builders[email] == nil {
                    builders[email] = PastMeetingPersonBuilder(email: email)
                }
                builders[email]?.merge(participant: participant, date: note.date)
            }
        }

        entries = builders.values
            .map { $0.entry(now: now) }
            .sorted(by: Self.defaultSort)
    }

    public init(entries: [PastMeetingsIndexEntry]) {
        self.entries = entries.sorted(by: Self.defaultSort)
    }

    public func allPeople() -> [Person] {
        entries.map(\.person)
    }

    public func search(_ query: String) -> [Person] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return allPeople() }

        return entries
            .filter { entry in
                if Person.matches(entry.person.name, query: trimmedQuery) { return true }
                return entry.person.emails.contains { Person.matches($0, query: trimmedQuery) }
            }
            .sorted(by: Self.defaultSort)
            .map(\.person)
    }

    public func entry(forEmail email: String) -> PastMeetingsIndexEntry? {
        guard let normalized = Person.normalizedEmail(email) else { return nil }
        return entries.first { $0.person.emails.contains(normalized) }
    }

    private static func defaultSort(_ lhs: PastMeetingsIndexEntry, _ rhs: PastMeetingsIndexEntry) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.coMeetingCount != rhs.coMeetingCount { return lhs.coMeetingCount > rhs.coMeetingCount }
        if lhs.lastMeetingDate != rhs.lastMeetingDate { return lhs.lastMeetingDate > rhs.lastMeetingDate }
        return lhs.person.name.localizedCaseInsensitiveCompare(rhs.person.name) == .orderedAscending
    }
}

private struct PastMeetingPersonBuilder {
    var email: String
    var name: String?
    var nameDate: Date?
    var coMeetingCount = 0
    var lastMeetingDate: Date?

    mutating func merge(participant: Participant, date: Date) {
        coMeetingCount += 1

        if lastMeetingDate.map({ date > $0 }) ?? true {
            lastMeetingDate = date
        }

        let displayName = participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if shouldUseName(displayName, date: date) {
            name = displayName
            nameDate = date
        }
    }

    func entry(now: Date) -> PastMeetingsIndexEntry {
        let lastMeetingDate = lastMeetingDate ?? now
        let daysSinceLastMeeting = max(0, now.timeIntervalSince(lastMeetingDate) / (24 * 60 * 60))
        let score = Double(coMeetingCount) * exp(-daysSinceLastMeeting / 90)
        let person = Person(
            name: name ?? Participant.displayName(name: nil, email: email),
            emails: [email],
            sourceRefs: [SourceRef(provider: PastMeetingsIndex.providerId, remoteId: email)]
        )

        return PastMeetingsIndexEntry(
            person: person,
            coMeetingCount: coMeetingCount,
            lastMeetingDate: lastMeetingDate,
            score: score
        )
    }

    private mutating func shouldUseName(_ candidate: String, date: Date) -> Bool {
        guard !candidate.isEmpty else { return false }
        guard !looksLikeEmail(candidate) else { return name.map(looksLikeEmail) ?? true }
        guard let currentName = name else { return true }
        if looksLikeEmail(currentName) { return true }
        return nameDate.map { date > $0 } ?? true
    }

    private func looksLikeEmail(_ value: String) -> Bool {
        value.contains("@")
    }
}
