import XCTest
import NoteTakrKit
@testable import NoteTakr

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

    func testLegacyMainWindowViewCompiles() {
        // MainWindowView must keep building until Task 17 cutover.
        _ = MainWindowView.self
        XCTAssertTrue(true)
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotePanelTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private final class SpyNoteStore: NoteStoring {
    var notes: [String: MeetingNote] = [:]

    func load(id: String) throws -> MeetingNote? { notes[id] }
    func save(_ note: MeetingNote) throws { notes[note.id] = note }
}
