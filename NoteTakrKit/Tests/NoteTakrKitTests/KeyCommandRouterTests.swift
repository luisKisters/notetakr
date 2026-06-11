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

    // MARK: - Esc → .dismissOverlay when inline edit is active

    func testEscape_inlineEditActive_returnsDismiss() {
        XCTAssertEqual(KeyCommandRouter.intent(for: .escape, context: .inlineEditActive), .dismissOverlay)
    }

    // MARK: - ⌘K → .toggleSwitcher

    func testCmdK_returnsToggleSwitcher() {
        XCTAssertEqual(KeyCommandRouter.intent(for: .cmdK, context: .editorFocused), .toggleSwitcher)
    }

    // MARK: - activeContext precedence (settings → switcher → inlineEdit → editor)

    func testActiveContext_settingsBeatsAll() {
        XCTAssertEqual(
            KeyCommandRouter.activeContext(settingsVisible: true, switcherVisible: true, inlineEditActive: true),
            .settingsVisible
        )
    }

    func testActiveContext_switcherBeatsInlineAndEditor() {
        XCTAssertEqual(
            KeyCommandRouter.activeContext(settingsVisible: false, switcherVisible: true, inlineEditActive: true),
            .switcherVisible
        )
    }

    func testActiveContext_inlineEditBeatsEditor() {
        XCTAssertEqual(
            KeyCommandRouter.activeContext(settingsVisible: false, switcherVisible: false, inlineEditActive: true),
            .inlineEditActive
        )
    }

    func testActiveContext_nothingOpen_returnsEditorFocused() {
        XCTAssertEqual(
            KeyCommandRouter.activeContext(settingsVisible: false, switcherVisible: false, inlineEditActive: false),
            .editorFocused
        )
    }

    func testActiveContext_defaultInlineEditFalse() {
        XCTAssertEqual(
            KeyCommandRouter.activeContext(settingsVisible: false, switcherVisible: false),
            .editorFocused
        )
    }

    func testEscapePrecedence_settingsVisible_dismissesOverlay() {
        let ctx = KeyCommandRouter.activeContext(settingsVisible: true, switcherVisible: false)
        XCTAssertEqual(KeyCommandRouter.intent(for: .escape, context: ctx), .dismissOverlay)
    }

    func testEscapePrecedence_switcherVisible_dismissesOverlay() {
        let ctx = KeyCommandRouter.activeContext(settingsVisible: false, switcherVisible: true)
        XCTAssertEqual(KeyCommandRouter.intent(for: .escape, context: ctx), .dismissOverlay)
    }

    func testEscapePrecedence_editorFocused_returnsNil() {
        let ctx = KeyCommandRouter.activeContext(settingsVisible: false, switcherVisible: false)
        XCTAssertNil(KeyCommandRouter.intent(for: .escape, context: ctx))
    }
}
