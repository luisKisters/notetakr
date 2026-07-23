import Foundation

public struct PeopleDirectory: PeopleSource {
    public let providerId = "directory"
    public let sourceProviderIds: [String]

    private let records: [DirectoryRecord]

    public init(sources: [any PeopleSource]) {
        var providerIds: [String] = []
        var seenProviderIds = Set<String>()
        var builders: [DirectoryRecordBuilder] = []

        for (sourceIndex, source) in sources.enumerated() {
            if seenProviderIds.insert(source.providerId).inserted {
                providerIds.append(source.providerId)
            }

            for (personIndex, person) in source.allPeople().enumerated() {
                let incoming = DirectoryRecordBuilder(
                    person: person,
                    providerId: source.providerId,
                    sourceIndex: sourceIndex,
                    personIndex: personIndex
                )
                let matchingIndexes = builders.indices.filter { index in
                    incoming.hasSharedEmail(with: builders[index])
                }

                guard let firstMatch = matchingIndexes.first else {
                    builders.append(incoming)
                    continue
                }

                var merged = builders[firstMatch]
                for index in matchingIndexes.dropFirst().reversed() {
                    merged.merge(builders[index])
                    builders.remove(at: index)
                }
                merged.merge(incoming)
                builders[firstMatch] = merged
            }
        }

        self.sourceProviderIds = providerIds
        self.records = builders
            .sorted { $0.sortKey < $1.sortKey }
            .map { $0.record() }
    }

    public func allPeople() -> [Person] {
        records.map(\.person)
    }

    public func search(_ query: String) -> [Person] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return allPeople() }

        return records
            .map(\.person)
            .filter { PeopleSearch.person($0, matchesPrefix: trimmedQuery) }
    }

    public func person(forEmail email: String) -> Person? {
        guard let normalizedEmail = Person.normalizedEmail(email) else { return nil }
        return records.first { $0.person.emails.contains(normalizedEmail) }?.person
    }

    public func people(fromProvider providerId: String) -> [Person] {
        records
            .filter { $0.providerIds.contains(providerId) }
            .map(\.person)
    }

    public func providerIds(for person: Person) -> [String] {
        guard let record = records.first(where: { $0.matches(person) }) else { return [] }
        return record.providerIds
    }
}

private struct DirectoryRecord: Equatable {
    var person: Person
    var providerIds: [String]

    func matches(_ other: Person) -> Bool {
        let sharedEmails = !person.emails.isEmpty && !Set(person.emails).isDisjoint(with: other.emails)
        return sharedEmails || person == other
    }
}

private struct DirectoryRecordBuilder {
    private(set) var emails: [String] = []
    private var emailSet = Set<String>()
    private(set) var sourceRefs: [SourceRef] = []
    private var sourceRefSet = Set<SourceRef>()
    private(set) var providerIds: [String] = []
    private var providerIdSet = Set<String>()
    private(set) var nameCandidates: [PrioritizedValue<String>] = []
    private(set) var companyCandidates: [PrioritizedValue<String>] = []
    private(set) var sortKey: SortKey

    init(person: Person, providerId: String, sourceIndex: Int, personIndex: Int) {
        self.sortKey = SortKey(sourceIndex: sourceIndex, personIndex: personIndex)
        merge(person: person, providerId: providerId, sourceIndex: sourceIndex, personIndex: personIndex)
    }

    mutating func merge(_ other: DirectoryRecordBuilder) {
        for email in other.emails {
            appendEmail(email)
        }
        for sourceRef in other.sourceRefs {
            appendSourceRef(sourceRef)
        }
        for providerId in other.providerIds {
            appendProviderId(providerId)
        }
        nameCandidates.append(contentsOf: other.nameCandidates)
        companyCandidates.append(contentsOf: other.companyCandidates)
        sortKey = min(sortKey, other.sortKey)
    }

    mutating func merge(person: Person, providerId: String, sourceIndex: Int, personIndex: Int) {
        for email in person.emails {
            appendEmail(email)
        }
        for sourceRef in person.sourceRefs {
            appendSourceRef(sourceRef)
        }
        appendProviderId(providerId)

        let key = SortKey(sourceIndex: sourceIndex, personIndex: personIndex)
        if let name = trimmedNonEmpty(person.name) {
            nameCandidates.append(PrioritizedValue(value: name, sortKey: key))
        }
        if let company = trimmedNonEmpty(person.company) {
            companyCandidates.append(PrioritizedValue(value: company, sortKey: key))
        }

        sortKey = min(sortKey, key)
    }

    func hasSharedEmail(with other: DirectoryRecordBuilder) -> Bool {
        !emailSet.isEmpty && !emailSet.isDisjoint(with: other.emailSet)
    }

    func record() -> DirectoryRecord {
        let name = nameCandidates.sorted().first?.value ??
            Participant.displayName(name: nil, email: emails.first)
        let company = companyCandidates.sorted().first?.value

        return DirectoryRecord(
            person: Person(
                name: name,
                emails: emails,
                company: company,
                sourceRefs: sourceRefs
            ),
            providerIds: providerIds
        )
    }

    private mutating func appendEmail(_ email: String) {
        guard let normalizedEmail = Person.normalizedEmail(email),
              emailSet.insert(normalizedEmail).inserted else {
            return
        }

        emails.append(normalizedEmail)
    }

    private mutating func appendSourceRef(_ sourceRef: SourceRef) {
        guard sourceRefSet.insert(sourceRef).inserted else { return }
        sourceRefs.append(sourceRef)
    }

    private mutating func appendProviderId(_ providerId: String) {
        guard providerIdSet.insert(providerId).inserted else { return }
        providerIds.append(providerId)
    }
}

private struct PrioritizedValue<Value>: Comparable {
    var value: Value
    var sortKey: SortKey

    static func == (lhs: PrioritizedValue<Value>, rhs: PrioritizedValue<Value>) -> Bool {
        lhs.sortKey == rhs.sortKey
    }

    static func < (lhs: PrioritizedValue<Value>, rhs: PrioritizedValue<Value>) -> Bool {
        lhs.sortKey < rhs.sortKey
    }
}

private struct SortKey: Comparable {
    var sourceIndex: Int
    var personIndex: Int

    static func < (lhs: SortKey, rhs: SortKey) -> Bool {
        if lhs.sourceIndex != rhs.sourceIndex { return lhs.sourceIndex < rhs.sourceIndex }
        return lhs.personIndex < rhs.personIndex
    }
}

private func trimmedNonEmpty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == false ? trimmed : nil
}
