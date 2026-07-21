import Foundation
import NoteTakrKit

public struct ConvexCachedPerson: Codable, Equatable, Sendable {
    public var remoteId: String
    public var name: String
    public var emails: [String]
    public var company: String?

    public init(
        remoteId: String,
        name: String,
        emails: [String],
        company: String? = nil
    ) {
        self.remoteId = remoteId
        self.name = name
        self.emails = emails
        self.company = company
    }
}

public final class ConvexPeopleCacheSource: PeopleSource, @unchecked Sendable {
    public static let crmProviderId = "crm"

    public var providerId: String { Self.crmProviderId }
    public let snapshotURL: URL

    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    public init(rootURL: URL) {
        self.snapshotURL = rootURL
            .appendingPathComponent("NoteTakr", isDirectory: true)
            .appendingPathComponent("PeopleCache.json")
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public init(snapshotURL: URL) {
        self.snapshotURL = snapshotURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func allPeople() -> [Person] {
        loadSnapshot().map(Self.person(from:))
    }

    public func search(_ query: String) -> [Person] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return allPeople() }

        return allPeople().filter { person in
            person.name.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil ||
                person.emails.contains {
                    $0.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
        }
    }

    public func refresh(people: [ConvexCachedPerson]) throws {
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let normalized = people.map(Self.normalized(_:))
        let data = try encoder.encode(normalized)
        try data.write(to: snapshotURL, options: .atomic)
    }

    private func loadSnapshot() -> [ConvexCachedPerson] {
        guard let data = try? Data(contentsOf: snapshotURL),
              let people = try? decoder.decode([ConvexCachedPerson].self, from: data) else {
            return []
        }
        return people
    }

    private static func person(from cached: ConvexCachedPerson) -> Person {
        Person(
            name: cached.name,
            emails: cached.emails,
            company: cached.company,
            sourceRefs: [SourceRef(provider: crmProviderId, remoteId: cached.remoteId)]
        )
    }

    private static func normalized(_ person: ConvexCachedPerson) -> ConvexCachedPerson {
        ConvexCachedPerson(
            remoteId: person.remoteId.trimmingCharacters(in: .whitespacesAndNewlines),
            name: person.name.trimmingCharacters(in: .whitespacesAndNewlines),
            emails: person.emails.compactMap(Person.normalizedEmail(_:)),
            company: trimmedNonEmpty(person.company)
        )
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
