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
                           participants: [Participant] = [],
                           locationText: String? = nil,
                           meetingLink: String? = nil) -> UpcomingEvent {
        UpcomingEvent(id: id, title: title, start: start, end: end,
                      participants: participants, locationText: locationText, meetingLink: meetingLink)
    }

    private func makeRecording(noteID: String = "rec-1", title: String = "Client escalation",
                               startedAt: Date? = nil,
                               calendarEvent: String? = nil,
                               participants: [Participant] = []) -> ActiveRecordingInfo {
        ActiveRecordingInfo(
            noteID: noteID,
            title: title,
            startedAt: startedAt ?? utcDate(2026, 6, 10, 9, 7),
            calendarEvent: calendarEvent,
            participants: participants
        )
    }

    private func makeVM(notes: [MeetingNote] = [], events: [UpcomingEvent] = [],
                        activeRecording: ActiveRecordingInfo? = nil,
                        defaults: any NoteDefaultsProviding = NoopDefaultsProvider()) -> (SwitcherViewModel, SpyStore) {
        let spy = SpyStore(notes: notes)
        let vm = SwitcherViewModel(
            noteListProvider: spy,
            eventsProvider: FixedEventsProvider(events: events),
            activeRecordingProvider: FixedActiveRecordingProvider(recording: activeRecording),
            now: { self.fixedNow },
            store: spy,
            defaultsProvider: defaults,
            calendar: Self.utcCal
        )
        return (vm, spy)
    }

    // MARK: - Grouping: calendar-first recency labels

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

    func testFutureCalendarOnlyEventAppearsInUpcomingGroup() {
        let event = makeEvent(id: "e1", title: "Kickoff", start: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM(events: [event])
        XCTAssertEqual(vm.groups.first?.label, "Upcoming")
        XCTAssertEqual(vm.groups.first?.items.map { itemTitle($0) }, ["Kickoff"])
    }

    func testFarFutureCalendarOnlyEventAppearsInUpcomingGroup() {
        let event = makeEvent(id: "e1", title: "Review", start: utcDate(2026, 6, 17, 10))
        let (vm, _) = makeVM(events: [event])
        XCTAssertEqual(vm.groups.first?.label, "Upcoming")
        XCTAssertEqual(vm.groups.first?.items.map { itemTitle($0) }, ["Review"])
    }

    func testPastCalendarOnlyEventDoesNotAppearAsCreatableGhost() {
        let event = makeEvent(
            id: "past-event",
            title: "Past calendar event",
            start: utcDate(2026, 6, 10, 8),
            end: utcDate(2026, 6, 10, 9)
        )
        let (vm, _) = makeVM(events: [event])
        XCTAssertTrue(vm.groups.isEmpty, "Past unlinked calendar events must not show Create rows")
    }

    func testPastCalendarOnlyEventWithoutEndDoesNotAppearAsCreatableGhost() {
        let event = makeEvent(
            id: "past-event-no-end",
            title: "Past calendar event with no end",
            start: utcDate(2026, 6, 10, 8)
        )
        let (vm, _) = makeVM(events: [event])
        XCTAssertTrue(vm.groups.isEmpty, "Past unlinked calendar events without an end must not show Create rows")
    }

    func testLongRunningPastStartedCalendarEventDoesNotAppearAsCreatableGhost() {
        let event = makeEvent(
            id: "all-day-ish",
            title: "Long running stale event",
            start: utcDate(2026, 6, 10, 0),
            end: utcDate(2026, 6, 11, 0)
        )
        let (vm, _) = makeVM(events: [event])
        XCTAssertTrue(vm.groups.isEmpty, "All-day or long-running stale events must not show Create rows in Cmd-K")
    }

    func testShortCurrentlyRunningCalendarEventStillAppearsAsCreatableGhost() {
        let event = makeEvent(
            id: "current-short",
            title: "Current meeting",
            start: utcDate(2026, 6, 10, 9),
            end: utcDate(2026, 6, 10, 11)
        )
        let (vm, _) = makeVM(events: [event])
        XCTAssertEqual(vm.groups.first?.label, "Upcoming")
        XCTAssertEqual(vm.groups.first?.items.map { itemTitle($0) }, ["Current meeting"])
    }

    func testFutureNotesRemainInUpcomingGroup() {
        let soon = makeNote(id: "n1", title: "Soon", date: utcDate(2026, 6, 11, 10))
        let later = makeNote(id: "n2", title: "Later", date: utcDate(2026, 6, 17, 9))
        let (vm, _) = makeVM(notes: [later, soon])

        let upcomingGroups = vm.groups.filter { $0.label == "Upcoming" }
        XCTAssertEqual(upcomingGroups.count, 1)
        XCTAssertEqual(upcomingGroups.first?.items.map { itemTitle($0) }, ["Soon", "Later"])
    }

    func testOlderPastNoteAppearsInDatedGroup() {
        // 2 days ago -> concrete date heading.
        let note = makeNote(id: "n1", title: "Old", date: utcDate(2026, 6, 8, 10))
        let (vm, _) = makeVM(notes: [note])
        XCTAssertTrue(vm.groups.contains { $0.label == "8 Jun" }, "Expected dated label, got: \(vm.groups.map { $0.label })")
    }

    func testOlderCurrentYearNoteUsesCompactDateHeading() {
        let note = makeNote(id: "n1", title: "Old", date: utcDate(2026, 5, 1, 10))
        let (vm, _) = makeVM(notes: [note])
        XCTAssertTrue(vm.groups.contains { $0.label == "1 May" }, "Expected compact date label, got: \(vm.groups.map { $0.label })")
    }

    func testPreviousYearNoteIncludesYearInHeading() {
        let note = makeNote(id: "n1", title: "Old", date: utcDate(2025, 5, 1, 10))
        let (vm, _) = makeVM(notes: [note])
        XCTAssertTrue(vm.groups.contains { $0.label == "1 May 2025" }, "Expected year in date label, got: \(vm.groups.map { $0.label })")
    }

    func testMultiplePastDaysBecomeSeparateDatedGroups() {
        let recent = makeNote(id: "n1", title: "Recent", date: utcDate(2026, 6, 8, 14))
        let older = makeNote(id: "n2", title: "Older", date: utcDate(2026, 5, 1, 10))
        let (vm, _) = makeVM(notes: [older, recent])

        XCTAssertEqual(vm.groups.map(\.label), ["8 Jun", "1 May"])
        XCTAssertEqual(vm.groups.flatMap(\.items).map { itemTitle($0) }, ["Recent", "Older"])
    }

    func testFutureGroupsBeforeCurrentAndPastGroups() {
        let pastNote = makeNote(id: "n1", title: "Past", date: utcDate(2026, 6, 9, 10))
        let futureNote = makeNote(id: "n2", title: "Future", date: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM(notes: [pastNote, futureNote])
        let labels = vm.groups.map { $0.label }
        let upcomingIdx = labels.firstIndex(of: "Upcoming")!
        let yesterdayIdx = labels.firstIndex(of: "Yesterday")!
        XCTAssertLessThan(upcomingIdx, yesterdayIdx, "Upcoming must appear before Yesterday")
    }

    func testTodayGroupBetweenFutureAndPast() {
        let todayNote = makeNote(id: "n1", title: "Today", date: utcDate(2026, 6, 10, 9))
        let pastNote = makeNote(id: "n2", title: "Past", date: utcDate(2026, 6, 9, 10))
        let futureNote = makeNote(id: "n3", title: "Future", date: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM(notes: [todayNote, pastNote, futureNote])
        let labels = vm.groups.map { $0.label }
        let upcomingIdx = labels.firstIndex(of: "Upcoming")!
        let todayIdx = labels.firstIndex(of: "Today")!
        let yesterdayIdx = labels.firstIndex(of: "Yesterday")!
        XCTAssertLessThan(upcomingIdx, todayIdx)
        XCTAssertLessThan(todayIdx, yesterdayIdx)
    }

    // MARK: - Ordering within groups

    func testFutureGroupItemsAscending() {
        let n1 = makeNote(id: "n1", title: "First",  date: utcDate(2026, 6, 11, 9))
        let n2 = makeNote(id: "n2", title: "Second", date: utcDate(2026, 6, 11, 14))
        let (vm, _) = makeVM(notes: [n2, n1])  // intentionally reversed
        guard let group = vm.groups.first(where: { $0.label == "Upcoming" }) else {
            return XCTFail("No Upcoming group")
        }
        let titles = group.items.map { itemTitle($0) }
        XCTAssertEqual(titles, ["First", "Second"])
    }

    func testLongUpcomingListSelectsVisibleFutureWindowOnReset() {
        let events = [
            makeEvent(id: "e1", title: "First", start: utcDate(2026, 6, 10, 11)),
            makeEvent(id: "e2", title: "Second", start: utcDate(2026, 6, 10, 12)),
            makeEvent(id: "e3", title: "Third", start: utcDate(2026, 6, 10, 13)),
            makeEvent(id: "e4", title: "Fourth", start: utcDate(2026, 6, 10, 14)),
        ]
        let (vm, _) = makeVM(events: events)
        XCTAssertEqual(vm.selectedIndex, 2)
        XCTAssertEqual(vm.selectedItem.map { itemTitle($0) }, Optional("Third"))
    }

    func testCurrentCalendarEventsSortBeforeUpcomingEvents() {
        let future = makeEvent(id: "future", title: "Future", start: utcDate(2026, 6, 10, 11))
        let current = makeEvent(id: "current", title: "Current",
                                start: utcDate(2026, 6, 10, 9),
                                end: utcDate(2026, 6, 10, 11))
        let (vm, _) = makeVM(events: [future, current])
        XCTAssertEqual(vm.groups.first?.label, "Upcoming")
        XCTAssertEqual(vm.groups.first?.items.map { itemTitle($0) }, ["Current", "Future"])
    }

    func testPastGroupItemsDescending() {
        let n1 = makeNote(id: "n1", title: "Morning",   date: utcDate(2026, 6, 9, 9))
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
        XCTAssertEqual(allItems.count, 1)
        if case .note(let id, _, _, _) = allItems[0].kind {
            XCTAssertEqual(id, "n1")
        } else {
            XCTFail("Expected a note item, got event")
        }
    }

    func testUnlinkedEventAppearsAsSeparateGhost() {
        let note = makeNote(id: "n1", title: "Standup", date: utcDate(2026, 6, 10, 9), calendarEvent: "cal-1")
        let otherEvent = makeEvent(id: "cal-2", title: "Lunch",
                                   start: utcDate(2026, 6, 10, 9),
                                   end: utcDate(2026, 6, 10, 11))
        let (vm, _) = makeVM(notes: [note], events: [otherEvent])
        let allItems = vm.groups.flatMap { $0.items }
        XCTAssertEqual(allItems.count, 2)
    }

    func testNoteWithoutLinkedEventDoesNotDedupOtherEvents() {
        let note = makeNote(id: "n1", title: "Note", date: utcDate(2026, 6, 10, 9))
        let event = makeEvent(id: "cal-1", title: "Event", start: utcDate(2026, 6, 10, 11))
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

    func testSearchMatchesCurrentEventTitle() {
        let e = makeEvent(id: "e1", title: "Quarterly Review",
                          start: utcDate(2026, 6, 10, 9),
                          end: utcDate(2026, 6, 10, 11))
        let (vm, _) = makeVM(events: [e])
        vm.searchQuery = "quarterly"
        XCTAssertEqual(vm.groups.flatMap { $0.items }.count, 1)
    }

    func testSearchSurfacesFutureCalendarOnlyEvent() {
        let e = makeEvent(id: "e1", title: "Quarterly Review", start: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM(events: [e])
        vm.searchQuery = "quarterly"
        XCTAssertEqual(vm.groups.flatMap { $0.items }.map { itemTitle($0) }, ["Quarterly Review"])
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

    // MARK: - Active recording marker

    func testActiveRecordingNoteIsMarked() {
        let active = makeNote(id: "n1", title: "Recording Anchor", date: utcDate(2026, 6, 10, 9))
        let inactive = makeNote(id: "n2", title: "Old Note Parking Lot", date: utcDate(2026, 6, 10, 8))
        let (vm, _) = makeVM(notes: [active, inactive])

        vm.activeRecordingNoteID = "n1"

        let items = vm.groups.flatMap { $0.items }
        XCTAssertTrue(items.first { noteID($0) == "n1" }?.isRecording == true)
        XCTAssertTrue(items.first { noteID($0) == "n2" }?.isRecording == false)
    }

    func testActiveRecordingMarkerSurvivesSearch() {
        let active = makeNote(id: "n1", title: "Recording Anchor", date: utcDate(2026, 6, 10, 9))
        let inactive = makeNote(id: "n2", title: "Old Note Parking Lot", date: utcDate(2026, 6, 10, 8))
        let (vm, _) = makeVM(notes: [active, inactive])

        vm.activeRecordingNoteID = "n1"
        vm.searchQuery = "anchor"

        let items = vm.groups.flatMap { $0.items }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(noteID(items[0]), "n1")
        XCTAssertTrue(items[0].isRecording)
    }

    // MARK: - Command surfacing

    func testSearchSettingsSurfacesOpenSettingsCommand() {
        let (vm, _) = makeVM()
        vm.searchQuery = "settings"
        let allItems = vm.groups.flatMap { $0.items }
        let cmdItems = allItems.filter {
            if case .command(let c) = $0.kind { return c.id == .openSettings }
            return false
        }
        XCTAssertEqual(cmdItems.count, 1, "Typing 'settings' must surface the Open Settings command")
    }

    func testSearchPreferencesSurfacesOpenSettingsCommand() {
        let (vm, _) = makeVM()
        vm.searchQuery = "pref"
        let allItems = vm.groups.flatMap { $0.items }
        let cmdItems = allItems.filter {
            if case .command(let c) = $0.kind { return c.id == .openSettings }
            return false
        }
        XCTAssertEqual(cmdItems.count, 1, "Typing 'pref' must surface Open Settings (prefix of 'preferences')")
    }

    func testSearchNewSurfacesNewNoteCommand() {
        let (vm, _) = makeVM()
        vm.searchQuery = "new"
        let allItems = vm.groups.flatMap { $0.items }
        let cmdItems = allItems.filter {
            if case .command(let c) = $0.kind { return c.id == .newNote }
            return false
        }
        XCTAssertEqual(cmdItems.count, 1, "Typing 'new' must surface the New note command")
    }

    func testCommandsGroupLabelIsCommands() {
        let (vm, _) = makeVM()
        vm.searchQuery = "settings"
        XCTAssertTrue(vm.groups.contains { $0.label == "Commands" }, "Command rows must be in a 'Commands' group")
    }

    func testCommandsGroupLeadsOtherGroups() {
        let note = makeNote(id: "n1", title: "Settings meeting", date: utcDate(2026, 6, 9, 10))
        let (vm, _) = makeVM(notes: [note])
        vm.searchQuery = "settings"
        guard let firstGroup = vm.groups.first else { return XCTFail("No groups") }
        XCTAssertEqual(firstGroup.label, "Commands", "Commands group must appear before meeting groups")
    }

    func testEmptyQueryDoesNotSurfaceCommands() {
        let (vm, _) = makeVM()
        vm.searchQuery = ""
        let cmdItems = vm.groups.flatMap { $0.items }.filter {
            if case .command = $0.kind { return true }
            return false
        }
        XCTAssertTrue(cmdItems.isEmpty, "Commands must NOT appear when query is empty")
    }

    func testUnrelatedQueryDoesNotSurfaceCommands() {
        let (vm, _) = makeVM()
        vm.searchQuery = "standup"
        let cmdItems = vm.groups.flatMap { $0.items }.filter {
            if case .command = $0.kind { return true }
            return false
        }
        XCTAssertTrue(cmdItems.isEmpty, "Unrelated query must not surface command rows")
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
        let event = makeEvent(id: "e1", title: "Event",
                              start: utcDate(2026, 6, 10, 9),
                              end: utcDate(2026, 6, 10, 11))
        let (vm, _) = makeVM(events: [event])
        XCTAssertNil(vm.open(), "open() must return nil when a ghost event is selected")
    }

    func testOpenReturnsNilWhenCommandSelected() {
        let (vm, _) = makeVM()
        vm.searchQuery = "settings"
        XCTAssertNil(vm.open(), "open() must return nil when a command row is selected")
    }

    func testActiveRecordingAppearsAtTopOfTodayAndOpensByNoteID() {
        let recording = makeRecording(noteID: "live-123", title: "Live Client Call")
        let note = makeNote(id: "n1", title: "Earlier", date: utcDate(2026, 6, 10, 8))
        let (vm, _) = makeVM(notes: [note], activeRecording: recording)

        XCTAssertEqual(vm.groups.first?.label, "Today")
        XCTAssertEqual(vm.groups.first?.items.map { itemTitle($0) }, ["Live Client Call", "Earlier"])
        XCTAssertEqual(vm.open(), "live-123")
    }

    func testActiveRecordingDoesNotDuplicateItsNoteRow() {
        let recording = makeRecording(noteID: "live-123", title: "Live Client Call")
        let note = makeNote(id: "live-123", title: "Live Client Call", date: utcDate(2026, 6, 10, 9))
        let (vm, _) = makeVM(notes: [note], activeRecording: recording)
        XCTAssertEqual(vm.groups.flatMap(\.items).map { itemTitle($0) }, ["Live Client Call"])
    }

    func testActiveRecordingDedupesLinkedCalendarEvent() {
        let recording = makeRecording(noteID: "live-123", title: "Live Client Call", calendarEvent: "cal-1")
        let event = makeEvent(id: "cal-1", title: "Live Client Call",
                              start: utcDate(2026, 6, 10, 9),
                              end: utcDate(2026, 6, 10, 11))
        let (vm, _) = makeVM(events: [event], activeRecording: recording)
        XCTAssertEqual(vm.groups.flatMap(\.items).map { itemTitle($0) }, ["Live Client Call"])
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

    // MARK: - Deterministic icon mapping

    func testIconKindForGhostEventIsGhostEvent() {
        let event = makeEvent(id: "e1", title: "Lunch", start: utcDate(2026, 6, 11, 12))
        let item = SwitcherItem(kind: .event(event), dotState: .upcoming)
        XCTAssertEqual(SwitcherViewModel.iconKind(for: item), .ghostEvent)
    }

    func testIconKindForActiveRecordingIsRecording() {
        let recording = makeRecording()
        let item = SwitcherItem(kind: .activeRecording(recording), dotState: .current)
        XCTAssertEqual(SwitcherViewModel.iconKind(for: item), .recording)
    }

    func testIconKindForEventWithMeetingLinkIsVideoCall() {
        let event = makeEvent(id: "e1", title: "Zoom call", start: utcDate(2026, 6, 11, 12),
                              meetingLink: "https://zoom.us/j/123")
        let item = SwitcherItem(kind: .event(event), dotState: .upcoming)
        XCTAssertEqual(SwitcherViewModel.iconKind(for: item), .videoCall)
    }

    func testIconKindForNoteWithNoParticipantsIsSoloNote() {
        let note = makeNote(id: "n1", title: "Scratch", date: utcDate(2026, 6, 9, 10))
        let item = SwitcherItem(kind: .note(id: "n1", title: "Scratch",
                                            date: utcDate(2026, 6, 9, 10), participants: []),
                                dotState: .past)
        XCTAssertEqual(SwitcherViewModel.iconKind(for: item), .soloNote)
    }

    func testIconKindForNoteWithOneParticipantIsOneOnOne() {
        let item = SwitcherItem(kind: .note(id: "n1", title: "1:1",
                                            date: utcDate(2026, 6, 9, 10),
                                            participants: [Participant(name: "Alice")]),
                                dotState: .past)
        XCTAssertEqual(SwitcherViewModel.iconKind(for: item), .oneOnOne)
    }

    func testIconKindForNoteWithTwoParticipantsIsGroupMeeting() {
        let item = SwitcherItem(kind: .note(id: "n1", title: "Standup",
                                            date: utcDate(2026, 6, 9, 10),
                                            participants: [Participant(name: "Alice"), Participant(name: "Bob")]),
                                dotState: .past)
        XCTAssertEqual(SwitcherViewModel.iconKind(for: item), .groupMeeting)
    }

    func testIconKindForOpenSettingsCommand() {
        let cmd = SwitcherCommand(id: .openSettings, title: "Open Settings\u{2026}",
                                  subtitle: "", shortcut: "\u{2318},")
        let item = SwitcherItem(kind: .command(cmd), dotState: .past)
        XCTAssertEqual(SwitcherViewModel.iconKind(for: item), .openSettings)
    }

    func testIconKindForNewNoteCommand() {
        let cmd = SwitcherCommand(id: .newNote, title: "New note",
                                  subtitle: "", shortcut: "\u{2318}N")
        let item = SwitcherItem(kind: .command(cmd), dotState: .past)
        XCTAssertEqual(SwitcherViewModel.iconKind(for: item), .newNote)
    }

    // MARK: - createNote(from:)

    func testCreateNoteFromEventPreFillsFields() throws {
        let event = makeEvent(
            id: "cal-42",
            title: "Design Sprint",
            start: utcDate(2026, 6, 11, 9),
            end: utcDate(2026, 6, 11, 17),
            participants: [Participant(name: "Alice", email: "alice@example.com")],
            locationText: "Room 4",
            meetingLink: "https://zoom.us/j/123"
        )
        let (vm, _) = makeVM()
        let note = try vm.createNote(from: event)
        XCTAssertEqual(note.title, "Design Sprint")
        XCTAssertEqual(note.date, utcDate(2026, 6, 11, 9))
        XCTAssertEqual(note.end, utcDate(2026, 6, 11, 17))
        XCTAssertEqual(note.calendarEvent, "cal-42")
        XCTAssertEqual(note.participants, [Participant(name: "Alice", email: "alice@example.com")])
        XCTAssertEqual(note.locationText, "Room 4")
        XCTAssertEqual(note.meetingLink, "https://zoom.us/j/123")
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

    func testCreateNoteLocalOnlyTrueWhenDefaultIsTrue() throws {
        var defaults = FixedDefaults(transcribeByDefault: true, defaultLanguage: .auto, inPersonByDefault: false)
        defaults.localOnlyByDefault = true
        let event = makeEvent(id: "e1", title: "E", start: utcDate(2026, 6, 11, 10))
        let (vm, _) = makeVM(defaults: defaults)
        let note = try vm.createNote(from: event)
        XCTAssertEqual(note.localOnly, true)
    }

    func testCreatedNoteAppearsInGroups() throws {
        // Event happening now: start < fixedNow < end
        let event = makeEvent(id: "e1", title: "Live Meeting",
                              start: utcDate(2026, 6, 10, 9),
                              end:   utcDate(2026, 6, 10, 11))
        let (vm, _) = makeVM()
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
        case .activeRecording(let recording): return recording.title
        case .command(let c): return c.title
        }
    }

    private func noteID(_ item: SwitcherItem) -> String? {
        if case .note(let id, _, _, _) = item.kind { return id }
        return nil
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

private struct FixedActiveRecordingProvider: ActiveRecordingProviding {
    let recording: ActiveRecordingInfo?
    func currentRecording() -> ActiveRecordingInfo? { recording }
}

private struct FixedDefaults: NoteDefaultsProviding {
    let transcribeByDefault: Bool
    let defaultLanguage: TranscribeLanguage
    let inPersonByDefault: Bool
    var localOnlyByDefault: Bool = false
}
