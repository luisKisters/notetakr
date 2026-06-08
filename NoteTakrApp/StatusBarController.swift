import AppKit

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "NoteTakr")
        }

        let startItem = NSMenuItem(title: "Start Recording", action: #selector(startRecording), keyEquivalent: "")
        startItem.target = self

        let menu = NSMenu()
        menu.addItem(startItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NoteTakr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func startRecording() {
        // Placeholder — audio recording implemented in Task 3.
    }
}
