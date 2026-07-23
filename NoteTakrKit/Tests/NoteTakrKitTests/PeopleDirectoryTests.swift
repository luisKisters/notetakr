import XCTest
@testable import NoteTakrKit

final class PeopleDirectoryTests: XCTestCase {
    func testMergesPeopleSharingAnyEmailAcrossSources() {
        let contacts = StaticPeopleSource(
            providerId: "contacts",
            people: [
                Person(
                    name: "Ada",
                    emails: ["a@x.com"],
                    sourceRefs: [SourceRef(provider: "contacts", remoteId: "contact-1")]
                )
            ]
        )
        let pastMeetings = StaticPeopleSource(
            providerId: "pastMeetings",
            people: [
                Person(
                    name: "Ada L.",
                    emails: ["a@x.com", "ada@y.com"],
                    sourceRefs: [SourceRef(provider: "pastMeetings", remoteId: "a@x.com")]
                )
            ]
        )

        let people = PeopleDirectory(sources: [contacts, pastMeetings]).allPeople()

        XCTAssertEqual(people.count, 1)
        XCTAssertEqual(people[0].emails, ["a@x.com", "ada@y.com"])
        XCTAssertEqual(
            Set(people[0].sourceRefs),
            [
                SourceRef(provider: "contacts", remoteId: "contact-1"),
                SourceRef(provider: "pastMeetings", remoteId: "a@x.com"),
            ]
        )
    }

    func testNamePrecedenceFollowsSourcePriorityOrder() {
        let contacts = StaticPeopleSource(
            providerId: "contacts",
            people: [Person(name: "Ada Lovelace", emails: ["a@x.com"])]
        )
        let pastMeetings = StaticPeopleSource(
            providerId: "pastMeetings",
            people: [Person(name: "a@x.com", emails: ["a@x.com"])]
        )

        let people = PeopleDirectory(sources: [contacts, pastMeetings]).allPeople()

        XCTAssertEqual(people.map(\.name), ["Ada Lovelace"])
    }

    func testPeopleFromSingleSourcesPassThroughUnchanged() {
        let ada = Person(
            name: "Ada",
            emails: ["ada@x.com"],
            sourceRefs: [SourceRef(provider: "contacts", remoteId: "contact-1")]
        )
        let grace = Person(
            name: "Grace",
            emails: ["grace@navy.mil"],
            sourceRefs: [SourceRef(provider: "pastMeetings", remoteId: "grace@navy.mil")]
        )

        let people = PeopleDirectory(
            sources: [
                StaticPeopleSource(providerId: "contacts", people: [ada]),
                StaticPeopleSource(providerId: "pastMeetings", people: [grace]),
            ]
        ).allPeople()

        XCTAssertEqual(people, [ada, grace])
    }
}

private struct StaticPeopleSource: PeopleSource {
    var providerId: String
    var people: [Person]

    func allPeople() -> [Person] {
        people
    }

    func search(_ query: String) -> [Person] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return people }

        return people.filter { person in
            person.name.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil ||
            person.emails.contains { $0.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
