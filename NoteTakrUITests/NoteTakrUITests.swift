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

    func testPermissionsAndInPersonCanChangeAudioSourcesWhileRecording() throws {
        launch(openSettings: true, enablePanelToggleControl: true)

        let permissionsTab = element("settingsTab_permissions")
        XCTAssertTrue(permissionsTab.waitForExistence(timeout: 8))
        permissionsTab.click()

        XCTAssertTrue(element("permissionRow_Contacts").waitForExistence(timeout: 5))
        XCTAssertTrue(element("permissionRow_System Audio").waitForExistence(timeout: 5))

        element("settingsTab_thisMeeting").click()
        let inPersonToggle = element("inPersonMeetingToggle")
        XCTAssertTrue(inPersonToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(inPersonToggle.isEnabled)

        element("settingsCloseButton").click()
        let recordButton = element("recordPillMainButton")
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        recordButton.click()
        XCTAssertTrue(
            element("recordPillCaretButton").waitForExistence(timeout: 8),
            "The mock recorder should transition the pill to its recording state."
        )
        let initialSession = try waitForRecordedSession()
        XCTAssertFalse(initialSession.inPerson)
        XCTAssertTrue(initialSession.systemAudioEnabled)

        app.typeKey(",", modifierFlags: [.command])
        XCTAssertTrue(element("settingsTab_thisMeeting").waitForExistence(timeout: 5))
        element("settingsTab_thisMeeting").click()

        let liveToggle = element("inPersonMeetingToggle")
        XCTAssertTrue(liveToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(liveToggle.isEnabled, "In-person must remain editable during recording.")
        setInPersonFromTestProcess(true)
        try waitForPersistedInPersonFrontmatter()
        let updatedSession = try waitForRecordedSession(inPerson: true)
        XCTAssertFalse(
            updatedSession.systemAudioEnabled,
            "Turning on in-person during recording must stop and persist desktop audio as disabled."
        )
        let detail = element("inPersonMeetingDetail")
        XCTAssertEqual(
            (detail.value as? String) ?? detail.label,
            "Mic only — changes audio sources immediately"
        )
    }

    func testTitleBarControlsOpenCommandMenuAndSettings() {
        launch(enablePanelToggleControl: true)

        let commandButton = element("toolbarCommandKButton")
        let settingsButton = element("toolbarSettingsButton")
        let closeButton = element("toolbarCloseButton")
        XCTAssertTrue(commandButton.waitForExistence(timeout: 5))
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))

        commandButton.click()
        XCTAssertTrue(element("switcherOverlay").waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("meetingTitleField").waitForExistence(timeout: 5))

        settingsButton.click()
        XCTAssertTrue(element("settingsCloseButton").waitForExistence(timeout: 5))
        element("settingsCloseButton").click()

        closeButton.click()
        XCTAssertTrue(element("meetingTitleField").waitForNonExistence(timeout: 5))
        togglePanelFromTestProcess()
        XCTAssertTrue(element("meetingTitleField").waitForExistence(timeout: 5))
    }

    func testCalendarPickerFocusesCurrentEventAndSupportsKeyboardNavigation() {
        launch(commandKEvents: true, expandFrontmatter: true)

        let pickerButton = element("calendarEventPickerButton")
        XCTAssertTrue(pickerButton.waitForExistence(timeout: 5))
        pickerButton.click()

        let current = element("eventPickerRow_e2e-commandk-current-calendar-only")
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertEqual(current.value as? String, "Focused")
        let search = element("eventPickerSearchField")
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeKey(.downArrow, modifierFlags: [])
        XCTAssertEqual(
            element("eventPickerRow_e2e-commandk-future-calendar-only-1").value as? String,
            "Focused"
        )

        // Moving back to the still-visible current row must only change focus;
        // it must not jump or rebuild the picker beneath the user.
        search.typeKey(.upArrow, modifierFlags: [])
        XCTAssertEqual(current.value as? String, "Focused")
        XCTAssertTrue(element("eventPickerSearchField").isHittable)

        // Crossing the top edge reveals the previous row. Returning to the
        // still-visible current row must retain that exact viewport instead of
        // jumping back to the beginning or end of the list.
        search.typeKey(.upArrow, modifierFlags: [])
        let scrollBar = element("eventPickerList").scrollBars.firstMatch
        XCTAssertTrue(scrollBar.waitForExistence(timeout: 5))
        let revealedOffset = String(describing: scrollBar.value)
        search.typeKey(.downArrow, modifierFlags: [])
        XCTAssertEqual(String(describing: scrollBar.value), revealedOffset)
    }

    func testCommandMenuRowsExposeHoverFeedbackWithoutChangingKeyboardSelection() throws {
        try seedMeeting(
            id: "11111111-1111-1111-1111-111111111111",
            title: "Hover target",
            date: "2026-07-10T09:00:00Z"
        )
        try seedMeeting(
            id: "22222222-2222-2222-2222-222222222222",
            title: "Keyboard selection",
            date: "2026-07-11T09:00:00Z"
        )
        launch(openSwitcher: true)

        let hoverTarget = app.buttons[
            "switcherRow_note-11111111-1111-1111-1111-111111111111"
        ]
        let keyboardSelection = app.buttons[
            "switcherRow_note-22222222-2222-2222-2222-222222222222"
        ]
        XCTAssertTrue(hoverTarget.waitForExistence(timeout: 5))
        XCTAssertTrue(keyboardSelection.waitForExistence(timeout: 5))
        XCTAssertEqual(keyboardSelection.value as? String, "Selected")
        hoverTarget.hover()
        XCTAssertEqual(hoverTarget.value as? String, "Hovered")
        XCTAssertEqual(
            keyboardSelection.value as? String,
            "Selected",
            "Pointer hover must not silently replace the keyboard selection."
        )

        element("switcherSearchField").typeKey(.return, modifierFlags: [])
        let title = element("meetingTitleField")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Keyboard selection")
    }

    func testCalendarSwitchConfirmationBlocksThePickerBehindIt() {
        launch(commandKEvents: true, expandFrontmatter: true)

        let pickerButton = element("calendarEventPickerButton")
        XCTAssertTrue(pickerButton.waitForExistence(timeout: 5))
        pickerButton.click()

        // Link a future event first so choosing the current event exercises the
        // destructive metadata-update confirmation instead of immediately
        // dismissing the picker.
        let future = element("eventPickerRow_e2e-commandk-future-calendar-only-3")
        XCTAssertTrue(future.waitForExistence(timeout: 5))
        future.click()
        XCTAssertTrue(pickerButton.waitForExistence(timeout: 5))
        pickerButton.click()

        let current = element("eventPickerRow_e2e-commandk-current-calendar-only")
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        current.click()

        XCTAssertTrue(element("eventSwitchConfirmation").waitForExistence(timeout: 5))
        XCTAssertTrue(element("eventSwitchConfirmationUpdate").isHittable)
        XCTAssertFalse(
            element("eventPickerSearchField").exists,
            "The obscured picker must not remain interactive or scrollable behind the confirmation."
        )

        element("eventSwitchConfirmationCancel").click()
        XCTAssertTrue(element("eventPickerSearchField").waitForExistence(timeout: 5))
    }

    func testAppearanceChangesStaySynchronizedAcrossSettingsEditorAndCommandMenu() {
        launch(openSettings: true, enablePanelToggleControl: true)

        for appearance in ["light", "dark", "glass"] {
            setAppearanceFromTestProcess(appearance)
            XCTAssertTrue(waitForAppearance(appearance, element: element("settingsAppearance")))

            element("settingsCloseButton").click()
            XCTAssertTrue(waitForAppearance(appearance, element: element("editorAppearance")))

            element("toolbarCommandKButton").click()
            XCTAssertTrue(waitForAppearance(appearance, element: element("switcherAppearance")))

            app.typeKey(.escape, modifierFlags: [])
            element("toolbarSettingsButton").click()
            XCTAssertTrue(waitForAppearance(appearance, element: element("settingsAppearance")))
        }
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

        let selectedMeeting = app.buttons[
            "switcherRow_note-11111111-1111-1111-1111-111111111111"
        ]
        XCTAssertTrue(selectedMeeting.waitForExistence(timeout: 8))
        selectNoteFromTestProcess("11111111-1111-1111-1111-111111111111")

        let titleField = element("meetingTitleField")
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertEqual(titleField.value as? String, "Selected older meeting")

        let visibleMeeting = element("meetingTitleField")
        XCTAssertTrue(visibleMeeting.exists)
        togglePanelFromTestProcess()
        XCTAssertTrue(
            visibleMeeting.waitForNonExistence(timeout: 5),
            "Hiding the panel should remove the selected meeting editor from accessibility."
        )

        togglePanelFromTestProcess()
        let restoredTitle = element("meetingTitleField")
        XCTAssertTrue(
            restoredTitle.waitForExistence(timeout: 5),
            "Reopening the panel should restore the selected meeting editor."
        )
        XCTAssertEqual(restoredTitle.value as? String, "Selected older meeting")
    }

    private func launch(
        openSettings: Bool = false,
        openSwitcher: Bool = false,
        enablePanelToggleControl: Bool = false,
        commandKEvents: Bool = false,
        expandFrontmatter: Bool = false
    ) {
        app.launchEnvironment["NOTETAKR_E2E_APP_SUPPORT_ROOT"] = appSupportRoot.path
        app.launchEnvironment["NOTETAKR_E2E_USE_MOCK_RECORDER"] = "1"
        app.launchEnvironment["NOTETAKR_E2E_SHOW_PANEL"] = "1"
        app.launchEnvironment["NOTETAKR_E2E_OPEN_SETTINGS"] = openSettings ? "1" : "0"
        app.launchEnvironment["NOTETAKR_E2E_OPEN_SWITCHER"] = openSwitcher ? "1" : "0"
        app.launchEnvironment["NOTETAKR_E2E_ENABLE_PANEL_TOGGLE_CONTROL"] =
            enablePanelToggleControl ? "1" : "0"
        app.launchEnvironment["NOTETAKR_E2E_COMMANDK_EVENTS"] = commandKEvents ? "1" : "0"
        app.launchEnvironment["NOTETAKR_E2E_EXPAND_FRONTMATTER"] = expandFrontmatter ? "1" : "0"
        app.launch()
        app.activate()

        let launchAnchor: XCUIElement
        if openSettings {
            launchAnchor = element("settingsTab_permissions")
        } else if openSwitcher {
            launchAnchor = element("switcherOverlay")
        } else {
            launchAnchor = element("meetingTitleField")
        }
        XCTAssertTrue(
            launchAnchor.waitForExistence(timeout: 10),
            "The requested NoteTakr screen should become accessible after launch."
        )
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

    private func waitForRecordedSession(
        inPerson expectedInPerson: Bool? = nil,
        timeout: TimeInterval = 5
    ) throws -> SessionSnapshot {
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
                   let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data),
                   expectedInPerson == nil || snapshot.inPerson == expectedInPerson {
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

    private func waitForPersistedInPersonFrontmatter(timeout: TimeInterval = 5) throws {
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
                let noteURL = folder.appendingPathComponent("note.md")
                guard let text = try? String(contentsOf: noteURL, encoding: .utf8) else { continue }
                let persisted = text.split(separator: "\n").contains {
                    $0.trimmingCharacters(in: .whitespaces) == "in_person: true"
                }
                if persisted { return }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        throw NSError(
            domain: "NoteTakrUITests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for in_person: true frontmatter"]
        )
    }

    private func togglePanelFromTestProcess() {
        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.notetakr.e2e.togglePanel"),
            object: nil
        )
    }

    private func selectNoteFromTestProcess(_ noteID: String) {
        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.notetakr.e2e.selectNote"),
            object: noteID
        )
    }

    private func setInPersonFromTestProcess(_ value: Bool) {
        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.notetakr.e2e.setInPerson"),
            object: value ? "1" : "0"
        )
    }

    private func setAppearanceFromTestProcess(_ appearance: String) {
        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.notetakr.e2e.setAppearance"),
            object: appearance,
            deliverImmediately: true
        )
    }

    private func waitForAppearance(
        _ appearance: String,
        element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let expected = "Appearance: \(appearance)"
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.waitForExistence(timeout: 0.2), element.value as? String == expected {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    }
}

private struct SessionSnapshot: Decodable {
    let inPerson: Bool
    let systemAudioEnabled: Bool
}
