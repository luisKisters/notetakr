import AppKit
import Combine
import SwiftUI
import NoteTakrCore

/// Thin menu-bar controller. All state lives in `AppModel`; this just renders a
/// status item + menu and forwards actions, surfacing the single main window.
@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private var recordingMenuItem: NSMenuItem?
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton(isRecording: model.isRecording)
        statusItem.menu = makeMenu()

        model.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                self?.configureButton(isRecording: isRecording)
                self?.recordingMenuItem?.title = isRecording ? "Stop Recording" : "Start Recording"
            }
            .store(in: &cancellables)
    }

    private func configureButton(isRecording: Bool) {
        guard let button = statusItem.button else { return }
        let symbol = isRecording ? "mic.circle.fill" : "mic.circle"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "NoteTakr")
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = isRecording ? .systemRed : nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open NoteTakr", action: #selector(openMain), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        let quick = NSMenuItem(title: "Quick Recording", action: #selector(quickRecording), keyEquivalent: "")
        quick.target = self
        menu.addItem(quick)

        let record = NSMenuItem(
            title: model.isRecording ? "Stop Recording" : "Start Recording",
            action: #selector(toggleRecording), keyEquivalent: ""
        )
        record.target = self
        recordingMenuItem = record
        menu.addItem(record)
        menu.addItem(.separator())

        let folder = NSMenuItem(
            title: "Open Recordings Folder", action: #selector(openRecordingsFolder), keyEquivalent: ""
        )
        folder.target = self
        menu.addItem(folder)

        let settings = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(title: "Quit NoteTakr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )
        return menu
    }

    @objc private func openMain() { model.showWindow(tab: .sessions) }
    @objc private func openSettings() { model.showWindow(tab: .settings) }
    @objc private func openRecordingsFolder() { model.openRecordingsFolder() }
    @objc private func quickRecording() { Task { await model.quickRecording() } }
    @objc private func toggleRecording() { Task { await model.toggleRecording() } }
}
