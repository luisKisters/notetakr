import AppKit
import Sparkle
import SwiftUI
import NoteTakrKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private(set) var notePanelController: NotePanelController?
    private var panelCoordinator: PanelToggleCoordinator?
    private var updaterController: SPUStandardUpdaterController?
    #if DEBUG
    private var e2ePanelToggleObserver: NSObjectProtocol?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let appModel = AppModel.shared
        let notesRoot = appModel.store.baseURL
        let npc = NotePanelController(notesRoot: notesRoot, appModel: appModel)
        notePanelController = npc

        let coordinator = PanelToggleCoordinator(
            panelRegistrar: CarbonHotkeyRegistrar(hotkeyID: 1),
            recordingRegistrar: CarbonHotkeyRegistrar(hotkeyID: 2)
        )
        coordinator.getPanelVisible = { npc.panel?.isVisible ?? false }
        coordinator.showPanel = { npc.show() }
        coordinator.hidePanel = { npc.panel?.orderOut(nil) }
        coordinator.flushPendingSave = { try? npc.bridge.viewModel.flush() }
        coordinator.startRecording = {
            Task { @MainActor in
                await appModel.quickRecording()
            }
        }
        coordinator.hotkeyRegistrationChanged = { [weak npc] purpose, combo, registered in
            let role: SettingsSheetViewModel.HotkeyRegistrationRole
            let label: String
            switch purpose {
            case .panelToggle:
                role = .showNote
                label = "Show note hotkey"
            case .recordingStart:
                role = .recording
                label = "Start recording hotkey"
            }
            npc?.settingsBridge.setHotkeyRegistrationMessage(
                registered ? nil : "\(label) \(combo.displayString) could not be registered. Choose a different shortcut.",
                for: role
            )
        }
        coordinator.updateHotkeys(
            panelToggle: npc.settingsBridge.appSettings.hotkey,
            recordingStart: npc.settingsBridge.appSettings.recordingHotkey
        )

        npc.settingsBridge.onHotkeyChange = { [weak coordinator, weak npc] _ in
            guard let settings = npc?.settingsBridge.appSettings else { return }
            coordinator?.updateHotkeys(panelToggle: settings.hotkey, recordingStart: settings.recordingHotkey)
        }
        npc.settingsBridge.onRecordingHotkeyChange = { [weak coordinator, weak npc] _ in
            guard let settings = npc?.settingsBridge.appSettings else { return }
            coordinator?.updateHotkeys(panelToggle: settings.hotkey, recordingStart: settings.recordingHotkey)
        }
        panelCoordinator = coordinator

        #if DEBUG
        installE2EPanelToggleControlIfRequested(coordinator: coordinator)
        #endif

        // Wire recording lifecycle to the panel's RecordingNoteBridge
        appModel.onRecordingStarted = { [weak npc] sessionID in
            let wasVisible = npc?.panel?.isVisible == true
            npc?.recordingStarted(sessionID: sessionID)
            if wasVisible {
                npc?.showLoadedNote()
            }
        }
        appModel.onRecordingStopped = { [weak npc] _ in
            npc?.recordingStopped()
        }

        statusBarController = StatusBarController(model: appModel, notePanelController: npc)
        startUpdaterIfConfigured()

        npc.settingsBridge.onAutoCheckForUpdatesChange = { [weak self] value in
            self?.updaterController?.updater.automaticallyChecksForUpdates = value
        }
        npc.settingsBridge.onAutoDownloadUpdatesChange = { [weak self] value in
            self?.updaterController?.updater.automaticallyDownloadsUpdates = value
        }

        NSApp.activate(ignoringOtherApps: true)
        npc.show()

        #if DEBUG
        runE2ELaunchHooks(notePanelController: npc)
        #endif

        // Populate the calendar event picker on launch if access was already granted.
        Task { await appModel.loadUpcomingEvents() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        notePanelController?.show()
        return true
    }

    private func startUpdaterIfConfigured() {
        guard hasSparkleConfiguration else {
            NSLog("Sparkle updater is not configured for this build.")
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        let settings = notePanelController?.settingsBridge.appSettings
        controller.updater.automaticallyChecksForUpdates = settings?.autoCheckForUpdates ?? true
        controller.updater.automaticallyDownloadsUpdates = settings?.autoDownloadUpdates ?? false
        controller.startUpdater()
        controller.updater.checkForUpdatesInBackground()

        NotificationCenter.default.addObserver(
            forName: .noteTakrCheckForUpdates,
            object: nil,
            queue: .main
        ) { [weak controller] _ in
            controller?.checkForUpdates(nil)
        }
    }

    private var hasSparkleConfiguration: Bool {
        guard
            let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        else {
            return false
        }

        return isConfigured(feedURL) && isConfigured(publicKey)
    }

    private func isConfigured(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("$(")
    }

    #if DEBUG
    private func installE2EPanelToggleControlIfRequested(coordinator: PanelToggleCoordinator) {
        guard ProcessInfo.processInfo.environment["NOTETAKR_E2E_ENABLE_PANEL_TOGGLE_CONTROL"] == "1" else {
            return
        }
        e2ePanelToggleObserver = DistributedNotificationCenter.default().addObserver(
            forName: .noteTakrE2ETogglePanel,
            object: nil,
            queue: .main
        ) { [weak coordinator] _ in
            coordinator?.toggle()
        }
    }

    private func runE2ELaunchHooks(notePanelController npc: NotePanelController) {
        let env = ProcessInfo.processInfo.environment
        let showPanel = env["NOTETAKR_E2E_SHOW_PANEL"] == "1"
        let openSwitcher = env["NOTETAKR_E2E_OPEN_SWITCHER"] == "1"
        let openSettings = env["NOTETAKR_E2E_OPEN_SETTINGS"] == "1"
        guard showPanel || openSwitcher || openSettings else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            npc.show()
            if openSwitcher {
                npc.settingsBridge.isVisible = false
                npc.switcherBridge.show()
            }
            if openSettings {
                npc.switcherBridge.dismiss()
                npc.settingsBridge.isVisible = true
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    #endif
}

// MARK: - Notification names

extension Notification.Name {
    static let noteTakrCheckForUpdates = Notification.Name("NoteTakrCheckForUpdates")
    #if DEBUG
    static let noteTakrE2ETogglePanel = Notification.Name("com.notetakr.e2e.togglePanel")
    #endif
}
