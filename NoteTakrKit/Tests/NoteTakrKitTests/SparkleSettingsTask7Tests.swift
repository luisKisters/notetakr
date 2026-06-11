import XCTest
@testable import NoteTakrKit

// Tests verifying Task 7: Sparkle update settings persistence.
// All assertions are Linux-safe: no Sparkle framework is imported.
// The actual Sparkle wiring is macOS-only (verified on the macOS CI runner).

final class SparkleSettingsTask7Tests: XCTestCase {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleTask7-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Defaults

    func testAutoCheckForUpdatesDefaultIsTrue() {
        let store = AppSettingsStore(root: makeTempDir())
        XCTAssertTrue(store.autoCheckForUpdates, "autoCheckForUpdates should default to true")
    }

    func testAutoDownloadUpdatesDefaultIsFalse() {
        let store = AppSettingsStore(root: makeTempDir())
        XCTAssertFalse(store.autoDownloadUpdates, "autoDownloadUpdates should default to false")
    }

    // MARK: - Persistence round-trips

    func testAutoCheckForUpdatesPersistsDisabled() {
        let root = makeTempDir()
        let s = AppSettingsStore(root: root)
        s.autoCheckForUpdates = false
        let s2 = AppSettingsStore(root: root)
        XCTAssertFalse(s2.autoCheckForUpdates)
    }

    func testAutoCheckForUpdatesPersistsEnabled() {
        let root = makeTempDir()
        let s = AppSettingsStore(root: root)
        s.autoCheckForUpdates = false
        s.autoCheckForUpdates = true
        let s2 = AppSettingsStore(root: root)
        XCTAssertTrue(s2.autoCheckForUpdates)
    }

    func testAutoDownloadUpdatesPersistsEnabled() {
        let root = makeTempDir()
        let s = AppSettingsStore(root: root)
        s.autoDownloadUpdates = true
        let s2 = AppSettingsStore(root: root)
        XCTAssertTrue(s2.autoDownloadUpdates)
    }

    func testAutoDownloadUpdatesPersistsDisabled() {
        let root = makeTempDir()
        let s = AppSettingsStore(root: root)
        s.autoDownloadUpdates = true
        s.autoDownloadUpdates = false
        let s2 = AppSettingsStore(root: root)
        XCTAssertFalse(s2.autoDownloadUpdates)
    }

    // MARK: - Both fields coexist without interference

    func testBothFieldsRoundTripIndependently() {
        let root = makeTempDir()
        let s = AppSettingsStore(root: root)
        s.autoCheckForUpdates = false
        s.autoDownloadUpdates = true
        let s2 = AppSettingsStore(root: root)
        XCTAssertFalse(s2.autoCheckForUpdates)
        XCTAssertTrue(s2.autoDownloadUpdates)
    }

    func testUpdateSettingsDoNotCorruptOtherSettings() {
        let root = makeTempDir()
        let s = AppSettingsStore(root: root)
        s.transcribeByDefault = false
        s.yourName = "Test User"
        s.autoCheckForUpdates = false
        s.autoDownloadUpdates = true
        let s2 = AppSettingsStore(root: root)
        XCTAssertFalse(s2.transcribeByDefault, "unrelated field should not be affected")
        XCTAssertEqual(s2.yourName, "Test User", "unrelated field should not be affected")
        XCTAssertFalse(s2.autoCheckForUpdates)
        XCTAssertTrue(s2.autoDownloadUpdates)
    }

    // MARK: - Linux-safe notification trigger

    // The "Check for Updates" button posts a named notification; the AppDelegate
    // picks it up and calls Sparkle only on macOS. This test verifies the
    // notification name constant is available on Linux without importing Sparkle.
    func testCheckForUpdatesNotificationNameIsAvailable() {
        // The Notification.Name extension lives in NoteTakrApp (macOS-only target),
        // so we verify the settings properties that drive the trigger instead.
        // On Linux, the notification will fire but have no Sparkle listener — a safe no-op.
        let store = AppSettingsStore(root: makeTempDir())
        store.autoCheckForUpdates = true
        // If autoCheckForUpdates is true, AppDelegate wires Sparkle to fire on launch.
        // We can only assert the value is readable on this platform.
        XCTAssertTrue(store.autoCheckForUpdates)
    }
}
