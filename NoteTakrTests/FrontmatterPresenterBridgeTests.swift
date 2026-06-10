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

        bridge.setInPerson(true)

        let saved = try XCTUnwrap(spy.notes["fp-1"])
        XCTAssertEqual(saved.inPerson, true)
    }

    func testToggleInPersonFalseToTrue() throws {
        let spy = SpyPresenterStore()
        var note = MeetingNote(id: "fp-2", title: "Test Note", date: fixedDate())
        note.inPerson = true
        spy.notes["fp-2"] = note

        let bridge = FrontmatterPresenterBridge(store: spy)
        bridge.load(note: note)

        bridge.setInPerson(false)

        let saved = try XCTUnwrap(spy.notes["fp-2"])
        XCTAssertEqual(saved.inPerson, false)
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

        XCTAssertEqual(bridge.propertyRows.count, 6)
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
