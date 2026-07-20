import Foundation

public struct PeoplePickerPresenter {
    public struct Section: Equatable {
        public var id: SectionID
        public var rows: [Row]

        public init(id: SectionID, rows: [Row]) {
            self.id = id
            self.rows = rows
        }
    }

    public enum SectionID: Equatable, Hashable {
        case inThisEvent
        case recent
        case source(String)
        case freeText
    }

    public enum Row: Equatable {
        case person(Person)
        case freeText(String)
    }

    private let directory: PeopleDirectory
    private let eventAttendees: [Participant]
    private let alreadyAdded: [Participant]

    public init(
        directory: PeopleDirectory,
        eventAttendees: [Participant] = [],
        alreadyAdded: [Participant] = []
    ) {
        self.directory = directory
        self.eventAttendees = eventAttendees
        self.alreadyAdded = alreadyAdded
    }

    public func sections(for query: String) -> [Section] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var builder = SectionBuilder(alreadyAdded: alreadyAdded, query: trimmedQuery)
        var sections: [Section] = []

        let eventRows = builder.rows(from: eventPeople(), excludingSeen: true)
        if !eventRows.isEmpty {
            sections.append(Section(id: .inThisEvent, rows: eventRows))
        }

        let recentRows = builder.rows(
            from: directory.people(fromProvider: PastMeetingsIndex.providerId),
            excludingSeen: true
        )
        if !recentRows.isEmpty {
            sections.append(Section(id: .recent, rows: recentRows))
        }

        for providerId in directory.sourceProviderIds where providerId != PastMeetingsIndex.providerId {
            let rows = builder.rows(from: directory.people(fromProvider: providerId), excludingSeen: true)
            if !rows.isEmpty {
                sections.append(Section(id: .source(providerId), rows: rows))
            }
        }

        if shouldShowFreeTextRow(for: trimmedQuery) {
            let row = Row.freeText(trimmedQuery)
            if sections.isEmpty {
                sections.append(Section(id: .freeText, rows: [row]))
            } else {
                sections[sections.count - 1].rows.append(row)
            }
        }

        return sections
    }

    public func participant(from row: Row) -> Participant {
        switch row {
        case .person(let person):
            return Participant(name: person.name, email: person.emails.first)
        case .freeText(let value):
            return Participant(name: value, email: nil)
        }
    }

    private func eventPeople() -> [Person] {
        var people: [Person] = []
        var seenEmails = Set<String>()

        for attendee in eventAttendees {
            guard let email = Person.normalizedEmail(attendee.email),
                  seenEmails.insert(email).inserted else {
                continue
            }

            if let person = directory.person(forEmail: email) {
                people.append(person)
            } else {
                people.append(
                    Person(
                        name: attendee.displayName,
                        emails: [email],
                        sourceRefs: [SourceRef(provider: "event", remoteId: email)]
                    )
                )
            }
        }

        return people
    }

    private func shouldShowFreeTextRow(for query: String) -> Bool {
        guard !query.isEmpty else { return false }

        let allPeople = eventPeople() + directory.allPeople()
        return !allPeople.contains { PeopleSearch.person($0, exactlyMatches: query) }
    }
}

private struct SectionBuilder {
    private let query: String
    private let alreadyAddedEmails: Set<String>
    private let alreadyAddedNames: Set<String>
    private var seenEmails = Set<String>()
    private var seenNames = Set<String>()

    init(alreadyAdded: [Participant], query: String) {
        self.query = query
        self.alreadyAddedEmails = Set(alreadyAdded.compactMap { Person.normalizedEmail($0.email) })
        self.alreadyAddedNames = Set(
            alreadyAdded
                .filter { Person.normalizedEmail($0.email) == nil }
                .map { PeopleSearch.fold($0.displayName) }
        )
    }

    mutating func rows(from people: [Person], excludingSeen: Bool) -> [PeoplePickerPresenter.Row] {
        var rows: [PeoplePickerPresenter.Row] = []

        for person in people {
            guard matchesQuery(person),
                  !isAlreadyAdded(person),
                  !shouldSkipAsSeen(person, excludingSeen: excludingSeen) else {
                continue
            }

            rows.append(.person(person))
            recordSeen(person)
        }

        return rows
    }

    private func matchesQuery(_ person: Person) -> Bool {
        query.isEmpty || PeopleSearch.person(person, matchesPrefix: query)
    }

    private func isAlreadyAdded(_ person: Person) -> Bool {
        if !alreadyAddedEmails.isDisjoint(with: person.emails) {
            return true
        }

        guard person.emails.isEmpty else { return false }
        return alreadyAddedNames.contains(PeopleSearch.fold(person.name))
    }

    private func shouldSkipAsSeen(_ person: Person, excludingSeen: Bool) -> Bool {
        guard excludingSeen else { return false }

        if !person.emails.isEmpty {
            return !seenEmails.isDisjoint(with: person.emails)
        }

        return seenNames.contains(PeopleSearch.fold(person.name))
    }

    private mutating func recordSeen(_ person: Person) {
        for email in person.emails {
            seenEmails.insert(email)
        }
        if person.emails.isEmpty {
            seenNames.insert(PeopleSearch.fold(person.name))
        }
    }
}

enum PeopleSearch {
    static func person(_ person: Person, matchesPrefix query: String) -> Bool {
        let foldedQuery = fold(query)
        guard !foldedQuery.isEmpty else { return true }

        if fold(person.name).hasPrefix(foldedQuery) {
            return true
        }

        return person.emails.contains { fold($0).hasPrefix(foldedQuery) }
    }

    static func person(_ person: Person, exactlyMatches query: String) -> Bool {
        let foldedQuery = fold(query)
        guard !foldedQuery.isEmpty else { return false }

        if fold(person.name) == foldedQuery {
            return true
        }

        return person.emails.contains { fold($0) == foldedQuery }
    }

    static func fold(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
