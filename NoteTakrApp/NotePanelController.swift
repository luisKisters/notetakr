import AppKit
import SwiftUI
import NoteTakrKit

/// Floating note panel (420×620). Owns the Kit NoteStore + NoteEditorBridge.
/// Menu bar "Open Note Panel" calls `show()`.
@MainActor
final class NotePanelController {
    private(set) var panel: NSPanel?
    private let store: NoteStore
    let bridge: NoteEditorBridge

    init(notesRoot: URL) {
        store = NoteStore(root: notesRoot)
        bridge = NoteEditorBridge(store: store)
        buildPanel()
    }

    func show() {
        loadCurrentNote()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Private

    private func buildPanel() {
        let p = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // IMPORTANT: set collectionBehavior BEFORE calling makeKeyAndOrderFront —
        // omitting this causes a launch-abort crash on macOS.
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.backgroundColor = NSColor(red: 0.082, green: 0.078, blue: 0.090, alpha: 1)
        p.minSize = NSSize(width: 300, height: 400)
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.center()
        p.contentView = NSHostingView(rootView: EditorView(bridge: bridge))
        self.panel = p
    }

    private func loadCurrentNote() {
        let notes = (try? store.list()) ?? []
        if let first = notes.first {
            try? bridge.viewModel.load(noteID: first.id)
        } else if let note = try? store.create(title: "Untitled meeting", date: Date()) {
            try? bridge.viewModel.load(noteID: note.id)
        }
    }
}

// MARK: -

/// NSPanel subclass that closes on Escape.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
