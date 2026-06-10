import XCTest
@testable import NoteTakrKit

final class SwitcherViewModelTests: XCTestCase {

    // MARK: - Shared fixtures

    private static var utcCal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    // Fixed "now": 2026-06-10 10:00 UTC (Wednesday)
    private var fixedNow: Date { Self.utcCal.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 10))! }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        Self.utcCal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeNote(id: String, title: String, date: Date, end: Date? = nil,
                          calendarEvent: String? = nil, participants: [Participant] = []) -> MeetingNote {
        MeetingNote(id: id, title: title, date: date, end: end,
                    calendarEvent: calendarEvent, participants: participants)
    }

    private func makeEvent(id: String, title: String, start: Date, end: Date? = nil,
                           participants: [Participant] = []) -> UpcomingEvent {
        UpcomingEvent(id: id, title: title, start: start, end: end, participants: participants)
    }

    private func makeVM(notes: [MeetingNote] = [], events: [UpcomingEvent] = [],
                        defaults: any NoteDefaultsProviding = NoopDefaultsProvider()) -> (SwitcherViewModel, SpyStore) {
        let spy = SpyStore(notes: notes)
        let vm = SwitcherViewModel(
            noteListProvider: spy,
            eventsProvider: FixedEventsProvider(events: events),
            now: { self.fixedNow },
            store: spy,
            defaultsProvider: defaults,
            calendar: Self.utcCal
        )
        return (vm, spy)
    }

    // MARK: - Grouping: Today / Yesterday / Tomorrow

    func testTodayNoteAppearsInTodayGroup() {
        let note = makeNote(id: "1", title: "Standup", date: utcDate(2026, 6, 10, 9))
        let (vm, _) = makeVM(notes: [note])
        XCTAssertTrue(vm.groups.contains { $0.label == "Today" })
    }

    func testYesterdayNoteAppearsInYesterdayGroup() {
        let note = makeNote(id: "1", title: "Retro", date: utcDate(2026, 6, 9, 14))
        let (vm, _) = makeVM(notes: [note])
        XCTAssertTrue(vm.groups.contains { $0.label == "Yesterday" })
    }

    func testTomorrowEventAppearsInTomorrowGroup() {
        let event = makeEvent(id: "e1", title: "Kickoff", start: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM(events: [event])
        XCTAssertTrue(vm.groups.contains { $0.label == "Tomorrow" })
    }

    func testFutureGroupsBeforeCurrentAndPastGroups() {
        let pastNote = makeNote(id: "n1", title: "Past", date: utcDate(2026, 6, 9, 10))
        let futureEvent = makeEvent(id: "e1", title: "Future", start: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM(notes: [pastNote], events: [futureEvent])
        let labels = vm.groups.map { $0.label }
        let tomorrowIdx = labels.firstIndex(of: "Tomorrow")!
        let yesterdayIdx = labels.firstIndex(of: "Yesterday")!
        XCTAssertLessThan(tomorrowIdx, yesterdayIdx, "Future groups must appear before past groups")
    }

    func testTodayGroupBetweenFutureAndPast() {
        let todayNote = makeNote(id: "n1", title: "Today", date: utcDate(2026, 6, 10, 9))
        let pastNote = makeNote(id: "n2", title: "Past", date: utcDate(2026, 6, 9, 10))
        let futureEvent = makeEvent(id: "e1", title: "Future", start: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM(notes: [todayNote, pastNote], events: [futureEvent])
        let labels = vm.groups.map { $0.label }
        let tomorrowIdx = labels.firstIndex(of: "Tomorrow")!
        let todayIdx = labels.firstIndex(of: "Today")!
        let yesterdayIdx = labels.firstIndex(of: "Yesterday")!
        XCTAssertLessThan(tomorrowIdx, todayIdx)
        XCTAssertLessThan(todayIdx, yesterdayIdx)
    }

    func testWeekdayLabelForFutureDayIn2To7Range() {
        // 2026-06-12 is a Friday
        let event = makeEvent(id: "e1", title: "Review", start: utcDate(2026, 6, 12, 10))
        let (vm, _) = makeVM(events: [event])
        XCTAssertTrue(vm.groups.contains { $0.label == "Friday" }, "Expected 'Friday' label, got: \(vm.groups.map { $0.label })")
    }

    func testWeekdayLabelForPastDayIn2To7DaysAgo() {
        // 2026-06-08 is a Monday (2 days ago)
        let note = makeNote(id: "n1", title: "Old", date: utcDate(2026, 6, 8, 10))
        let (vm, _) = makeVM(notes: [note])
        XCTAssertTrue(vm.groups.contains { $0.label == "Monday" }, "Expected 'Monday' label, got: \(vm.groups.map { $0.label })")
    }

    func testOldDateUsesShortFormat() {
        let note = makeNote(id: "n1", title: "Old", date: utcDate(2026, 5, 1, 10))
        let (vm, _) = makeVM(notes: [note])
        XCTAssertTrue(vm.groups.contains { $0.label == "May 1" }, "Expected 'May 1' label, got: \(vm.groups.map { $0.label })")
    }

    // MARK: - Ordering within groups

    func testFutureGroupItemsAscending() {
        let e1 = makeEvent(id: "e1", title: "First",  start: utcDate(2026, 6, 11, 9))
        let e2 = makeEvent(id: "e2", title: "Second", start: utcDate(2026, 6, 11, 14))
        let (vm, _) = makeVM(events: [e2, e1])  // intentionally reversed
        guard let group = vm.groups.first(where: { $0.label == "Tomorrow" }) else {
            return XCTFail("No Tomorrow group")
        }
        let titles = group.items.map { itemTitle($0) }
        XCTAssertEqual(titles, ["First", "Second"])
    }

    func testPastGroupItemsDescending() {
        let n1 = makeNote(id: "n1", title: "Morning", date: utcDate(2026, 6, 9, 9))
        let n2 = makeNote(id: "n2", title: "Afternoon", date: utcDate(2026, 6, 9, 14))
        let (vm, _) = makeVM(notes: [n1, n2])
        guard let group = vm.groups.first(where: { $0.label == "Yesterday" }) else {
            return XCTFail("No Yesterday group")
        }
        let titles = group.items.map { itemTitle($0) }
        XCTAssertEqual(titles, ["Afternoon", "Morning"])
    }

    // MARK: - Dot state

    func testUpcomingDotStateForFutureNote() {
        let note = makeNote(id: "n1", title: "Future", date: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM(notes: [note])
        XCTAssertEqual(vm.groups.flatMap { $0.items }.first?.dotState, .upcoming)
    }

    func testCurrentDotStateWhenNowBetweenStartAndEnd() {
        // fixedNow = 10:00; event runs 09:00–11:00
        let event = makeEvent(id: "e1", title: "Now", start: utcDate(2026, 6, 10, 9), end: utcDate(2026, 6, 10, 11))
        let (vm, _) = makeVM(events: [event])
        XCTAssertEqual(vm.groups.flatMap { $0.items }.first?.dotState, .current)
    }

    func testPastDotStateAfterEndTime() {
        // ended at 09:00, now is 10:00
        let note = makeNote(id: "n1", title: "Done", date: utcDate(2026, 6, 10, 8), end: utcDate(2026, 6, 10, 9))
        let (vm, _) = makeVM(notes: [note])
        XCTAssertEqual(vm.groups.flatMap { $0.items }.first?.dotState, .past)
    }

    func testPastDotStateNoEndTime() {
        let note = makeNote(id: "n1", title: "Past", date: utcDate(2026, 6, 9, 14))
        let (vm, _) = makeVM(notes: [note])
        XCTAssertEqual(vm.groups.flatMap { $0.items }.first?.dotState, .past)
    }

    // MARK: - Ghost de-duplication

    func testLinkedEventNotDuplicated() {
        let note = makeNote(id: "n1", title: "Standup", date: utcDate(2026, 6, 10, 9), calendarEvent: "cal-1")
        let event = makeEvent(id: "cal-1", title: "Standup", start: utcDate(2026, 6, 10, 9))
        let (vm, _) = makeVM(notes: [note], events: [event])
        let allItems = vm.groups.flatMap { $0.items }
        // Only the note should appear, not the event
        XCTAssertEqual(allItems.count, 1)
        if case .note(let id, _, _, _) = allItems[0].kind {
            XCTAssertEqual(id, "n1")
        } else {
            XCTFail("Expected a note item, got event")
        }
    }

    func testUnlinkedEventAppearsAsSeparateGhost() {
        let note = makeNote(id: "n1", title: "Standup", date: utcDate(2026, 6, 10, 9), calendarEvent: "cal-1")
        let otherEvent = makeEvent(id: "cal-2", title: "Lunch", start: utcDate(2026, 6, 10, 12))
        let (vm, _) = makeVM(notes: [note], events: [otherEvent])
        let allItems = vm.groups.flatMap { $0.items }
        XCTAssertEqual(allItems.count, 2)
    }

    func testNoteWithoutLinkedEventDoesNotDedupOtherEvents() {
        let note = makeNote(id: "n1", title: "Note", date: utcDate(2026, 6, 10, 9))
        let event = makeEvent(id: "cal-1", title: "Event", start: utcDate(2026, 6, 10, 9))
        let (vm, _) = makeVM(notes: [note], events: [event])
        XCTAssertEqual(vm.groups.flatMap { $0.items }.count, 2)
    }

    // MARK: - Search

    func testSearchByTitle() {
        let n1 = makeNote(id: "n1", title: "Weekly Standup", date: utcDate(2026, 6, 9, 9))
        let n2 = makeNote(id: "n2", title: "Design Review", date: utcDate(2026, 6, 8, 14))
        let (vm, _) = makeVM(notes: [n1, n2])
        vm.searchQuery = "standup"
        XCTAssertEqual(vm.groups.flatMap { $0.items }.count, 1)
        XCTAssertEqual(itemTitle(vm.groups.flatMap { $0.items }[0]), "Weekly Standup")
    }

    func testSearchIsCaseInsensitive() {
        let n = makeNote(id: "n1", title: "Sprint Review", date: utcDate(2026, 6, 9, 10))
        let (vm, _) = makeVM(notes: [n])
        vm.searchQuery = "SPRINT"
        XCTAssertEqual(vm.groups.flatMap { $0.items }.count, 1)
    }

    func testSearchIsDiacriticInsensitive() {
        let n = makeNote(id: "n1", title: "Meeting",
                         date: utcDate(2026, 6, 9, 10),
                         participants: [Participant(name: "Müller")])
        let (vm, _) = makeVM(notes: [n])
        vm.searchQuery = "muller"
        XCTAssertEqual(vm.groups.flatMap { $0.items }.count, 1, "Should match Müller with query 'muller'")
    }

    func testSearchMatchesParticipantNames() {
        let n = makeNote(id: "n1", title: "All-hands",
                         date: utcDate(2026, 6, 9, 10),
                         participants: [Participant(name: "Alice"), Participant(name: "Bob")])
        let (vm, _) = makeVM(notes: [n])
        vm.searchQuery = "alice"
        XCTAssertEqual(vm.groups.flatMap { $0.items }.count, 1)
    }

    func testSearchMatchesEventTitle() {
        let e = makeEvent(id: "e1", title: "Quarterly Review", start: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM(events: [e])
        vm.searchQuery = "quarterly"
        XCTAssertEqual(vm.groups.flatMap { $0.items }.count, 1)
    }

    func testSearchNoMatchReturnsEmpty() {
        let n = makeNote(id: "n1", title: "Planning", date: utcDate(2026, 6, 9, 10))
        let (vm, _) = makeVM(notes: [n])
        vm.searchQuery = "xyz-no-match"
        XCTAssertTrue(vm.groups.flatMap { $0.items }.isEmpty)
    }

    func testClearingSearchRestoresAllItems() {
        let n = makeNote(id: "n1", title: "Planning", date: utcDate(2026, 6, 9, 10))
        let (vm, _) = makeVM(notes: [n])
        vm.searchQuery = "xyz"
        vm.searchQuery = ""
        XCTAssertEqual(vm.groups.flatMap { $0.items }.count, 1)
    }

    func testSearchWithAccentMatchesWithoutAccent() {
        let n = makeNote(id: "n1", title: "Café meeting", date: utcDate(2026, 6, 9, 10))
        let (vm, _) = makeVM(notes: [n])
        vm.searchQuery = "cafe"
        XCTAssertEqual(vm.groups.flatMap { $0.items }.count, 1, "Should match 'Café' with query 'cafe'")
    }

    // MARK: - Selection and navigation

    func testInitialSelectionIsZero() {
        let n = makeNote(id: "n1", title: "A", date: utcDate(2026, 6, 9, 10))
        let (vm, _) = makeVM(notes: [n])
        XCTAssertEqual(vm.selectedIndex, 0)
    }

    func testMoveDownAdvancesIndex() {
        let notes = [
            makeNote(id: "n1", title: "A", date: utcDate(2026, 6, 9, 14)),
            makeNote(id: "n2", title: "B", date: utcDate(2026, 6, 9, 10)),
        ]
        let (vm, _) = makeVM(notes: notes)
        vm.moveDown()
        XCTAssertEqual(vm.selectedIndex, 1)
    }

    func testMoveDownWrapsToZero() {
        let notes = [
            makeNote(id: "n1", title: "A", date: utcDate(2026, 6, 9, 14)),
            makeNote(id: "n2", title: "B", date: utcDate(2026, 6, 9, 10)),
        ]
        let (vm, _) = makeVM(notes: notes)
        vm.moveDown()
        vm.moveDown()
        XCTAssertEqual(vm.selectedIndex, 0, "Should wrap from last item back to 0")
    }

    func testMoveUpFromZeroWrapsToLast() {
        let notes = [
            makeNote(id: "n1", title: "A", date: utcDate(2026, 6, 9, 14)),
            makeNote(id: "n2", title: "B", date: utcDate(2026, 6, 9, 10)),
        ]
        let (vm, _) = makeVM(notes: notes)
        vm.moveUp()
        XCTAssertEqual(vm.selectedIndex, 1, "Should wrap from index 0 to last index")
    }

    func testSelectionSkipsGroupHeadersAcrossGroups() {
        // Two notes in different day groups
        let todayNote  = makeNote(id: "n1", title: "Today",    date: utcDate(2026, 6, 10, 9))
        let yesterNote = makeNote(id: "n2", title: "Yesterday", date: utcDate(2026, 6, 9, 14))
        let (vm, _) = makeVM(notes: [todayNote, yesterNote])
        // Flat items: [today-note, yesterday-note]
        vm.moveDown()  // 0 → 1
        if let item = vm.selectedItem, case .note(let id, _, _, _) = item.kind {
            XCTAssertEqual(id, "n2")
        } else {
            XCTFail("Expected second note selected after moveDown")
        }
    }

    func testOpenReturnsSelectedNoteID() {
        let note = makeNote(id: "abc-123", title: "Standup", date: utcDate(2026, 6, 9, 10))
        let (vm, _) = makeVM(notes: [note])
        XCTAssertEqual(vm.open(), "abc-123")
    }

    func testOpenReturnsNilWhenEventSelected() {
        let event = makeEvent(id: "e1", title: "Event", start: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM(events: [event])
        XCTAssertNil(vm.open(), "open() must return nil when a ghost event is selected")
    }

    func testSelectionClampedAfterSearchFiltersItems() {
        let notes = [
            makeNote(id: "n1", title: "Alpha", date: utcDate(2026, 6, 9, 14)),
            makeNote(id: "n2", title: "Beta",  date: utcDate(2026, 6, 9, 10)),
        ]
        let (vm, _) = makeVM(notes: notes)
        vm.moveDown()  // selectedIndex = 1
        vm.searchQuery = "alpha"  // only 1 item remains; index should clamp to 0
        XCTAssertEqual(vm.selectedIndex, 0)
    }

    // MARK: - createNote(from:)

    func testCreateNoteFromEventPreFillsFields() throws {
        let event = makeEvent(
            id: "cal-42",
            title: "Design Sprint",
            start: utcDate(2026, 6, 11, 9),
            end: utcDate(2026, 6, 11, 17),
            participants: [Participant(name: "Alice", email: "alice@example.com")]
        )
        let (vm, _) = makeVM()
        let note = try vm.createNote(from: event)
        XCTAssertEqual(note.title, "Design Sprint")
        XCTAssertEqual(note.date, utcDate(2026, 6, 11, 9))
        XCTAssertEqual(note.end, utcDate(2026, 6, 11, 17))
        XCTAssertEqual(note.calendarEvent, "cal-42")
        XCTAssertEqual(note.participants, [Participant(name: "Alice", email: "alice@example.com")])
    }

    func testCreateNoteAppliesDefaultTranscribe() throws {
        let defaults = FixedDefaults(transcribeByDefault: false, defaultLanguage: .auto, inPersonByDefault: false)
        let event = makeEvent(id: "e1", title: "E", start: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM(defaults: defaults)
        let note = try vm.createNote(from: event)
        XCTAssertEqual(note.transcribe, false)
    }

    func testCreateNoteAppliesDefaultLanguageWhenNotAuto() throws {
        let defaults = FixedDefaults(transcribeByDefault: true, defaultLanguage: .code("fr"), inPersonByDefault: false)
        let event = makeEvent(id: "e1", title: "E", start: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM(defaults: defaults)
        let note = try vm.createNote(from: event)
        XCTAssertEqual(note.language, .code("fr"))
    }

    func testCreateNoteLanguageNilWhenAutoDefault() throws {
        let event = makeEvent(id: "e1", title: "E", start: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM()  // NoopDefaultsProvider has .auto
        let note = try vm.createNote(from: event)
        XCTAssertNil(note.language, "language should be nil (not stored) when default is auto")
    }

    func testCreateNoteInPersonNilWhenDefaultIsFalse() throws {
        let event = makeEvent(id: "e1", title: "E", start: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM()  // inPersonByDefault = false
        let note = try vm.createNote(from: event)
        XCTAssertNil(note.inPerson, "inPerson should be nil when inPersonByDefault is false")
    }

    func testCreateNoteInPersonTrueWhenDefaultIsTrue() throws {
        let defaults = FixedDefaults(transcribeByDefault: true, defaultLanguage: .auto, inPersonByDefault: true)
        let event = makeEvent(id: "e1", title: "E", start: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM(defaults: defaults)
        let note = try vm.createNote(from: event)
        XCTAssertEqual(note.inPerson, true)
    }

    func testCreatedNoteAppearsInGroups() throws {
        // Event happening now: start < fixedNow < end
        let event = makeEvent(id: "e1", title: "Live Meeting",
                              start: utcDate(2026, 6, 10, 9),
                              end:   utcDate(2026, 6, 10, 11))
        let (vm, spy) = makeVM()
        // After createNote, the spy's listNotes() will return the new note
        let note = try vm.createNote(from: event)
        let allItems = vm.groups.flatMap { $0.items }
        XCTAssertTrue(allItems.contains { item in
            if case .note(let id, _, _, _) = item.kind { return id == note.id }
            return false
        }, "New note must appear in groups after createNote")
    }

    func testCreatedNoteHasCurrentDotState() throws {
        // Event ongoing at fixedNow (10:00): start=09:00 end=11:00
        let event = makeEvent(id: "e1", title: "Ongoing",
                              start: utcDate(2026, 6, 10, 9),
                              end:   utcDate(2026, 6, 10, 11))
        let (vm, _) = makeVM()
        let note = try vm.createNote(from: event)
        let match = vm.groups.flatMap { $0.items }.first {
            if case .note(let id, _, _, _) = $0.kind { return id == note.id }
            return false
        }
        XCTAssertEqual(match?.dotState, .current, "Created note's dot state must be .current when ongoing")
    }

    func testCreatedNoteIsSavedToStore() throws {
        let event = makeEvent(id: "e1", title: "E", start: utcDate(2026, 6, 11, 10))
        let (vm, spy) = makeVM()
        let note = try vm.createNote(from: event)
        XCTAssertTrue(spy.notes.contains { $0.id == note.id }, "Note must be persisted in the store")
    }

    // MARK: - onChange callbacks

    func testOnChangeCalledOnRebuild() {
        var count = 0
        let (vm, _) = makeVM()
        vm.onChange = { count += 1 }
        count = 0  // reset after init
        vm.searchQuery = "x"
        XCTAssertGreaterThan(count, 0)
    }

    func testOnChangeCalledOnMoveDown() {
        let n1 = makeNote(id: "n1", title: "A", date: utcDate(2026, 6, 9, 14))
        let n2 = makeNote(id: "n2", title: "B", date: utcDate(2026, 6, 9, 10))
        let (vm, _) = makeVM(notes: [n1, n2])
        var count = 0
        vm.onChange = { count += 1 }
        vm.moveDown()
        XCTAssertEqual(count, 1)
    }

    // MARK: - Helpers

    private func itemTitle(_ item: SwitcherItem) -> String {
        switch item.kind {
        case .note(_, let title, _, _): return title
        case .event(let e): return e.title
        }
    }
}

// MARK: - Test doubles

private final class SpyStore: NoteStoring, NoteListProviding {
    var notes: [MeetingNote]

    init(notes: [MeetingNote] = []) {
        self.notes = notes
    }

    func listNotes() -> [MeetingNote] { notes }

    func load(id: String) throws -> MeetingNote? { notes.first { $0.id == id } }

    func save(_ note: MeetingNote) throws {
        notes.removeAll { $0.id == note.id }
        notes.append(note)
    }
}

private struct FixedEventsProvider: UpcomingEventsProviding {
    let events: [UpcomingEvent]
    func listEvents() -> [UpcomingEvent] { events }
}

private struct FixedDefaults: NoteDefaultsProviding {
    let transcribeByDefault: Bool
    let defaultLanguage: TranscribeLanguage
    let inPersonByDefault: Bool
}
