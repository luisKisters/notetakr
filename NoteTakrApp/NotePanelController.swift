import AppKit
import SwiftUI
import NoteTakrKit
import NoteTakrCore

/// Floating note panel (420×620). Owns the Kit NoteStore + NoteEditorBridge
/// + FrontmatterPresenterBridge + NoteTabsBridge + SwitcherBridge.
/// Menu bar "Open Note Panel" calls `show()`.
@MainActor
final class NotePanelController {
    private(set) var panel: NSPanel?
    private let store: NoteStore
    let bridge: NoteEditorBridge
    let frontmatterBridge: FrontmatterPresenterBridge
    let tabsBridge: NoteTabsBridge
    let switcherBridge: SwitcherBridge

    private let sessionStore: SessionStore?
    private let calendarEventsProvider = CalendarEventsProvider()

    init(notesRoot: URL, appModel: AppModel? = nil) {
        store = NoteStore(root: notesRoot)
        bridge = NoteEditorBridge(store: store)
        frontmatterBridge = FrontmatterPresenterBridge(store: store)

        let generator: (any SummaryGenerating)?
        let sessionStoreRef: SessionStore?

        if let appModel {
            let adapter = SummaryGeneratingAdapter(
                sessionStore: appModel.store,
                settingsStore: appModel.summarizationSettingsStore,
                templateStore: appModel.summaryTemplateStore,
                keychainStore: appModel.keychainStore
            )
            generator = adapter
            sessionStoreRef = appModel.store
        } else {
            generator = nil
            sessionStoreRef = nil
        }
        sessionStore = sessionStoreRef

        let editorViewModel = bridge.viewModel
        let presenter = NoteTabsPresenter(
            summaryGenerator: generator,
            editorFlush: { try editorViewModel.flush() }
        )

        if let ss = sessionStoreRef {
            presenter.onPersistSummary = { noteID, summary in
                guard let uuid = UUID(uuidString: noteID),
                      var session = try? ss.load(id: uuid) else { return }
                session.summary = summary
                try? ss.save(session)
            }
        }

        tabsBridge = NoteTabsBridge(presenter: presenter)

        // Build switcher
        let noteListProvider = NoteStoreListProvider(store: store)
        let switcherVM = SwitcherViewModel(
            noteListProvider: noteListProvider,
            eventsProvider: calendarEventsProvider,
            now: { Date() },
            store: store
        )
        switcherBridge = SwitcherBridge(viewModel: switcherVM)

        buildPanel()
        wireSwitcher()
    }

    /// Updates calendar events in the switcher from AppModel's current snapshot.
    func refreshCalendarEvents(from events: [CalendarEvent]) {
        calendarEventsProvider.events = events.map { ce in
            UpcomingEvent(
                id: ce.id,
                title: ce.title,
                start: ce.startDate,
                end: ce.endDate,
                participants: ce.attendees.map { p in
                    NoteTakrKit.Participant(name: p.name, email: p.email)
                }
            )
        }
    }

    private func wireSwitcher() {
        switcherBridge.onOpenNote = { [weak self] noteID in
            self?.loadNote(id: noteID)
        }
        switcherBridge.onEditorFocusRequest = { [weak self] in
            self?.panel?.makeFirstResponder(self?.panel?.contentView)
        }
        switcherBridge.onCreateBlankNote = { [weak self] in
            guard let self else { return }
            if let note = try? self.store.create(title: "Untitled meeting", date: Date()) {
                self.loadNote(id: note.id)
            }
        }
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
        // .canJoinAllSpaces and .moveToActiveSpace are mutually exclusive; use canJoinAllSpaces
        // so the panel is visible on every Space without moving.
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
        p.contentView = NSHostingView(
            rootView: EditorView(
                bridge: bridge,
                frontmatterBridge: frontmatterBridge,
                tabsBridge: tabsBridge,
                switcherBridge: switcherBridge
            )
        )
        self.panel = p
    }

    private func loadCurrentNote() {
        let notes = (try? store.list()) ?? []
        let note: MeetingNote?
        if let first = notes.first {
            note = first
        } else {
            note = try? store.create(title: "Untitled meeting", date: Date())
        }
        guard let note else { return }
        loadNote(id: note.id)
    }

    /// Loads a note by ID into all bridges (editor, frontmatter, tabs).
    func loadNote(id: String) {
        guard let note = try? store.load(id: id) else { return }
        try? bridge.viewModel.load(noteID: id)
        frontmatterBridge.load(note: note)
        tabsBridge.load(noteID: id)

        if let ss = sessionStore,
           let uuid = UUID(uuidString: id),
           let session = try? ss.load(id: uuid) {
            let rawSegments = session.transcriptSegments.map { seg in
                RawSegment(speaker: seg.speaker, timestamp: seg.timestamp, text: seg.text)
            }
            tabsBridge.presenter.setSegments(rawSegments, for: id)
            if let summary = session.summary, !summary.isEmpty {
                tabsBridge.presenter.setSummary(summary, for: id)
            }
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
