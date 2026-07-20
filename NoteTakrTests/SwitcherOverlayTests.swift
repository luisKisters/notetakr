import XCTest
import SwiftUI
import AppKit
import NoteTakrKit
@testable import NoteTakr

@MainActor
final class SwitcherOverlayTests: XCTestCase {

    // MARK: - 1. ⌘K toggles overlay state

    func testToggleSwitcherShowsOverlay() {
        let bridge = makeBridge()
        XCTAssertFalse(bridge.isVisible)
        bridge.toggle()
        XCTAssertTrue(bridge.isVisible)
    }

    func testToggleAgainHidesOverlay() {
        let bridge = makeBridge()
        bridge.toggle()
        XCTAssertTrue(bridge.isVisible)
        bridge.toggle()
        XCTAssertFalse(bridge.isVisible)
    }

    // MARK: - 2. esc restores editor focus

    func testDismissHidesOverlayAndCallsFocusCallback() {
        let bridge = makeBridge()
        bridge.show()

        var focusCallCount = 0
        bridge.onEditorFocusRequest = { focusCallCount += 1 }

        bridge.dismiss()

        XCTAssertFalse(bridge.isVisible)
        XCTAssertEqual(focusCallCount, 1)
    }

    func testDismissClearsSearchQuery() {
        let bridge = makeBridge()
        bridge.show()
        bridge.searchQuery = "weekly sync"
        bridge.dismiss()
        XCTAssertEqual(bridge.searchQuery, "")
    }

    // MARK: - 3. Selecting a ghost event calls createNote and switches to the new note

    func testSelectingGhostEventCreatesNoteAndCallsOnOpenNote() throws {
        let spy = SpySwitcherStore()
        let event = UpcomingEvent(
            id: "event-abc",
            title: "Design Review",
            start: Date().addingTimeInterval(3600),
            participants: []
        )
        let eventsProvider = SpyEventsProvider(events: [event])
        let noteProvider = SpyNoteListProvider(notes: [])

        let viewModel = SwitcherViewModel(
            noteListProvider: noteProvider,
            eventsProvider: eventsProvider,
            now: { Date() },
            store: spy
        )
        let bridge = SwitcherBridge(viewModel: viewModel)
        bridge.show()

        var openedNoteID: String?
        bridge.onOpenNote = { openedNoteID = $0 }

        // Select the ghost event row and open it
        // The event should appear in the first group since it's upcoming
        bridge.openOrCreate(event: event)

        // The store should have a saved note
        XCTAssertFalse(spy.savedNotes.isEmpty)
        let saved = try XCTUnwrap(spy.savedNotes.first)
        XCTAssertEqual(saved.title, "Design Review")
        XCTAssertEqual(saved.calendarEvent, "event-abc")

        // onOpenNote was called with the new note's ID
        XCTAssertEqual(openedNoteID, saved.id)

        // Overlay dismisses
        XCTAssertFalse(bridge.isVisible)
    }

    func testSelectingNoteRowOpensItDirectly() {
        let spy = SpySwitcherStore()
        let note = MeetingNote(id: "note-xyz", title: "Standup", date: Date())
        let noteProvider = SpyNoteListProvider(notes: [note])

        let viewModel = SwitcherViewModel(
            noteListProvider: noteProvider,
            eventsProvider: SpyEventsProvider(events: []),
            now: { Date() },
            store: spy
        )
        let bridge = SwitcherBridge(viewModel: viewModel)
        bridge.show()

        var openedID: String?
        bridge.onOpenNote = { openedID = $0 }

        // Move to the first item (should be the note) and open
        bridge.openOrCreateSelected()

        XCTAssertEqual(openedID, "note-xyz")
        XCTAssertFalse(bridge.isVisible)
    }

    func testSelectingActiveRecordingOpensItsNoteWithoutCreating() {
        let spy = SpySwitcherStore()
        let recording = ActiveRecordingInfo(
            noteID: "recording-note",
            title: "Recording now",
            startedAt: Date()
        )

        let viewModel = SwitcherViewModel(
            noteListProvider: SpyNoteListProvider(notes: []),
            eventsProvider: SpyEventsProvider(events: []),
            activeRecordingProvider: FixedActiveRecordingProvider(recording: recording),
            now: { Date() },
            store: spy
        )
        let bridge = SwitcherBridge(viewModel: viewModel)
        bridge.show()

        var openedID: String?
        bridge.onOpenNote = { openedID = $0 }

        bridge.openOrCreateSelected()

        XCTAssertEqual(openedID, "recording-note")
        XCTAssertTrue(spy.savedNotes.isEmpty)
        XCTAssertFalse(bridge.isVisible)
    }

    // MARK: - 4. Navigation

