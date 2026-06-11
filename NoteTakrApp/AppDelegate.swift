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
    private var newNoteRegistrar: CarbonHotkeyRegistrar?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let notesRoot = base.appendingPathComponent("NoteTakr/Sessions")
        let npc = NotePanelController(notesRoot: notesRoot, appModel: AppModel.shared)
        notePanelController = npc

        let coordinator = PanelToggleCoordinator(registrar: CarbonHotkeyRegistrar())
        coordinator.getPanelVisible = { npc.panel?.isVisible ?? false }
        coordinator.showPanel = { npc.show() }
        coordinator.hidePanel = { npc.panel?.orderOut(nil) }
        coordinator.flushPendingSave = { try? npc.bridge.viewModel.flush() }
        coordinator.updateHotkey(npc.settingsBridge.appSettings.hotkey)

        npc.settingsBridge.onHotkeyChange = { [weak coordinator] combo in
            coordinator?.updateHotkey(combo)
        }
        panelCoordinator = coordinator

        // Wire recording lifecycle to the panel's RecordingNoteBridge
        AppModel.shared.onRecordingStarted = { [weak npc] sessionID in
            npc?.recordingStarted(sessionID: sessionID)
            npc?.show()
        }
        AppModel.shared.onRecordingStopped = { [weak npc] _ in
            npc?.recordingStopped()
        }

        statusBarController = StatusBarController(model: .shared, notePanelController: npc)
        registerNewNoteHotkey(npc: npc)
        startUpdaterIfConfigured()

        npc.settingsBridge.onAutoCheckForUpdatesChange = { [weak self] value in
            self?.updaterController?.updater.automaticallyChecksForUpdates = value
        }
        npc.settingsBridge.onAutoDownloadUpdatesChange = { [weak self] value in
            self?.updaterController?.updater.automaticallyDownloadsUpdates = value
        }

        NSApp.activate(ignoringOtherApps: true)

        // Populate the calendar event picker on launch if access was already granted.
        Task { await AppModel.shared.loadUpcomingEvents() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        notePanelController?.show()
        return true
    }

    private func registerNewNoteHotkey(npc: NotePanelController) {
        guard let combo = try? HotkeyCombo(modifiers: .command, key: "N") else { return }
        let registrar = CarbonHotkeyRegistrar(hotkeyID: 2)
        registrar.register(combo: combo) { [weak npc] in
            Task { @MainActor in
                // Switcher handles ⌘N via its own SwiftUI shortcut; skip to avoid double creation.
                guard let npc, !npc.switcherBridge.isVisible else { return }
                npc.createNewNote()
                npc.show()
            }
        }
        newNoteRegistrar = registrar
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
}

// MARK: - Notification names

extension Notification.Name {
    static let noteTakrCheckForUpdates = Notification.Name("NoteTakrCheckForUpdates")
}
