import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private(set) var notePanelController: NotePanelController?
    private var panelCoordinator: PanelToggleCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

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

        statusBarController = StatusBarController(model: .shared, notePanelController: npc)
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.showWindow()
        return true
    }
}
