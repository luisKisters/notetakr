import XCTest
@testable import NoteTakrKit

final class PeoplePickerPresenterTests: XCTestCase {
    func testEventAttendeesArePinnedInFirstSection() {
        let directory = PeopleDirectory(
            sources: [
                StaticPeopleSource(providerId: "pastMeetings", people: [
                    Person(name: "Grace Hopper", emails: ["grace@navy.mil"]),
                    Person(name: "Ada Lovelace", emails: ["ada@x.com"]),
                ])
            ]
        )
        let presenter = PeoplePickerPresenter(
            directory: directory,
            eventAttendees: [Participant(name: "Ada L.", email: "ada@x.com")]
        )

        let sections = presenter.sections(for: "")

        XCTAssertEqual(sections.first?.id, .inThisEvent)
        XCTAssertEqual(sections.first?.rows, [.person(Person(name: "Ada Lovelace", emails: ["ada@x.com"]))])
    }

    func testAlreadyAddedParticipantsAreExcluded() {
        let directory = PeopleDirectory(
            sources: [
                StaticPeopleSource(providerId: "pastMeetings", people: [
                    Person(name: "Ada Lovelace", emails: ["ada@x.com"]),
                    Person(name: "Grace Hopper", emails: ["grace@navy.mil"]),
                ])
            ]
        )
        let presenter = PeoplePickerPresenter(
            directory: directory,
            alreadyAdded: [Participant(name: "Ada", email: "ada@x.com")]
        )

        let rows = presenter.sections(for: "").flatMap(\.rows)

        XCTAssertFalse(rows.contains(.person(Person(name: "Ada Lovelace", emails: ["ada@x.com"]))))
        XCTAssertTrue(rows.contains(.person(Person(name: "Grace Hopper", emails: ["grace@navy.mil"]))))
    }

    func testFreeTextRowAppearsWhenNoExactMatch() {
        let presenter = PeoplePickerPresenter(
            directory: PeopleDirectory(sources: [
                StaticPeopleSource(providerId: "pastMeetings", people: [
                    Person(name: "Ada Lovelace", emails: ["ada@x.com"])
                ])
            ])
        )

        let rows = presenter.sections(for: "Zzz").flatMap(\.rows)

        XCTAssertEqual(rows.last, .freeText("Zzz"))
        XCTAssertEqual(presenter.participant(from: .freeText("Zzz")), Participant(name: "Zzz", email: nil))
    }

    func testSelectingPersonProducesParticipantWithPrimaryEmail() {
        let ada = Person(name: "Ada Lovelace", emails: ["a@x.com", "ada@y.com"])
        let presenter = PeoplePickerPresenter(directory: PeopleDirectory(sources: []))

        XCTAssertEqual(
            presenter.participant(from: .person(ada)),
            Participant(name: "Ada Lovelace", email: "a@x.com")
        )
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
