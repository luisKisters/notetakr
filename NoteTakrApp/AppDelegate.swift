import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        statusBarController = StatusBarController()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowSettingsWindow),
            name: .noteTakrShowSettingsWindow,
            object: nil
        )
        showSettingsWindow()
    }

    @objc private func handleShowSettingsWindow() {
        showSettingsWindow()
    }

    private func showSettingsWindow() {
        // Uses the SwiftUI Settings scene window (single managed instance, normal window level).
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name {
    static let noteTakrShowSettingsWindow =
        Notification.Name("NoteTakrShowSettingsWindow")
}
