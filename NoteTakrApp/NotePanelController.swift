import AppKit
import SwiftUI
import NoteTakrKit
import NoteTakrCore

/// Floating note panel (420×620). Owns the Kit NoteStore + all bridges.
/// AppDelegate calls `show()`, `recordingStarted(sessionID:)`, `recordingStopped()`.
@MainActor
final class NotePanelController {
    private(set) var panel: NSPanel?
    private let store: NoteStore
    let bridge: NoteEditorBridge
    let frontmatterBridge: FrontmatterPresenterBridge
    let tabsBridge: NoteTabsBridge
    let switcherBridge: SwitcherBridge
    let settingsBridge: SettingsSheetViewModel
    let recordPillMachine: RecordPillStateMachine

    private let sessionStore: SessionStore?
    private let calendarEventsProvider = CalendarEventsProvider()
    private let appSettings: AppSettingsStore

    // Recording wiring
    private var recordingBridge: RecordingNoteBridge?
    private var transcriptionAdapter: TranscriptionRequestingAdapter?
    private var elapsedTimer: Timer?
    private var pillTickTimer: Timer?

    init(notesRoot: URL, appModel: AppModel? = nil) {
        store = NoteStore(root: notesRoot)
        bridge = NoteEditorBridge(store: store)
        frontmatterBridge = FrontmatterPresenterBridge(store: store)
        recordPillMachine = RecordPillStateMachine()

        let settingsRoot = notesRoot.deletingLastPathComponent()
        let localAppSettings = AppSettingsStore(root: settingsRoot)
        appSettings = localAppSettings
        settingsBridge = SettingsSheetViewModel(
            frontmatterBridge: frontmatterBridge,
            appSettings: localAppSettings
        )

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
            transcriptionAdapter = TranscriptionRequestingAdapter(appModel: appModel)
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

        let noteListProvider = NoteStoreListProvider(store: store)
        let switcherVM = SwitcherViewModel(
            noteListProvider: noteListProvider,
            eventsProvider: calendarEventsProvider,
            now: { Date() },
            store: store,
            defaultsProvider: localAppSettings
        )
        switcherBridge = SwitcherBridge(viewModel: switcherVM)

        buildPanel()
        wireSwitcher()
        wireRecordPill(appModel: appModel)
    }

    /// Updates calendar events in the switcher from an external snapshot.
    func refreshCalendarEvents(from events: [CalendarEvent]) {
        let upcoming = events.map { ce in
            UpcomingEvent(
                id: ce.id,
                title: ce.title,
                start: ce.startDate,
                end: ce.endDate,
                participants: ce.attendees.map { p in
                    .init(name: p.name, email: p.email)
                },
                locationText: ce.location,
                meetingLink: ce.url?.absoluteString
            )
        }
        calendarEventsProvider.events = upcoming
        frontmatterBridge.availableEvents = upcoming
    }

    /// Returns currently available upcoming events for the property panel event chip.
    var availableEvents: [UpcomingEvent] { calendarEventsProvider.events }

    // MARK: - Recording lifecycle

    /// Called by AppDelegate when recording starts. Loads the note and starts the bridge.
    func recordingStarted(sessionID: String) {
        // Ensure note.md exists; synthesize from session.json if needed (migration path).
        if (try? store.load(id: sessionID)) == nil,
           let uuid = UUID(uuidString: sessionID),
           let session = try? sessionStore?.load(id: uuid) {
            let note = MeetingNote(id: sessionID, title: session.title, date: session.date)
            try? store.save(note)
        }

        loadNote(id: sessionID)

        guard let presenter = frontmatterBridge.presenter else { return }

        let settings = EffectiveMeetingSettings.resolve(note: presenter.note, defaults: appSettings)
        let recBridge = RecordingNoteBridge(
            frontmatterPresenter: presenter,
            tabsPresenter: tabsBridge.presenter,
            settings: settings,
            transcriptionService: transcriptionAdapter,
            now: { Date() }
        )
        recordingBridge = recBridge
        recBridge.startRecording()

        // Tick the elapsed REC chip every second
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.frontmatterBridge.refreshChips() }
        }
    }

    /// Called by AppDelegate when recording stops. Stops the bridge (triggers transcription).
    func recordingStopped() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        recordingBridge?.stopRecording()
        recordingBridge = nil
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
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.minSize = NSSize(width: 300, height: 400)
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.center()
        p.contentView = NSHostingView(
            rootView: EditorView(
                bridge: bridge,
                frontmatterBridge: frontmatterBridge,
                tabsBridge: tabsBridge,
                switcherBridge: switcherBridge,
                settingsBridge: settingsBridge,
                recordPillMachine: recordPillMachine
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

    /// Creates a blank note and loads it into the editor. Used by the ⌘N global hotkey.
    func createNewNote() {
        if let note = try? store.create(title: "Untitled meeting", date: Date()) {
            loadNote(id: note.id)
        }
    }

    private func wireRecordPill(appModel: AppModel?) {
        guard let appModel else { return }
        let machine = recordPillMachine

        machine.onStarted = { [weak self, weak appModel] in
            guard let appModel else { return }
            Task { @MainActor in
                await appModel.startRecording(title: nil)
                // Start pill tick timer
                self?.startPillTickTimer()
            }
        }

        machine.onStopped = { [weak self, weak appModel] intent in
            guard let appModel else { return }
            Task { @MainActor in
                self?.stopPillTickTimer()
                await appModel.stopRecording()
                // Show the audio player in the transcript row
                self?.frontmatterBridge.hasCompletedRecording = true
                if intent == .summarize {
                    let noteID = self?.frontmatterBridge.noteID ?? ""
                    if !noteID.isEmpty {
                        try? self?.tabsBridge.presenter.selectTab(.summary, for: noteID)
                        self?.tabsBridge.generateSummary()
                    }
                }
            }
        }
    }

    private func startPillTickTimer() {
        pillTickTimer?.invalidate()
        pillTickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.recordPillMachine.tick() }
        }
    }

    private func stopPillTickTimer() {
        pillTickTimer?.invalidate()
        pillTickTimer = nil
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
        switcherBridge.onOpenSettings = { [weak self] in
            self?.settingsBridge.isVisible = true
        }
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

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
