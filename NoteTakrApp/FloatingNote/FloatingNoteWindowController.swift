import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted (e.g. from the menu bar) to ask the floating note window to toggle.
    static let noteTakrToggleFloatingNote = Notification.Name("noteTakrToggleFloatingNote")
}

/// Owns the always-on-top floating note panel and shows/hides it. The panel
/// floats above other apps while visible and is summoned/dismissed by a global
/// shortcut or the menu bar.
@MainActor
final class FloatingNoteWindowController {
    private let model: AppModel
    private let panel: NSPanel

    init(model: AppModel) {
        self.model = model

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()

        let host = NSHostingView(rootView: FloatingNoteView().environmentObject(model))
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleToggleRequest),
            name: .noteTakrToggleFloatingNote, object: nil
        )
    }

    private func configurePanel() {
        panel.title = "Note"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.minSize = NSSize(width: 360, height: 420)
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.center()
    }

    /// Shows the panel (and brings it forward) if hidden, hides it if visible.
    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        model.prepareFloatingNote()
        if panel.frame.origin == .zero { panel.center() }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    @objc private func handleToggleRequest() {
        toggle()
    }
}
