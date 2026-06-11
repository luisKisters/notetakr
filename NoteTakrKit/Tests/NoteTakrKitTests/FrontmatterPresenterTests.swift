import XCTest
@testable import NoteTakrKit

final class FrontmatterPresenterTests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDown() {
        for dir in tempDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs.removeAll()
    }

    // MARK: - Chip matrix: time range

    func testTimeRangeChip_withEnd() {
        let note = MeetingNote(
            id: "1", title: "T",
            date: utcDate(2026, 6, 10, 14, 0),
            end: utcDate(2026, 6, 10, 14, 45)
        )
        XCTAssertEqual(makePresenter(note: note).chips[0], .timeRange("14:00–14:45"))
    }

    func testTimeRangeChip_withoutEnd() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 10, 0))
        XCTAssertEqual(makePresenter(note: note).chips[0], .timeRange("10:00"))
    }

    func testTimeRangeChip_crossMidnight() {
        let note = MeetingNote(
            id: "1", title: "T",
            date: utcDate(2026, 6, 10, 23, 30),
            end: utcDate(2026, 6, 11, 0, 15)
        )
        XCTAssertEqual(makePresenter(note: note).chips[0], .timeRange("23:30–00:15"))
    }

    // MARK: - Chip matrix: location

    func testLocationChip_zoom() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 9, 0), location: .zoom)
        XCTAssertTrue(makePresenter(note: note).chips.contains(.location("Zoom")))
    }

    func testLocationChip_meet() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 9, 0), location: .meet)
        XCTAssertTrue(makePresenter(note: note).chips.contains(.location("Google Meet")))
    }

    func testLocationChip_teams() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 9, 0), location: .teams)
        XCTAssertTrue(makePresenter(note: note).chips.contains(.location("Teams")))
    }

    func testLocationChip_inPersonViaLocation() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 9, 0), location: .inPerson)
        XCTAssertTrue(makePresenter(note: note).chips.contains(.location("In person")))
    }

    func testLocationChip_inPersonViaFlag() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 9, 0), inPerson: true)
        XCTAssertTrue(makePresenter(note: note).chips.contains(.location("In person")))
    }

    func testLocationChip_noneLocationAndNoFlag_absent() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 9, 0), location: Location.none)
        XCTAssertFalse(makePresenter(note: note).chips.contains { if case .location = $0 { return true }; return false })
    }

    func testLocationChip_nilLocation_absent() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 9, 0))
        XCTAssertFalse(makePresenter(note: note).chips.contains { if case .location = $0 { return true }; return false })
    }

    func testLocationChip_prefersLocationText() {
        let note = MeetingNote(
            id: "1", title: "T",
            date: utcDate(2026, 6, 10, 9, 0),
            location: .zoom,
            locationText: "Acme HQ · Room 4"
        )
        XCTAssertTrue(makePresenter(note: note).chips.contains(.location("Acme HQ · Room 4")))
        XCTAssertFalse(makePresenter(note: note).chips.contains(.location("Zoom")))
    }

    // MARK: - Chip matrix: participants

    func testParticipantsChip_absent_whenEmpty() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 9, 0))
        XCTAssertFalse(makePresenter(note: note).chips.contains { if case .participants = $0 { return true }; return false })
    }

    func testParticipantsChip_singular() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 9, 0),
                               participants: [Participant(name: "Alice")])
        XCTAssertTrue(makePresenter(note: note).chips.contains(.participants("1 person")))
    }

    func testParticipantsChip_plural() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 9, 0),
                               participants: [Participant(name: "Alice"), Participant(name: "Bob"), Participant(name: "Charlie")])
        XCTAssertTrue(makePresenter(note: note).chips.contains(.participants("3 people")))
    }

    // MARK: - Chip matrix: full / partial / empty

    func testFullMetadata_allChipsPresent() {
        let note = MeetingNote(
            id: "1", title: "Standup",
            date: utcDate(2026, 6, 10, 14, 0),
            end: utcDate(2026, 6, 10, 14, 45),
            participants: [Participant(name: "Alice"), Participant(name: "Bob")],
            location: .zoom
        )
        let chips = makePresenter(note: note).chips
        XCTAssertEqual(chips.count, 3)
        XCTAssertEqual(chips[0], .timeRange("14:00–14:45"))
        XCTAssertEqual(chips[1], .location("Zoom"))
        XCTAssertEqual(chips[2], .participants("2 people"))
    }

    func testPartialMetadata_noParticipants() {
        let note = MeetingNote(
            id: "1", title: "T",
            date: utcDate(2026, 6, 10, 9, 0),
            end: utcDate(2026, 6, 10, 9, 30),
            location: .meet
        )
        let chips = makePresenter(note: note).chips
        XCTAssertEqual(chips.count, 2)
        XCTAssertEqual(chips[0], .timeRange("09:00–09:30"))
        XCTAssertEqual(chips[1], .location("Google Meet"))
    }

    func testEmptyMetadata_onlyTimeChip() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 10, 0))
        let chips = makePresenter(note: note).chips
        XCTAssertEqual(chips.count, 1)
        XCTAssertEqual(chips[0], .timeRange("10:00"))
    }

    // MARK: - Chip matrix: REC chip

    func testRecordingChip_absentWhenNotRecording() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 10, 0))
        let presenter = makePresenter(note: note)
        XCTAssertFalse(presenter.chips.contains { if case .recording = $0 { return true }; return false })
    }

    func testRecordingChip_presentWhileRecording() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 10, 0))
        var currentTime = utcDate(2026, 6, 10, 10, 0)
        let presenter = FrontmatterPresenter(
            note: note,
            store: StoreSpy(),
            now: { currentTime },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        presenter.recordingStartedAt = currentTime
        currentTime = currentTime.addingTimeInterval(754) // 12:34
        let recChip = presenter.chips.first { if case .recording = $0 { return true }; return false }
        XCTAssertEqual(recChip, .recording("12:34"))
    }

    func testRecordingChip_absentAfterStop() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 10, 0))
        let start = utcDate(2026, 6, 10, 10, 0)
        let presenter = FrontmatterPresenter(
            note: note,
            store: StoreSpy(),
            now: { start.addingTimeInterval(60) },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        presenter.recordingStartedAt = start
        XCTAssertTrue(presenter.chips.contains { if case .recording = $0 { return true }; return false })
        presenter.recordingStartedAt = nil
        XCTAssertFalse(presenter.chips.contains { if case .recording = $0 { return true }; return false })
    }

    // MARK: - Elapsed formatting

    func testElapsedFormat_seconds() {
        XCTAssertEqual(FrontmatterPresenter.formatElapsed(9), "0:09")
    }

    func testElapsedFormat_minutesAndSeconds() {
        XCTAssertEqual(FrontmatterPresenter.formatElapsed(754), "12:34")
    }

    func testElapsedFormat_hoursMinutesSeconds() {
        XCTAssertEqual(FrontmatterPresenter.formatElapsed(3723), "1:02:03")
    }

    func testElapsedFormat_zero() {
        XCTAssertEqual(FrontmatterPresenter.formatElapsed(0), "0:00")
    }

    func testElapsedFormat_exactHour() {
        XCTAssertEqual(FrontmatterPresenter.formatElapsed(3600), "1:00:00")
    }

    // MARK: - Property rows (updated for new PropertyRow structure)

    func testPropertyRows_structure() {
        let date = utcDate(2026, 6, 10, 14, 0)
        let end = utcDate(2026, 6, 10, 14, 45)
        let note = MeetingNote(
            id: "1", title: "Weekly Sync",
            date: date, end: end,
            calendarEvent: "CAL-123",
            participants: [Participant(name: "Alice")],
            locationText: "Acme HQ · Room 4",
            meetingLink: "https://zoom.us/j/123",
            inPerson: false
        )
        let rows = makePresenter(note: note).propertyRows
        // event, dateTime, people, location, meetingLink, inPerson, transcript
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows[0], .event(id: "CAL-123", title: "Weekly Sync"))
        XCTAssertEqual(rows[1], .dateTime(date: date, end: end))
        XCTAssertEqual(rows[2], .people([Participant(name: "Alice")]))
        XCTAssertEqual(rows[3], .location("Acme HQ · Room 4"))
        XCTAssertEqual(rows[4], .meetingLink("https://zoom.us/j/123"))
        XCTAssertEqual(rows[5], .inPerson(false))
        XCTAssertEqual(rows[6], .transcript)
    }

    func testPropertyRows_nilOptionals() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 14, 0))
        let rows = makePresenter(note: note).propertyRows
        XCTAssertEqual(rows[0], .event(id: nil, title: "T"))
        XCTAssertEqual(rows[1], .dateTime(date: note.date, end: nil))
        XCTAssertEqual(rows[2], .people([]))
        XCTAssertEqual(rows[3], .location(nil))
        XCTAssertEqual(rows[4], .meetingLink(nil))
        XCTAssertEqual(rows[5], .inPerson(false))
        XCTAssertEqual(rows[6], .transcript)
    }

    func testIsExpandedToggle() {
        let presenter = makePresenter(note: MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 9, 0)))
        XCTAssertFalse(presenter.isExpanded)
        presenter.isExpanded = true
        XCTAssertTrue(presenter.isExpanded)
    }

    // MARK: - Mutations (temp-dir store)

    func testSetInPersonPersists() throws {
        let (presenter, store) = try makeTempPresenter(note: baseNote())
        try presenter.setInPerson(true)
        let saved = try store.load(id: "test-id")
        XCTAssertEqual(saved?.inPerson, true)
    }

    func testSetInPersonFalsePersists() throws {
        var note = baseNote()
        note.inPerson = true
        let (presenter, store) = try makeTempPresenter(note: note)
        try presenter.setInPerson(false)
        let saved = try store.load(id: "test-id")
        XCTAssertEqual(saved?.inPerson, false)
    }

    func testSetInPerson_reflectsInEffectiveSettings() throws {
        let (presenter, _) = try makeTempPresenter(note: baseNote())
        try presenter.setInPerson(true)
        XCTAssertEqual(presenter.note.inPerson, true,
            "In-person flag must be set so EffectiveMeetingSettings disables system-audio capture")
    }

    func testLinkEvent_setsAllFields() throws {
        let note = baseNote()
        let (presenter, store) = try makeTempPresenter(note: note)
        let start = utcDate(2026, 6, 10, 14, 0)
        let end = utcDate(2026, 6, 10, 14, 45)

        let event = LinkedEventInfo(
            eventID: "EVT-123",
            title: "Weekly Sync",
            participants: [
                Participant(name: "Alice", email: "alice@example.com"),
                Participant(name: "Bob")
            ],
            startDate: start,
            endDate: end,
            locationText: "Acme HQ · Room 4",
            meetingLink: "https://zoom.us/j/8421337"
        )
        try presenter.linkEvent(event)

        let saved = try XCTUnwrap(try store.load(id: "test-id"))
        XCTAssertEqual(saved.calendarEvent, "EVT-123")
        XCTAssertEqual(saved.title, "Weekly Sync")
        XCTAssertEqual(saved.date, start)
        XCTAssertEqual(saved.end, end)
        XCTAssertEqual(saved.locationText, "Acme HQ · Room 4")
        XCTAssertEqual(saved.meetingLink, "https://zoom.us/j/8421337")
        XCTAssertEqual(saved.participants.count, 2)
    }

    func testLinkEvent_mergesParticipantsNoDuplicates() throws {
        var note = baseNote()
        note.participants = [Participant(name: "Existing")]
        let (presenter, store) = try makeTempPresenter(note: note)

        let event = LinkedEventInfo(
            eventID: "EVT-123",
            title: "Q3 Planning",
            participants: [
                Participant(name: "Existing"),
                Participant(name: "New Person")
            ]
        )
        try presenter.linkEvent(event)

        let saved = try XCTUnwrap(try store.load(id: "test-id"))
        XCTAssertEqual(saved.participants.count, 2, "Existing participant must not be duplicated")
        XCTAssertTrue(saved.participants.contains(Participant(name: "Existing")))
        XCTAssertTrue(saved.participants.contains(Participant(name: "New Person")))
    }

    func testLinkEvent_doesNotUpdateDateWhenNil() throws {
        let originalDate = utcDate(2026, 6, 10, 14, 0)
        var note = baseNote()
        note.date = originalDate
        let (presenter, store) = try makeTempPresenter(note: note)

        let event = LinkedEventInfo(
            eventID: "EVT-123",
            title: "Meeting",
            participants: [],
            startDate: nil,  // no date update
            endDate: nil
        )
        try presenter.linkEvent(event)

        let saved = try XCTUnwrap(try store.load(id: "test-id"))
        XCTAssertEqual(saved.date, originalDate, "Date must not change when startDate is nil")
    }

    func testUnlinkEvent_clearsEventButKeepsParticipants() throws {
        var note = baseNote()
        note.calendarEvent = "EVT-123"
        note.participants = [Participant(name: "Alice"), Participant(name: "Bob")]
        let (presenter, store) = try makeTempPresenter(note: note)

        try presenter.unlinkEvent()

        let saved = try XCTUnwrap(try store.load(id: "test-id"))
        XCTAssertNil(saved.calendarEvent)
        XCTAssertEqual(saved.participants.count, 2, "Participants must survive unlink")
    }

    func testAddParticipantPersists() throws {
        let (presenter, store) = try makeTempPresenter(note: baseNote())
        try presenter.addParticipant(Participant(name: "Alice", email: "alice@example.com"))

        let saved = try XCTUnwrap(try store.load(id: "test-id"))
        XCTAssertEqual(saved.participants.count, 1)
        XCTAssertEqual(saved.participants[0].name, "Alice")
        XCTAssertEqual(saved.participants[0].email, "alice@example.com")
    }

    func testRemoveParticipantPersists() throws {
        var note = baseNote()
        note.participants = [Participant(name: "Alice"), Participant(name: "Bob")]
        let (presenter, store) = try makeTempPresenter(note: note)

        try presenter.removeParticipant(Participant(name: "Alice"))

        let saved = try XCTUnwrap(try store.load(id: "test-id"))
        XCTAssertEqual(saved.participants.count, 1)
        XCTAssertEqual(saved.participants[0].name, "Bob")
    }

    func testSetLocationText_persists() throws {
        let (presenter, store) = try makeTempPresenter(note: baseNote())
        try presenter.setLocationText("Acme HQ · Room 4")
        let saved = try XCTUnwrap(try store.load(id: "test-id"))
        XCTAssertEqual(saved.locationText, "Acme HQ · Room 4")
    }

    func testSetLocationText_emptyStringBecomesNil() throws {
        var note = baseNote()
        note.locationText = "Some location"
        let (presenter, store) = try makeTempPresenter(note: note)
        try presenter.setLocationText("")
        let saved = try XCTUnwrap(try store.load(id: "test-id"))
        XCTAssertNil(saved.locationText)
    }

    func testSetLocationText_whitespaceOnlyBecomesNil() throws {
        let (presenter, store) = try makeTempPresenter(note: baseNote())
        try presenter.setLocationText("   ")
        let saved = try XCTUnwrap(try store.load(id: "test-id"))
        XCTAssertNil(saved.locationText)
    }

    func testSetTranscribe_persists() throws {
        let (presenter, store) = try makeTempPresenter(note: baseNote())
        try presenter.setTranscribe(false)
        let saved = try XCTUnwrap(try store.load(id: "test-id"))
        XCTAssertEqual(saved.transcribe, false)
    }

    func testSetTranscribe_firesOnChange() throws {
        let (presenter, _) = try makeTempPresenter(note: baseNote())
        var count = 0
        presenter.onChange = { count += 1 }
        try presenter.setTranscribe(false)
        XCTAssertEqual(count, 1)
    }

    func testSetLanguage_persists() throws {
        let (presenter, store) = try makeTempPresenter(note: baseNote())
        try presenter.setLanguage(.code("fr"))
        let saved = try XCTUnwrap(try store.load(id: "test-id"))
        XCTAssertEqual(saved.language, .code("fr"))
    }

    func testSetLanguage_firesOnChange() throws {
        let (presenter, _) = try makeTempPresenter(note: baseNote())
        var count = 0
        presenter.onChange = { count += 1 }
        try presenter.setLanguage(.code("de"))
        XCTAssertEqual(count, 1)
    }

    func testSetMeetingLink_persists() throws {
        let (presenter, store) = try makeTempPresenter(note: baseNote())
        try presenter.setMeetingLink("https://zoom.us/j/8421337")
        let saved = try XCTUnwrap(try store.load(id: "test-id"))
        XCTAssertEqual(saved.meetingLink, "https://zoom.us/j/8421337")
    }

    func testSetMeetingLink_emptyStringBecomesNil() throws {
        var note = baseNote()
        note.meetingLink = "https://zoom.us/j/123"
        let (presenter, store) = try makeTempPresenter(note: note)
        try presenter.setMeetingLink("")
        let saved = try XCTUnwrap(try store.load(id: "test-id"))
        XCTAssertNil(saved.meetingLink)
    }

    func testSetDate_persists() throws {
        let (presenter, store) = try makeTempPresenter(note: baseNote())
        let newDate = utcDate(2026, 6, 11, 10, 30)
        let newEnd = utcDate(2026, 6, 11, 11, 0)
        try presenter.setDate(newDate, end: newEnd)
        let saved = try XCTUnwrap(try store.load(id: "test-id"))
        XCTAssertEqual(saved.date, newDate)
        XCTAssertEqual(saved.end, newEnd)
    }

    func testPropertyRow_location_nil_whenNoLocationText() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 14, 0))
        let rows = makePresenter(note: note).propertyRows
        XCTAssertEqual(rows[3], .location(nil))
    }

    func testPropertyRow_location_nonNil_whenLocationTextSet() {
        let note = MeetingNote(
            id: "1", title: "T",
            date: utcDate(2026, 6, 10, 14, 0),
            locationText: "Café Nord"
        )
        let rows = makePresenter(note: note).propertyRows
        XCTAssertEqual(rows[3], .location("Café Nord"))
    }

    func testPropertyRow_meetingLink_nil_whenNotSet() {
        let note = MeetingNote(id: "1", title: "T", date: utcDate(2026, 6, 10, 14, 0))
        let rows = makePresenter(note: note).propertyRows
        XCTAssertEqual(rows[4], .meetingLink(nil))
    }

    func testPropertyRow_meetingLink_nonNil_whenSet() {
        let note = MeetingNote(
            id: "1", title: "T",
            date: utcDate(2026, 6, 10, 14, 0),
            meetingLink: "https://meet.google.com/abc"
        )
        let rows = makePresenter(note: note).propertyRows
        XCTAssertEqual(rows[4], .meetingLink("https://meet.google.com/abc"))
    }

    func testOnChangeCalledAfterEachMutation() throws {
        let (presenter, _) = try makeTempPresenter(note: baseNote())
        var count = 0
        presenter.onChange = { count += 1 }

        try presenter.setInPerson(true)
        XCTAssertEqual(count, 1)
        try presenter.addParticipant(Participant(name: "Alice"))
        XCTAssertEqual(count, 2)
        try presenter.unlinkEvent()
        XCTAssertEqual(count, 3)
        try presenter.removeParticipant(Participant(name: "Alice"))
        XCTAssertEqual(count, 4)
        try presenter.setLocationText("Room 4")
        XCTAssertEqual(count, 5)
        try presenter.setMeetingLink("https://zoom.us/j/1")
        XCTAssertEqual(count, 6)
        try presenter.setTranscribe(false)
        XCTAssertEqual(count, 7)
        try presenter.setLanguage(.code("es"))
        XCTAssertEqual(count, 8)
    }

    func testNoteReflectsInMemoryMutations() throws {
        let (presenter, _) = try makeTempPresenter(note: baseNote())
        try presenter.setInPerson(true)
        XCTAssertEqual(presenter.note.inPerson, true)

        try presenter.addParticipant(Participant(name: "Alice"))
        XCTAssertEqual(presenter.note.participants.count, 1)

        try presenter.setLocationText("Room 4")
        XCTAssertEqual(presenter.note.locationText, "Room 4")

        try presenter.setMeetingLink("https://zoom.us/j/1")
        XCTAssertEqual(presenter.note.meetingLink, "https://zoom.us/j/1")
    }

    // MARK: - Helpers

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = 0
        c.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private class StoreSpy: NoteStoring {
        private var notes: [String: MeetingNote] = [:]
        func load(id: String) throws -> MeetingNote? { notes[id] }
        func save(_ note: MeetingNote) throws { notes[note.id] = note }
    }

    private func makePresenter(note: MeetingNote) -> FrontmatterPresenter {
        FrontmatterPresenter(
            note: note,
            store: StoreSpy(),
            now: { self.utcDate(2026, 6, 10, 14, 0) },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    private func baseNote() -> MeetingNote {
        MeetingNote(id: "test-id", title: "Test Meeting", date: utcDate(2026, 6, 10, 14, 0))
    }

    private func makeTempPresenter(note: MeetingNote) throws -> (FrontmatterPresenter, NoteStore) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrontmatterPresenterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirs.append(tempDir)
        let store = NoteStore(root: tempDir)
        try store.save(note)
        let presenter = FrontmatterPresenter(
            note: note,
            store: store,
            now: { self.utcDate(2026, 6, 10, 14, 0) },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        return (presenter, store)
    }
}
