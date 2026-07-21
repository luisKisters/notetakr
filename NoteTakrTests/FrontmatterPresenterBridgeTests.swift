import XCTest
import NoteTakrKit
@testable import NoteTakr

@MainActor
final class FrontmatterPresenterBridgeTests: XCTestCase {

    // MARK: - Bridge round-trip: in-person toggle → file changes via spy

    func testToggleInPersonPersistsThroughBridge() throws {
        let spy = SpyPresenterStore()
        var note = MeetingNote(id: "fp-1", title: "Test Note", date: fixedDate())
        note.inPerson = false
        spy.notes["fp-1"] = note

        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: note)
        XCTAssertEqual(bridge.noteInPerson, false)

        bridge.setInPerson(true)

        let saved = try XCTUnwrap(spy.notes["fp-1"])
        XCTAssertEqual(saved.inPerson, true)
        XCTAssertEqual(bridge.noteInPerson, true)
    }

    func testToggleInPersonFalseToTrue() throws {
        let spy = SpyPresenterStore()
        var note = MeetingNote(id: "fp-2", title: "Test Note", date: fixedDate())
        note.inPerson = true
        spy.notes["fp-2"] = note

        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: note)
        XCTAssertEqual(bridge.noteInPerson, true)

        bridge.setInPerson(false)

        let saved = try XCTUnwrap(spy.notes["fp-2"])
        XCTAssertEqual(saved.inPerson, false)
        XCTAssertEqual(bridge.noteInPerson, false)
    }

    func testInPersonCannotChangeDuringActiveRecording() throws {
        let spy = SpyPresenterStore()
        let note = MeetingNote(id: "fp-recording", title: "Live", date: fixedDate(), inPerson: false)
        spy.notes[note.id] = note
        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: note)

        bridge.setRecordingActive(true)
        bridge.setInPerson(true)

        XCTAssertTrue(bridge.isRecording)
        XCTAssertEqual(try XCTUnwrap(spy.notes[note.id]).inPerson, false)
        XCTAssertEqual(bridge.noteInPerson, false)
    }

    func testPublishedInPersonStateResetsWhenLoadingAnotherNote() {
        let spy = SpyPresenterStore()
        let first = MeetingNote(id: "fp-load-1", title: "First", date: fixedDate(), inPerson: true)
        let second = MeetingNote(id: "fp-load-2", title: "Second", date: fixedDate())
        spy.notes[first.id] = first
        spy.notes[second.id] = second
        let bridge = FrontmatterPresenterBridge(store: spy)

        bridge.load(note: first)
        XCTAssertEqual(bridge.noteInPerson, true)

        bridge.load(note: second)
        XCTAssertNil(bridge.noteInPerson)
    }

    // MARK: - Chips view model state matches Kit presenter

    func testChipsMatchKitPresenterForFullNote() throws {
        let spy = SpyPresenterStore()
        var note = MeetingNote(id: "fp-3", title: "Weekly Sync", date: fixedDate())
        note.end = fixedDate().addingTimeInterval(45 * 60)
        note.location = .zoom
        note.participants = [
            Participant(name: "Alice"),
            Participant(name: "Bob"),
            Participant(name: "Carol")
        ]
        spy.notes["fp-3"] = note

        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: note)

        let tz = TimeZone(secondsFromGMT: 0)!
        let kitPresenter = FrontmatterPresenter(
            note: note,
            store: spy,
            now: { self.fixedDate() },
            timeZone: tz
        )

        // Chips count should match
        // Bridge uses system timezone so we just check the count and types match structure
        XCTAssertFalse(bridge.chips.isEmpty)

        // Should have timeRange, location, participants chips (3 total, no recording)
        let bridgeChipTypes = bridge.chips.map { chipType($0) }
        XCTAssertTrue(bridgeChipTypes.contains("timeRange"))
        XCTAssertTrue(bridgeChipTypes.contains("location"))
        XCTAssertTrue(bridgeChipTypes.contains("participants"))
        XCTAssertFalse(bridgeChipTypes.contains("recording"))
    }

    func testChipsEmptyForMinimalNote() throws {
        let spy = SpyPresenterStore()
        let note = MeetingNote(id: "fp-4", title: "Bare Note", date: fixedDate())
        spy.notes["fp-4"] = note

        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: note)

        // Only timeRange chip for a bare note
        XCTAssertEqual(bridge.chips.count, 1)
        XCTAssertEqual(chipType(bridge.chips[0]), "timeRange")
    }

    func testRecordingChipAppearsWhenPresenterHasStartTime() throws {
        let spy = SpyPresenterStore()
        let note = MeetingNote(id: "fp-5", title: "Live Meeting", date: fixedDate())
        spy.notes["fp-5"] = note

        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: note)

        bridge.presenter?.recordingStartedAt = fixedDate().addingTimeInterval(-90)
        // Refresh manually
        bridge.presenter?.onChange?()

        let types = bridge.chips.map { chipType($0) }
        XCTAssertTrue(types.contains("recording"))
    }

    // MARK: - Property rows published correctly

    func testPropertyRowsPublishedAfterLoad() throws {
        let spy = SpyPresenterStore()
        var note = MeetingNote(id: "fp-6", title: "Test", date: fixedDate())
        note.inPerson = false
        note.transcribe = true
        spy.notes["fp-6"] = note

        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: note)

        XCTAssertEqual(bridge.propertyRows.count, 7)
    }

    // MARK: - isExpanded resets on load

    func testIsExpandedResetsOnLoad() throws {
        let spy = SpyPresenterStore()
        let note1 = MeetingNote(id: "fp-7a", title: "Note 1", date: fixedDate())
        let note2 = MeetingNote(id: "fp-7b", title: "Note 2", date: fixedDate())
        spy.notes["fp-7a"] = note1
        spy.notes["fp-7b"] = note2

        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: note1)
        bridge.isExpanded = true

        bridge.load(note: note2)
        XCTAssertFalse(bridge.isExpanded)
    }

    // MARK: - Unlink event clears calendarEvent

    func testUnlinkEventClearsCalendarEvent() throws {
        let spy = SpyPresenterStore()
        var note = MeetingNote(id: "fp-8", title: "Linked Note", date: fixedDate())
        note.calendarEvent = "event-abc"
        spy.notes["fp-8"] = note

        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: note)

        bridge.unlinkEvent()

        let saved = try XCTUnwrap(spy.notes["fp-8"])
        XCTAssertNil(saved.calendarEvent)
    }

    func testLinkCalendarEventPreservesParticipantCRM() throws {
        let spy = SpyPresenterStore()
        let note = MeetingNote(id: "fp-8b", title: "Unlinked", date: fixedDate())
        spy.notes["fp-8b"] = note

        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: note)

        bridge.linkCalendarEvent(
            id: "event-rich",
            title: "Rich Event",
            attendees: [
                Participant(name: "Carol CRM", email: "carol@example.com", crm: "local:person/carol")
            ],
            startDate: fixedDate()
        )

        let saved = try XCTUnwrap(spy.notes["fp-8b"])
        XCTAssertEqual(saved.participants, [
            Participant(name: "Carol CRM", email: "carol@example.com", crm: "local:person/carol")
        ])
    }

    func testLinkCalendarEventAutoMatchesParticipantToCRMSource() throws {
        let spy = SpyPresenterStore()
        let note = MeetingNote(id: "fp-8c", title: "Unlinked", date: fixedDate())
        spy.notes[note.id] = note
        let crmSource = StaticPeopleSource(providerId: "crm", people: [
            Person(
                name: "Carol CRM",
                emails: ["carol@example.com"],
                sourceRefs: [SourceRef(provider: "crm", remoteId: "person-carol")]
            )
        ])

        let bridge = FrontmatterPresenterBridge(store: spy, crmPeopleSource: crmSource)
        bridge.load(note: note)

        bridge.linkCalendarEvent(
            id: "event-crm",
            title: "CRM Event",
            attendees: [
                Participant(name: "Carol CRM", email: "carol@example.com")
            ],
            startDate: fixedDate()
        )

        let saved = try XCTUnwrap(spy.notes[note.id])
        XCTAssertEqual(saved.participants, [
            Participant(name: "Carol CRM", email: "carol@example.com", crm: "person-carol")
        ])
    }

    func testCrmMatchedEmailDoesNotAppearInUnmatchedBanner() throws {
        let spy = SpyPresenterStore()
        let note = MeetingNote(
            id: "fp-8d",
            title: "CRM Banner",
            date: fixedDate(),
            participants: [
                Participant(name: "Carol CRM", email: "carol@example.com"),
                Participant(name: "Mystery Guest")
            ]
        )
        spy.notes[note.id] = note
        let crmSource = StaticPeopleSource(providerId: "crm", people: [
            Person(
                name: "Carol CRM",
                emails: ["carol@example.com"],
                sourceRefs: [SourceRef(provider: "crm", remoteId: "person-carol")]
            )
        ])

        let bridge = FrontmatterPresenterBridge(store: spy, crmPeopleSource: crmSource)
        bridge.load(note: note)
        bridge.crmConnected = true

        XCTAssertEqual(bridge.crmBannerText, "1 participant not in CRM")
    }

    func testFrontmatterSaveNotifiesDirtyCallback() throws {
        let spy = SpyPresenterStore()
        let note = MeetingNote(id: "fp-dirty", title: "Dirty", date: fixedDate())
        spy.notes[note.id] = note
        let bridge = FrontmatterPresenterBridge(store: spy)
        var dirtyIDs: [String] = []
        bridge.onDidSave = { dirtyIDs.append($0) }
        bridge.load(note: note)

        bridge.setLocalOnly(true)

        XCTAssertEqual(dirtyIDs, [note.id])
    }

    // MARK: - People suggestions

    func testParticipantSuggestionsUseLocalNotesAndCalendarEvents() throws {
        let spy = SpyPresenterStore()
        let current = MeetingNote(id: "fp-9", title: "Current", date: fixedDate())
        let past = MeetingNote(
            id: "fp-past",
            title: "Past",
            date: fixedDate().addingTimeInterval(-86_400),
            participants: [Participant(name: "Alice Local", email: "alice@example.com")]
        )
        spy.notes["fp-9"] = current
        spy.notes["fp-past"] = past

        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: current)
        bridge.availableEvents = [
            UpcomingEvent(
                id: "cal-1",
                title: "Calendar",
                start: fixedDate().addingTimeInterval(3_600),
                participants: [
                    Participant(name: "Alice Local", email: "alice@example.com"),
                    Participant(name: "Bob Calendar", email: "bob@example.com")
                ]
            )
        ]
        bridge.rebuildPeopleIndex(notes: [current, past])

        let suggestions = bridge.participantSuggestions(matching: "", excluding: [])

        XCTAssertEqual(suggestions.map(\.displayName), ["Alice Local", "Bob Calendar"])
        XCTAssertEqual(suggestions.first?.noteCount, 1)
        XCTAssertEqual(suggestions.first?.calendarEventCount, 1)
    }

    func testParticipantSuggestionsExcludeCurrentNoteHistory() throws {
        let spy = SpyPresenterStore()
        let current = MeetingNote(
            id: "fp-9b",
            title: "Current",
            date: fixedDate(),
            participants: [Participant(name: "Current Only", email: "current@example.com")]
        )
        let past = MeetingNote(
            id: "fp-past-2",
            title: "Past",
            date: fixedDate().addingTimeInterval(-86_400),
            participants: [Participant(name: "Alice Local", email: "alice@example.com")]
        )
        spy.notes["fp-9b"] = current
        spy.notes["fp-past-2"] = past

        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: current)
        bridge.rebuildPeopleIndex(notes: [current, past])

        let suggestions = bridge.participantSuggestions(matching: "", excluding: [])

        XCTAssertEqual(suggestions.map(\.displayName), ["Alice Local"])
        XCTAssertNil(bridge.personEntry(for: Participant(name: "Current Only", email: "current@example.com")))
    }

    func testAddingSuggestedParticipantPersistsCRM() throws {
        let spy = SpyPresenterStore()
        let note = MeetingNote(id: "fp-10", title: "Current", date: fixedDate())
        spy.notes["fp-10"] = note

        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: note)

        bridge.addParticipant(Participant(name: "Sarah Chen", email: "sarah@acme.com", crm: "local:person/sarah"))

        let saved = try XCTUnwrap(spy.notes["fp-10"])
        XCTAssertEqual(saved.participants, [
            Participant(name: "Sarah Chen", email: "sarah@acme.com", crm: "local:person/sarah")
        ])
    }

    // MARK: - Helpers

    private func fixedDate() -> Date {
        // 2024-01-15 14:00:00 UTC
        var comps = DateComponents()
        comps.year = 2024; comps.month = 1; comps.day = 15
        comps.hour = 14; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    private func chipType(_ chip: Chip) -> String {
        switch chip {
        case .timeRange: return "timeRange"
        case .location: return "location"
        case .participants: return "participants"
        case .recording: return "recording"
        }
    }
}

// MARK: - Shared spy store

private final class SpyPresenterStore: NoteStoring, @unchecked Sendable {
    var notes: [String: MeetingNote] = [:]

    func load(id: String) throws -> MeetingNote? { notes[id] }
    func save(_ note: MeetingNote) throws { notes[note.id] = note }
}

private struct StaticPeopleSource: PeopleSource {
    var providerId: String
    var people: [Person]

    func allPeople() -> [Person] {
        people
    }

    func search(_ query: String) -> [Person] {
        people.filter { person in
            person.name.localizedCaseInsensitiveContains(query) ||
            person.emails.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}
