import XCTest
@testable import NoteTakrKit

final class PastMeetingsIndexTests: XCTestCase {
    func testAggregatesParticipantsAcrossNotesByEmail() {
        let notes = [
            note(id: "n1", daysAgo: 12, participants: [
                Participant(name: "Ada", email: "A@x.com")
            ]),
            note(id: "n2", daysAgo: 6, participants: [
                Participant(name: "Ada L.", email: "a@x.com")
            ]),
            note(id: "n3", daysAgo: 1, participants: [
                Participant(name: "Grace", email: "grace@navy.mil")
            ])
        ]

        let index = PastMeetingsIndex(notes: notes, now: now)

        XCTAssertEqual(index.allPeople().filter { $0.emails == ["a@x.com"] }.count, 1)
        XCTAssertEqual(index.entry(forEmail: "A@x.com")?.coMeetingCount, 2)
    }

    func testParticipantsWithoutEmailAreExcluded() {
        let index = PastMeetingsIndex(
            notes: [
                note(id: "n1", daysAgo: 1, participants: [
                    Participant(name: "Tom", email: nil),
                    Participant(name: "Ada", email: "ada@x.com")
                ])
            ],
            now: now
        )

        XCTAssertFalse(index.allPeople().contains { $0.name == "Tom" })
        XCTAssertEqual(index.allPeople().map(\.name), ["Ada"])
    }

    func testRankingPrefersFrequencyThenRecency() {
        let notes = [
            note(id: "a1", daysAgo: 60, participants: [Participant(name: "A", email: "a@x.com")]),
            note(id: "a2", daysAgo: 60, participants: [Participant(name: "A", email: "a@x.com")]),
            note(id: "a3", daysAgo: 60, participants: [Participant(name: "A", email: "a@x.com")]),
            note(id: "b1", daysAgo: 1, participants: [Participant(name: "B", email: "b@x.com")]),
            note(id: "c1", daysAgo: 1, participants: [Participant(name: "C", email: "c@x.com")]),
            note(id: "c2", daysAgo: 1, participants: [Participant(name: "C", email: "c@x.com")]),
            note(id: "c3", daysAgo: 1, participants: [Participant(name: "C", email: "c@x.com")])
        ]

        let people = PastMeetingsIndex(notes: notes, now: now).allPeople()

        XCTAssertEqual(people.map(\.name), ["C", "A", "B"])
    }

    func testSearchMatchesNameAndEmailCaseInsensitively() {
        let index = PastMeetingsIndex(
            notes: [
                note(id: "n1", daysAgo: 2, participants: [
                    Participant(name: "Ada Lovelace", email: "ada@x.com"),
                    Participant(name: "Email Match", email: "ada.research@example.com"),
                    Participant(name: "Grace Hopper", email: "grace@navy.mil")
                ])
            ],
            now: now
        )

        let lower = index.search("ada")
        let upper = index.search("ADA")

        XCTAssertEqual(lower, upper)
        XCTAssertEqual(lower.map(\.emails.first), ["ada@x.com", "ada.research@example.com"])
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(id: String, daysAgo: Int, participants: [Participant]) -> MeetingNote {
        MeetingNote(
            id: id,
            title: id,
            date: now.addingTimeInterval(-Double(daysAgo) * 24 * 60 * 60),
            participants: participants
        )
    }
}
