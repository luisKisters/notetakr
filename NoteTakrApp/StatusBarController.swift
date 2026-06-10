import AppKit
import Combine
import NoteTakrCore

/// Menu-bar status item. Forwards actions to the panel and recording pipeline.
@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private weak var notePanelController: NotePanelController?
    private let statusItem: NSStatusItem
    private var recordingMenuItem: NSMenuItem?
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel, notePanelController: NotePanelController? = nil) {
        self.model = model
        self.notePanelController = notePanelController
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

        let notePanel = NSMenuItem(title: "Toggle Note Panel", action: #selector(openNotePanel), keyEquivalent: "")
        notePanel.target = self
        menu.addItem(notePanel)
        menu.addItem(.separator())

        let record = NSMenuItem(
            title: model.isRecording ? "Stop Recording" : "Start Recording",
            action: #selector(toggleRecording), keyEquivalent: ""
        )
        record.target = self
        recordingMenuItem = record
        menu.addItem(record)
        menu.addItem(.separator())

        let folder = NSMenuItem(
            title: "Open Notes Folder", action: #selector(openRecordingsFolder), keyEquivalent: ""
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

    @objc private func openNotePanel() {
        if notePanelController?.panel?.isVisible == true {
            notePanelController?.panel?.orderOut(nil)
        } else {
            notePanelController?.show()
        }
    }
    @objc private func openSettings() { notePanelController?.show() }
    @objc private func openRecordingsFolder() { model.openRecordingsFolder() }
    @objc private func toggleRecording() { Task { await model.toggleRecording() } }
}
