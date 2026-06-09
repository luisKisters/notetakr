import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var floatingNoteController: FloatingNoteWindowController?
    private var floatingNoteHotkey: GlobalHotkey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        statusBarController = StatusBarController(model: .shared)

        // Floating note panel, summoned/dismissed by ⌥⌘N from anywhere.
        let floatingController = FloatingNoteWindowController(model: .shared)
        floatingNoteController = floatingController
        floatingNoteHotkey = GlobalHotkey(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(cmdKey | optionKey)
        ) { [weak floatingController] in
            floatingController?.toggle()
        }

        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.showWindow()
        return true
    }
}
