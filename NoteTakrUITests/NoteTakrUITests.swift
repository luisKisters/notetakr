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

    func testParticipantPickerAddsPersonFromPastMeetings() throws {
        let email = "ada.lovelace@analytical.example"
        try seedMeeting(
            id: "33333333-3333-3333-3333-333333333333",
            title: "Engine notes",
            date: "2026-07-08T09:00:00Z",
            participants: [SeedParticipant(name: "Ada Lovelace", email: email)]
        )
        try seedMeeting(
            id: "44444444-4444-4444-4444-444444444444",
            title: "Engine follow-up",
            date: "2026-07-09T09:00:00Z",
            participants: [SeedParticipant(name: "Ada Lovelace", email: email)]
        )
        try seedMeeting(
            id: "55555555-5555-5555-5555-555555555555",
            title: "Picker target",
            date: "2026-07-12T09:00:00Z"
        )

        launch(
            enablePanelToggleControl: true,
            expandFrontmatter: true,
            openPeoplePicker: true
        )

        let pickerField = element("participantPickerField")
        XCTAssertTrue(pickerField.waitForExistence(timeout: 8))
        pickerField.click()
        pickerField.typeText("Ada")

        let row = element("participantPickerRow_\(email)")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()

        try waitForPersistedParticipantFrontmatter(
            noteID: "55555555-5555-5555-5555-555555555555",
            name: "Ada Lovelace",
            email: email
        )
    }

    func testMeetingSyncsAfterRecordingStops() throws {
        launch(enablePanelToggleControl: true, mockSyncBackend: true)

        let recordButton = element("recordPillMainButton")
        XCTAssertTrue(recordButton.waitForExistence(timeout: 8))
        recordButton.click()
        XCTAssertTrue(
            element("recordPillCaretButton").waitForExistence(timeout: 8),
            "The mock recorder should enter the recording state."
        )

        recordButton.click()
        let payload = try waitForMockSyncPayload()
        let summaryText = "Server summary from the mock sync backend."
        try emitMockSyncSummary(
            localId: payload.localId,
            text: summaryText,
            crmPushStatus: "pushed"
        )

        app.buttons["Summary"].click()
        let readySummary = element("summaryReadyText")
        XCTAssertTrue(
            readySummary.waitForExistence(timeout: 10),
            "The Summary tab should render the server-emitted summary."
        )
        XCTAssertTrue(
            readySummary.label.contains(summaryText)
                || ((readySummary.value as? String)?.contains(summaryText) ?? false)
        )
        try waitForPersistedSummary(localId: payload.localId, text: summaryText)
        try waitForPersistedCrmPushStatus(localId: payload.localId, status: "pushed")
    }

    func testRecordingAutomaticallyWritesConfiguredObsidianFile() throws {
        let obsidianFolder = appSupportRoot
            .appendingPathComponent("Fixture Vault/Meeting Notes", isDirectory: true)
        try seedObsidianSettings(folder: obsidianFolder)
        launch(enablePanelToggleControl: true)

        let recordButton = element("recordPillMainButton")
        XCTAssertTrue(recordButton.waitForExistence(timeout: 8))
        recordButton.click()
        XCTAssertTrue(element("recordPillCaretButton").waitForExistence(timeout: 8))
        let recordedSession = try waitForRecordedSession()
        recordButton.click()

        let exported = try waitForObsidianExport(in: obsidianFolder)
        XCTAssertEqual(
            exported.url.lastPathComponent,
            "e2e-\(recordedSession.id.uuidString).md"
        )
        XCTAssertTrue(
            exported.markdown.contains("<!-- notetakr:\(recordedSession.id.uuidString) -->")
        )
        XCTAssertTrue(exported.markdown.contains("tags: [meeting, fixture]"))
        XCTAssertTrue(exported.markdown.contains("# "))
        XCTAssertFalse(exported.markdown.contains("{{"))
        XCTAssertFalse(exported.markdown.contains("}}"))
    }

    func testUnmatchedCrmBannerAppearsAboveFooter() throws {
        try seedMeeting(
            id: "66666666-6666-6666-6666-666666666666",
            title: "CRM unmatched meeting",
            date: "2026-07-13T09:00:00Z",
            participants: [SeedParticipant(name: "Mystery Guest", email: nil)]
        )

        launch(enablePanelToggleControl: true, mockCrmConnected: true)

        let banner = element("crmUnmatchedBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 8))
        let footerTab = app.buttons["Notes"]
        XCTAssertTrue(footerTab.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            banner.frame.maxY,
            footerTab.frame.minY + 2,
            "The CRM banner should sit above the footer tab bar."
        )

        element("crmUnmatchedBannerDismiss").click()
        XCTAssertTrue(
            banner.waitForNonExistence(timeout: 5),
            "Dismissing the CRM banner should hide it for the current meeting."
        )
    }

    private func launch(
        openSettings: Bool = false,
        openSwitcher: Bool = false,
        enablePanelToggleControl: Bool = false,
        commandKEvents: Bool = false,
        expandFrontmatter: Bool = false,
        openPeoplePicker: Bool = false,
        mockSyncBackend: Bool = false,
        mockCrmConnected: Bool = false
    ) {
        app.launchEnvironment["NOTETAKR_E2E_APP_SUPPORT_ROOT"] = appSupportRoot.path
        app.launchEnvironment["NOTETAKR_E2E_USE_MOCK_RECORDER"] = "1"
        app.launchEnvironment["NOTETAKR_E2E_MOCK_SYNC_BACKEND"] = mockSyncBackend ? "1" : "0"
        app.launchEnvironment["NOTETAKR_E2E_MOCK_CRM_CONNECTED"] = mockCrmConnected ? "1" : "0"
        app.launchEnvironment["NOTETAKR_E2E_SHOW_PANEL"] = "1"
        app.launchEnvironment["NOTETAKR_E2E_OPEN_SETTINGS"] = openSettings ? "1" : "0"
        app.launchEnvironment["NOTETAKR_E2E_OPEN_SWITCHER"] = openSwitcher ? "1" : "0"
        app.launchEnvironment["NOTETAKR_E2E_EXPAND_FRONTMATTER"] = expandFrontmatter ? "1" : "0"
        app.launchEnvironment["NOTETAKR_E2E_OPEN_PEOPLE_PICKER"] = openPeoplePicker ? "1" : "0"
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

    private func waitForMockSyncPayload(timeout: TimeInterval = 10) throws -> MockSyncPayload {
        let deadline = Date().addingTimeInterval(timeout)
        let payloads = mockSyncRoot()
            .appendingPathComponent("Payloads", isDirectory: true)
        while Date() < deadline {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: payloads,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )) ?? []
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let payload = try? JSONDecoder().decode(MockSyncPayload.self, from: data) else {
                    continue
                }
                return payload
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        throw NSError(
            domain: "NoteTakrUITests",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for mock sync payload"]
        )
    }

    private func emitMockSyncSummary(
        localId: String,
        text: String,
        crmPushStatus: String? = nil
    ) throws {
        let summaries = mockSyncRoot()
            .appendingPathComponent("Summaries", isDirectory: true)
        try FileManager.default.createDirectory(at: summaries, withIntermediateDirectories: true)
        let update = MockSyncSummary(
            localId: localId,
            text: text,
            crmPushStatus: crmPushStatus
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(update)
        try data.write(
            to: summaries.appendingPathComponent("\(localId).json"),
            options: .atomic
        )
    }

    private func waitForPersistedCrmPushStatus(
        localId: String,
        status: String,
        timeout: TimeInterval = 10
    ) throws {
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
                let file = folder.appendingPathComponent("note.md")
                guard let text = try? String(contentsOf: file, encoding: .utf8),
                      text.contains("id: \(localId)"),
                      text.contains("crm_push_status: \(status)") else {
                    continue
                }
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        throw NSError(
            domain: "NoteTakrUITests",
            code: 6,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for persisted CRM push status"]
        )
    }

    private func waitForPersistedSummary(
        localId: String,
        text: String,
        timeout: TimeInterval = 10
    ) throws {
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
                guard let data = try? Data(contentsOf: file),
                      let snapshot = try? JSONDecoder().decode(SummarySessionSnapshot.self, from: data),
                      snapshot.id.uuidString == localId,
                      snapshot.summary == text else {
                    continue
                }
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        throw NSError(
            domain: "NoteTakrUITests",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for persisted mock summary"]
        )
    }

    private func mockSyncRoot() -> URL {
        appSupportRoot
            .appendingPathComponent("NoteTakr", isDirectory: true)
            .appendingPathComponent("MockSyncBackend", isDirectory: true)
    }

    private func seedObsidianSettings(folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let settingsRoot = appSupportRoot.appendingPathComponent("NoteTakr", isDirectory: true)
        try FileManager.default.createDirectory(at: settingsRoot, withIntermediateDirectories: true)
        let settings = ObsidianFixtureSettings(
            obsidianExportEnabled: true,
            obsidianFolderPath: folder.path,
            obsidianTemplate: """
            ---
            tags: [meeting, fixture]
            ---
            # {{title}}

            {{notes}}

            {{summary}}

            {{transcript}}
            """,
            obsidianFileNameTemplate: "e2e-{{id}}"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(
            to: settingsRoot.appendingPathComponent("settings.json"),
            options: .atomic
        )
    }

    private func waitForObsidianExport(
        in folder: URL,
        timeout: TimeInterval = 10
    ) throws -> (url: URL, markdown: String) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )) ?? []
            for file in files where file.pathExtension.lowercased() == "md" {
                guard let markdown = try? String(contentsOf: file, encoding: .utf8),
                      markdown.contains("<!-- notetakr:") else { continue }
                return (file, markdown)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        throw NSError(
            domain: "NoteTakrUITests",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for automatic Obsidian export"]
        )
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func seedMeeting(
        id: String,
        title: String,
        date: String,
        participants: [SeedParticipant] = []
    ) throws {
        let sessions = appSupportRoot
            .appendingPathComponent("NoteTakr", isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)
        let folder = sessions.appendingPathComponent("seed_\(id.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var frontmatterLines = [
            "---",
            "id: \(id)",
            "title: \(title)",
            "date: \(date)",
        ]
        if !participants.isEmpty {
            let rendered = participants.map(\.frontmatterValue).joined(separator: ", ")
            frontmatterLines.append("participants: [\(rendered)]")
        }
        frontmatterLines.append("---")
        let markdown = frontmatterLines.joined(separator: "\n") + "\n"
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

    private func waitForPersistedParticipantFrontmatter(
        noteID: String,
        name: String,
        email: String,
        timeout: TimeInterval = 5
    ) throws {
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
                guard let text = try? String(contentsOf: noteURL, encoding: .utf8),
                      text.contains("id: \(noteID)") else { continue }
                let participant = "\(name) <\(email)>"
                if text.contains("participants:") && text.contains(participant) {
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        throw NSError(
            domain: "NoteTakrUITests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for persisted participant email"]
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
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.notetakr.e2e.setAppearance"),
            object: appearance,
            userInfo: nil,
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
    let id: UUID
    let inPerson: Bool
    let systemAudioEnabled: Bool
}

private struct SummarySessionSnapshot: Decodable {
    let id: UUID
    let summary: String?
}

private struct MockSyncPayload: Decodable {
    let localId: String
}

private struct MockSyncSummary: Encodable {
    let localId: String
    let text: String
    let crmPushStatus: String?
}

private struct ObsidianFixtureSettings: Encodable {
    let obsidianExportEnabled: Bool
    let obsidianFolderPath: String
    let obsidianTemplate: String
    let obsidianFileNameTemplate: String
}

private struct SeedParticipant {
    let name: String
    let email: String?

    var frontmatterValue: String {
        if let email, !email.isEmpty {
            return "\(name) <\(email)>"
        }
        return name
    }
}
