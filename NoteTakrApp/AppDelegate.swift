import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private(set) var notePanelController: NotePanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let notesRoot = base.appendingPathComponent("NoteTakr/Sessions")
        notePanelController = NotePanelController(notesRoot: notesRoot, appModel: AppModel.shared)

        statusBarController = StatusBarController(model: .shared, notePanelController: notePanelController)
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.showWindow()
        return true
    }
}
