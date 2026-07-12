import Foundation
import XCTest

/// Hosted-runner GUI coverage uses NoteTakr's mock recorder and isolated storage.
/// It deliberately does not claim to validate real microphone, ScreenCaptureKit,
/// TCC prompts, or audio played by another application such as YouTube.
final class NoteTakrUITests: XCTestCase {
    private var app: XCUIApplication!
    private var appSupportRoot: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        appSupportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteTakrUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appSupportRoot,
            withIntermediateDirectories: true
        )
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if testRun?.failureCount ?? 0 > 0 {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "NoteTakr UI failure"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app?.terminate()
        if let appSupportRoot {
            try? FileManager.default.removeItem(at: appSupportRoot)
        }
        app = nil
        appSupportRoot = nil
    }

    func testPermissionsAndInPersonAudioSourceLockWhileRecording() throws {
        launch(openSettings: true)

        let permissionsTab = element("settingsTab_permissions")
        XCTAssertTrue(permissionsTab.waitForExistence(timeout: 8))
        permissionsTab.click()

        XCTAssertTrue(element("permissionRow_Contacts").waitForExistence(timeout: 5))
        XCTAssertTrue(element("permissionRow_System Audio").waitForExistence(timeout: 5))

        element("settingsTab_thisMeeting").click()
        let inPersonToggle = element("inPersonMeetingToggle")
        XCTAssertTrue(inPersonToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(inPersonToggle.isEnabled)
        inPersonToggle.click()
        let checked = expectation(
            for: NSPredicate(format: "value == '1'"),
            evaluatedWith: inPersonToggle
        )
        wait(for: [checked], timeout: 5)

        element("settingsCloseButton").click()
        let recordButton = element("recordPillMainButton")
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        recordButton.click()
        XCTAssertTrue(
            element("recordPillCaretButton").waitForExistence(timeout: 8),
            "The mock recorder should transition the pill to its recording state."
        )
        let session = try waitForRecordedSession()
        XCTAssertTrue(session.inPerson)
        XCTAssertFalse(
            session.systemAudioEnabled,
            "An in-person recording must persist without a desktop-audio stream."
        )

        app.typeKey(",", modifierFlags: [.command])
        XCTAssertTrue(element("settingsTab_thisMeeting").waitForExistence(timeout: 5))
        element("settingsTab_thisMeeting").click()

        let lockedToggle = element("inPersonMeetingToggle")
        XCTAssertTrue(lockedToggle.waitForExistence(timeout: 5))
        let disabled = expectation(
            for: NSPredicate(format: "enabled == false"),
            evaluatedWith: lockedToggle
        )
        wait(for: [disabled], timeout: 5)
        XCTAssertEqual(
            element("inPersonMeetingDetail").label,
            "Stop recording to change audio sources"
        )
    }

    func testHideAndReopenPreservesSelectedMeetingIdentity() throws {
        try seedMeeting(
            id: "11111111-1111-1111-1111-111111111111",
            title: "Selected older meeting",
            date: "2026-07-10T09:00:00Z"
        )
        try seedMeeting(
            id: "22222222-2222-2222-2222-222222222222",
            title: "More recent meeting",
            date: "2026-07-11T09:00:00Z"
        )
        launch(openSwitcher: true, enablePanelToggleControl: true)

        let selectedMeeting = app.staticTexts["Selected older meeting"]
        XCTAssertTrue(selectedMeeting.waitForExistence(timeout: 8))
        selectedMeeting.click()

        let titleField = element("meetingTitleField")
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertEqual(titleField.value as? String, "Selected older meeting")

        let visibleWindow = app.windows.firstMatch
        XCTAssertTrue(visibleWindow.exists)
        togglePanelFromTestProcess()
        XCTAssertTrue(visibleWindow.waitForNonExistence(timeout: 5))

        togglePanelFromTestProcess()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let restoredTitle = element("meetingTitleField")
        XCTAssertTrue(restoredTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredTitle.value as? String, "Selected older meeting")
    }

    private func launch(
        openSettings: Bool = false,
        openSwitcher: Bool = false,
        enablePanelToggleControl: Bool = false
    ) {
        app.launchEnvironment["NOTETAKR_E2E_APP_SUPPORT_ROOT"] = appSupportRoot.path
        app.launchEnvironment["NOTETAKR_E2E_USE_MOCK_RECORDER"] = "1"
        app.launchEnvironment["NOTETAKR_E2E_SHOW_PANEL"] = "1"
        app.launchEnvironment["NOTETAKR_E2E_OPEN_SETTINGS"] = openSettings ? "1" : "0"
        app.launchEnvironment["NOTETAKR_E2E_OPEN_SWITCHER"] = openSwitcher ? "1" : "0"
        app.launchEnvironment["NOTETAKR_E2E_ENABLE_PANEL_TOGGLE_CONTROL"] =
            enablePanelToggleControl ? "1" : "0"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func seedMeeting(id: String, title: String, date: String) throws {
        let sessions = appSupportRoot
            .appendingPathComponent("NoteTakr", isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)
        let folder = sessions.appendingPathComponent("seed_\(id.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let markdown = """
        ---
        id: \(id)
        title: \(title)
        date: \(date)
        ---
        """
        try Data(markdown.utf8).write(to: folder.appendingPathComponent("note.md"))
    }

    private func waitForRecordedSession(timeout: TimeInterval = 5) throws -> SessionSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        let sessions = appSupportRoot
            .appendingPathComponent("NoteTakr", isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)
        while Date() < deadline {
            let folders = (try? FileManager.default.contentsOfDirectory(
                at: sessions,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )) ?? []
            for folder in folders {
                let file = folder.appendingPathComponent("session.json")
                if let data = try? Data(contentsOf: file),
                   let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data) {
                    return snapshot
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        throw NSError(
            domain: "NoteTakrUITests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for mock recording metadata"]
        )
    }

    private func togglePanelFromTestProcess() {
        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.notetakr.e2e.togglePanel"),
            object: nil,
            deliverImmediately: true
        )
    }
}

private struct SessionSnapshot: Decodable {
    let inPerson: Bool
    let systemAudioEnabled: Bool
}
