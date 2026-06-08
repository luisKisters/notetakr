import AppKit
import SwiftUI
import NoteTakrCore

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: SessionStore
    private var sessionsWindow: NSPanel?

    override init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("NoteTakr/Sessions", isDirectory: true)
        store = SessionStore(baseURL: appSupport)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try? store.recoverInterruptedSessions()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "NoteTakr")
        }

        let startItem = NSMenuItem(title: "Start Recording", action: #selector(startRecording), keyEquivalent: "")
        startItem.target = self

        let sessionsItem = NSMenuItem(title: "Sessions...", action: #selector(showSessions), keyEquivalent: "")
        sessionsItem.target = self

        let menu = NSMenu()
        menu.addItem(startItem)
        menu.addItem(sessionsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NoteTakr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func startRecording() {
        // Placeholder — audio recording implemented in Task 3.
    }

    @objc private func showSessions() {
        if let existing = sessionsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let sessions = (try? store.loadAll()) ?? []
        let view = TodayView(sessions: sessions)
        let hostingController = NSHostingController(rootView: view)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentViewController = hostingController
        window.title = "Sessions"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        sessionsWindow = window
    }
}
