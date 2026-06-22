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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let appModel = AppModel.shared
        let notesRoot = appModel.store.baseURL
        let npc = NotePanelController(notesRoot: notesRoot, appModel: appModel)
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
        appModel.onRecordingStarted = { [weak npc] sessionID in
            npc?.recordingStarted(sessionID: sessionID)
            npc?.showLoadedNote()
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
        if ProcessInfo.processInfo.environment["NOTETAKR_E2E_SHOW_PANEL"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                npc.show()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
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
}

// MARK: - Notification names

extension Notification.Name {
    static let noteTakrCheckForUpdates = Notification.Name("NoteTakrCheckForUpdates")
}
