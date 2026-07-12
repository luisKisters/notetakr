import AppKit
import XCTest
import NoteTakrKit
@testable import NoteTakr

@MainActor
final class NotePanelTests: XCTestCase {

    func testPanelControllerInitDoesNotCrash() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let controller = NotePanelController(notesRoot: dir)
        XCTAssertNotNil(controller.panel)
    }

    func testPanelIsKeyable() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let controller = NotePanelController(notesRoot: dir)
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(panel.canBecomeKey)
    }

    func testBridgeForwardsEditsToViewModel() throws {
        let spy = SpyNoteStore()
        let note = MeetingNote(id: "abc-1234", title: "Test", date: Date())
        spy.notes["abc-1234"] = note
        let bridge = NoteEditorBridge(store: spy)
        try bridge.viewModel.load(noteID: "abc-1234")

        var didChange = false
        bridge.viewModel.onChange = { didChange = true }

        bridge.setTitle("Updated Title")
        XCTAssertTrue(didChange)
        XCTAssertEqual(bridge.viewModel.title, "Updated Title")

        bridge.setBody("Body text")
        XCTAssertEqual(bridge.viewModel.body, "Body text")
    }

    func testCommandNKeyEquivalentCreatesNoteWhenSwitcherClosed() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let controller = NotePanelController(notesRoot: dir)
        let panel = try XCTUnwrap(controller.panel)

        let handled = panel.performKeyEquivalent(with: commandKeyEvent(
            characters: "n",
            keyCode: 45,
            windowNumber: panel.windowNumber
        ))

        XCTAssertTrue(handled)
        let noteID = try XCTUnwrap(controller.bridge.viewModel.noteID)
        XCTAssertEqual(controller.frontmatterBridge.noteID, noteID)
        XCTAssertNotNil(try NoteStore(root: dir).load(id: noteID))
    }

    func testCommandBackspaceKeyEquivalentDeletesLoadedNoteAndLoadsNext() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NoteStore(root: dir)
        let survivor = try store.create(title: "Keep", date: Date(timeIntervalSince1970: 200))
        let target = try store.create(title: "Delete", date: Date(timeIntervalSince1970: 100))
        let controller = NotePanelController(notesRoot: dir)
        let panel = try XCTUnwrap(controller.panel)
        controller.loadNote(id: target.id)

        let handled = panel.performKeyEquivalent(with: commandKeyEvent(
            characters: "\u{7F}",
            keyCode: 51,
            windowNumber: panel.windowNumber
        ))

        XCTAssertTrue(handled)
        XCTAssertNil(try store.load(id: target.id))
        XCTAssertEqual(controller.frontmatterBridge.noteID, survivor.id)
    }

    func testCommandBackspaceKeyDownDeletesLoadedNote() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NoteStore(root: dir)
        let target = try store.create(title: "Delete", date: Date(timeIntervalSince1970: 100))
        let controller = NotePanelController(notesRoot: dir)
        let panel = try XCTUnwrap(controller.panel)
        controller.loadNote(id: target.id)

        panel.keyDown(with: commandKeyEvent(
            characters: "\u{7F}",
            keyCode: 51,
            windowNumber: panel.windowNumber
        ))

        XCTAssertNil(try store.load(id: target.id))
        let replacementID = try XCTUnwrap(controller.bridge.viewModel.noteID)
        XCTAssertNotEqual(replacementID, target.id)
    }

    func testDeleteCurrentNoteCreatesBlankWhenDeletingLastNote() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NoteStore(root: dir)
        let target = try store.create(title: "Only Note", date: Date(timeIntervalSince1970: 100))
        let controller = NotePanelController(notesRoot: dir)
        controller.loadNote(id: target.id)

        XCTAssertTrue(controller.deleteCurrentNote())

        XCTAssertNil(try store.load(id: target.id))
        let replacementID = try XCTUnwrap(controller.bridge.viewModel.noteID)
        XCTAssertNotEqual(replacementID, target.id)
        XCTAssertNotNil(try store.load(id: replacementID))
    }

    func testExternalRecordingStartUpdatesRecordPillState() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NoteStore(root: dir)
        let note = try store.create(title: "External Recording", date: Date())
        let controller = NotePanelController(notesRoot: dir)

        controller.recordingStarted(sessionID: note.id)

        XCTAssertEqual(controller.recordPillMachine.state, .recording(elapsed: 0))
        XCTAssertEqual(controller.frontmatterBridge.noteID, note.id)
        XCTAssertNotNil(controller.frontmatterBridge.presenter?.recordingStartedAt)
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotePanelTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func commandKeyEvent(characters: String, keyCode: UInt16, windowNumber: Int) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}

private final class SpyNoteStore: NoteStoring, @unchecked Sendable {
    var notes: [String: MeetingNote] = [:]

    func load(id: String) throws -> MeetingNote? { notes[id] }
    func save(_ note: MeetingNote) throws { notes[note.id] = note }
}
