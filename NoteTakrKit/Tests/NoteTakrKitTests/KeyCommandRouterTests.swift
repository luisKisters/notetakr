import XCTest
@testable import NoteTakrKit

final class KeyCommandRouterTests: XCTestCase {

    // MARK: - ⌘N → .newNote (from any context)

    func testCmdN_editorFocused_returnsNewNote() {
        XCTAssertEqual(KeyCommandRouter.intent(for: .cmdN, context: .editorFocused), .newNote)
    }

    func testCmdN_switcherVisible_returnsNewNote() {
        XCTAssertEqual(KeyCommandRouter.intent(for: .cmdN, context: .switcherVisible), .newNote)
    }

    func testCmdN_settingsVisible_returnsNewNote() {
        XCTAssertEqual(KeyCommandRouter.intent(for: .cmdN, context: .settingsVisible), .newNote)
    }

    // MARK: - ⌘, → .openSettings (from any context)

    func testCmdComma_editorFocused_returnsOpenSettings() {
        XCTAssertEqual(KeyCommandRouter.intent(for: .cmdComma, context: .editorFocused), .openSettings)
    }

    func testCmdComma_switcherVisible_returnsOpenSettings() {
        XCTAssertEqual(KeyCommandRouter.intent(for: .cmdComma, context: .switcherVisible), .openSettings)
    }

    func testCmdComma_settingsVisible_returnsOpenSettings() {
        XCTAssertEqual(KeyCommandRouter.intent(for: .cmdComma, context: .settingsVisible), .openSettings)
    }

    // MARK: - Esc → .dismissOverlay only when an overlay is open

    func testEscape_switcherVisible_returnsDismiss() {
        XCTAssertEqual(KeyCommandRouter.intent(for: .escape, context: .switcherVisible), .dismissOverlay)
    }

    func testEscape_settingsVisible_returnsDismiss() {
        XCTAssertEqual(KeyCommandRouter.intent(for: .escape, context: .settingsVisible), .dismissOverlay)
    }

    func testEscape_editorFocused_returnsNil() {
        XCTAssertNil(KeyCommandRouter.intent(for: .escape, context: .editorFocused))
    }

    // MARK: - ⌘K → .toggleSwitcher

    func testCmdK_returnsToggleSwitcher() {
        XCTAssertEqual(KeyCommandRouter.intent(for: .cmdK, context: .editorFocused), .toggleSwitcher)
    }
}
