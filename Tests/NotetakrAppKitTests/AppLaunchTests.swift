#if os(macOS)
import XCTest
import SwiftUI
@testable import NotetakrAppKit

/// macOS-only tests confirming the app target's UI graph constructs and the
/// app model behaves. On Linux this file compiles to nothing.
@MainActor
final class AppLaunchTests: XCTestCase {
    func testSceneConstructs() {
        // Exercises the menu-bar scene initializer — verifies the app target
        // launches its SwiftUI graph without trapping.
        _ = NotetakrScene()
    }

    func testMenuBarViewConstructs() {
        let model = AppModel()
        _ = MenuBarView(model: model)
    }

    func testToggleRecordingFlipsState() {
        let model = AppModel()
        XCTAssertFalse(model.isRecording)
        XCTAssertEqual(model.primaryActionTitle, "Start Recording")

        model.toggleRecording()
        XCTAssertTrue(model.isRecording)
        XCTAssertEqual(model.primaryActionTitle, "Stop Recording")

        model.toggleRecording()
        XCTAssertFalse(model.isRecording)
    }
}
#endif