    func testMoveDownAndUpWraps() {
        let notes = (0..<3).map { i in
            MeetingNote(id: "n\(i)", title: "Note \(i)", date: Date().addingTimeInterval(Double(-i * 3600)))
        }
        let viewModel = SwitcherViewModel(
            noteListProvider: SpyNoteListProvider(notes: notes),
            eventsProvider: SpyEventsProvider(events: []),
            now: { Date() },
            store: SpySwitcherStore()
        )
        let bridge = SwitcherBridge(viewModel: viewModel)
        bridge.show()

        let initialIndex = bridge.viewModel.selectedIndex
        bridge.moveDown()
        XCTAssertNotEqual(bridge.viewModel.selectedIndex, initialIndex)

        bridge.moveUp()
        XCTAssertEqual(bridge.viewModel.selectedIndex, initialIndex)
    }

    func testHoverSelectionUpdatesActiveRowWithoutDismissing() {
        let notes = [
            MeetingNote(id: "n1", title: "One", date: Date()),
            MeetingNote(id: "n2", title: "Two", date: Date().addingTimeInterval(-3600)),
        ]
        let bridge = makeBridge(notes: notes)
        bridge.show()

        bridge.selectFromHover(index: 1)

        XCTAssertEqual(bridge.selectedIndex, 1)
        XCTAssertEqual(bridge.viewModel.selectedIndex, 1)
        XCTAssertTrue(bridge.isVisible)
    }

    // MARK: - 5. CalendarEventsProvider maps CalendarEvent to UpcomingEvent

    func testCalendarEventsProviderMapsCorrectly() {
        let provider = CalendarEventsProvider()
        XCTAssertTrue(provider.listEvents().isEmpty)

        provider.events = [
            UpcomingEvent(id: "ev1", title: "Standup", start: Date(), participants: [
                Participant(name: "Alice", email: "alice@example.com")
            ])
        ]
        let events = provider.listEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].title, "Standup")
        XCTAssertEqual(events[0].participants[0].name, "Alice")
    }

    // MARK: - 6. Theme adaptation

    func testSwitcherOverlayDarkAppearanceUsesSolidEditorDarkTokens() {
        XCTAssertEqual(
            SwitcherOverlayPalette.colors(for: .dark),
            Theme.dark
        )
        XCTAssertEqual(SwitcherOverlayPalette.colors(for: .dark).background.a, 1.0)
    }

    func testSwitcherOverlayLightAppearanceUsesSolidEditorLightTokens() {
        XCTAssertEqual(
            SwitcherOverlayPalette.colors(for: .light),
            Theme.light
        )
        XCTAssertEqual(SwitcherOverlayPalette.colors(for: .light).background.a, 1.0)
    }

    func testSwitcherOverlayGlassAppearanceUsesTheSameGlassTokensAsEditor() {
        let palette = SwitcherOverlayPalette.colors(for: .glass)

        XCTAssertEqual(palette, Theme.glass)
        XCTAssertEqual(palette.background.a, Theme.glass.background.a)
    }

    func testExplicitAppearancesDriveMatchingNativeControlSchemes() {
        XCTAssertEqual(Appearance.light.colorScheme, .light)
        XCTAssertEqual(Appearance.light.nsAppearance.name, .aqua)

        for appearance: Appearance in [.glass, .dark] {
            XCTAssertEqual(appearance.colorScheme, .dark)
            XCTAssertEqual(appearance.nsAppearance.name, .darkAqua)
        }
    }

    // MARK: - Helpers

    private func makeBridge(notes: [MeetingNote] = [], events: [UpcomingEvent] = []) -> SwitcherBridge {
        let vm = SwitcherViewModel(
            noteListProvider: SpyNoteListProvider(notes: notes),
            eventsProvider: SpyEventsProvider(events: events),
            now: { Date() },
            store: SpySwitcherStore()
        )
        return SwitcherBridge(viewModel: vm)
    }
}

// MARK: - Test doubles

private final class SpySwitcherStore: NoteStoring, @unchecked Sendable {
    var notes: [String: MeetingNote] = [:]
    var savedNotes: [MeetingNote] = []

    func load(id: String) throws -> MeetingNote? { notes[id] }
    func save(_ note: MeetingNote) throws {
        notes[note.id] = note
        savedNotes.append(note)
    }
}

private struct SpyNoteListProvider: NoteListProviding {
    var notes: [MeetingNote]
    func listNotes() -> [MeetingNote] { notes }
}

private struct SpyEventsProvider: UpcomingEventsProviding {
    var events: [UpcomingEvent]
    func listEvents() -> [UpcomingEvent] { events }
}

private struct FixedActiveRecordingProvider: ActiveRecordingProviding {
    var recording: ActiveRecordingInfo?
    func currentRecording() -> ActiveRecordingInfo? { recording }
}
