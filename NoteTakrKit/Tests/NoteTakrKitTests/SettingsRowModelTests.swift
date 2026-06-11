import XCTest
@testable import NoteTakrKit

final class SettingsRowModelTests: XCTestCase {

    // MARK: - Hover state

    func testNoHighlightByDefault() {
        let model = SettingsRowModel()
        XCTAssertFalse(model.showsHoverHighlight)
    }

    func testHoverEnablesHighlight() {
        var model = SettingsRowModel()
        model.setHover(true)
        XCTAssertTrue(model.showsHoverHighlight)
    }

    func testHoverExitDisablesHighlight() {
        var model = SettingsRowModel()
        model.setHover(true)
        model.setHover(false)
        XCTAssertFalse(model.showsHoverHighlight)
    }

    // MARK: - Hover ≠ selected

    func testHighlightRequiresHover() {
        // A row that is active/selected (isOn = true) but not hovered
        // must NOT show the hover highlight.
        let row = SettingsToggleRowModel(isOn: true)
        XCTAssertFalse(row.hoverState.showsHoverHighlight,
            "Active/selected state alone must not produce a hover highlight")
    }

    func testHoverAndActiveAreIndependent() {
        var row = SettingsToggleRowModel(isOn: true)
        row.hoverState.setHover(true)
        XCTAssertTrue(row.isOn)
        XCTAssertTrue(row.hoverState.showsHoverHighlight)
        // Now un-hover: active state remains, highlight goes away
        row.hoverState.setHover(false)
        XCTAssertTrue(row.isOn, "Removing hover must not change active state")
        XCTAssertFalse(row.hoverState.showsHoverHighlight, "Removing hover must remove highlight")
    }

    // MARK: - Whole-row activation

    func testActivateTogglesValue() {
        var row = SettingsToggleRowModel(isOn: false)
        row.activate()
        XCTAssertTrue(row.isOn, "activate() must toggle the value (simulates tap from any row region)")
    }

    func testActivateTwiceRestoresValue() {
        var row = SettingsToggleRowModel(isOn: true)
        row.activate()
        row.activate()
        XCTAssertTrue(row.isOn)
    }

    func testHoverDoesNotActivate() {
        var row = SettingsToggleRowModel(isOn: false)
        row.hoverState.setHover(true)
        XCTAssertFalse(row.isOn, "Hovering must not activate the toggle")
    }

    func testActivationPreservesHoverState() {
        var row = SettingsToggleRowModel(isOn: false)
        row.hoverState.setHover(true)
        row.activate()
        XCTAssertTrue(row.isOn)
        XCTAssertTrue(row.hoverState.showsHoverHighlight,
            "Activating must not clear the hover highlight")
    }
}
