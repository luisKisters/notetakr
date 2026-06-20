import AppKit
import Combine
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
    private let vocabularyStore: VocabularyStore?

    // Recording wiring
    private var recordingBridge: RecordingNoteBridge?
    private var transcriptionAdapter: TranscriptionRequestingAdapter?
    private var elapsedTimer: Timer?
    private var pillTickTimer: Timer?
    private var pillPipelineCancellables = Set<AnyCancellable>()
    private var calendarCancellables = Set<AnyCancellable>()
    private weak var appModelRef: AppModel?

    init(notesRoot: URL, appModel: AppModel? = nil) {
        store = NoteStore(root: notesRoot)
        bridge = NoteEditorBridge(store: store)
        frontmatterBridge = FrontmatterPresenterBridge(store: store)
        recordPillMachine = RecordPillStateMachine()

        let settingsRoot = notesRoot.deletingLastPathComponent()
        let localAppSettings = appModel?.appSettings ?? AppSettingsStore(root: settingsRoot)
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
            vocabularyStore = appModel.vocabularyStore
        } else {
            generator = nil
            sessionStoreRef = nil
            vocabularyStore = nil
        }
        sessionStore = sessionStoreRef

        let editorViewModel = bridge.viewModel
        let presenter = NoteTabsPresenter(
            summaryGenerator: generator,
            transcriptGenerator: transcriptionAdapter,  // enables the "Generate transcript" button
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
        wireCalendarSync(appModel: appModel)
    }

    /// Updates calendar events in the switcher from an external snapshot.
    func refreshCalendarEvents(from events: [CalendarEvent]) {
        let upcoming = events.toUpcomingEvents()
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

        let globalVocab = (try? vocabularyStore?.enabledEntries())?.map { $0.phrase } ?? []
        let settings = EffectiveMeetingSettings.resolve(note: presenter.note, defaults: appSettings, globalVocabulary: globalVocab)
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
        (panel as? FloatingPanel)?.updateCloseButtonVisibilityForCurrentMouse()
        Task { await appModelRef?.loadUpcomingEvents() }
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
        p.acceptsMouseMovedEvents = true
        p.minSize = NSSize(width: 300, height: 400)
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.center()
        p.contentView = HoverTrackingHostingView(
            rootView: EditorView(
                bridge: bridge,
                frontmatterBridge: frontmatterBridge,
                tabsBridge: tabsBridge,
                switcherBridge: switcherBridge,
                settingsBridge: settingsBridge,
                recordPillMachine: recordPillMachine
            ),
            hoverChanged: { [weak p] isHovered in
                p?.setCloseButtonVisible(isHovered)
            }
        )
        p.startCloseButtonHoverTracking()
        // Wire ESC precedence: settings → switcher → hide panel.
        // This is a safety-net in case SwiftUI keyboard shortcuts don't consume the event
        // (e.g. focus is on an AppKit control rather than a SwiftUI view).
        p.cancelHandler = { [weak self] in
            guard let self else { return false }
            let context = KeyCommandRouter.activeContext(
                settingsVisible: self.settingsBridge.isVisible,
                switcherVisible: self.switcherBridge.isVisible
            )
            switch context {
            case .settingsVisible:
                self.settingsBridge.close()
                return true
            case .switcherVisible:
                self.switcherBridge.dismiss()
                return true
            case .inlineEditActive, .editorFocused:
                return false
            }
        }
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
            // Keep the panel up front and key — creating a note must never look like the window closed.
            ensurePanelKey()
        }
    }

    private func wireRecordPill(appModel: AppModel?) {
        guard let appModel else { return }
        let machine = recordPillMachine

        machine.onStarted = { [weak self, weak appModel] in
            guard let appModel else { return }
            Task { @MainActor in
                await appModel.startRecording(title: nil)
                guard appModel.isRecording else {
                    // Start failed (classic cause: mic permission). Don't let the pill
                    // pretend to record — reset it and tell the user why.
                    self?.recordPillMachine.reset()
                    self?.showRecordingError(
                        appModel.recordingError ?? "Recording could not be started."
                    )
                    return
                }
                self?.startPillTickTimer()
            }
        }

        machine.onStopped = { [weak self, weak appModel] intent in
            guard let self, let appModel else { return }
            let stoppedNoteID = self.frontmatterBridge.noteID
            Task { @MainActor in
                self.stopPillTickTimer()
                await appModel.stopRecording()
                guard !stoppedNoteID.isEmpty,
                      self.frontmatterBridge.noteID == stoppedNoteID else { return }
                self.recordPillMachine.beginTranscribing()
                self.frontmatterBridge.hasCompletedRecording = true
                self.drivePostStopPipeline(noteID: stoppedNoteID, intent: intent)
            }
        }

        machine.onRestarted = { [weak self, weak appModel] in
            guard let appModel else { return }
            Task { @MainActor in
                self?.pillPipelineCancellables.removeAll()
                await appModel.stopRecording()
                await appModel.startRecording(title: nil)
                self?.startPillTickTimer()
            }
        }

        machine.onDiscarded = { [weak self, weak appModel] in
            guard let appModel else { return }
            Task { @MainActor in
                self?.stopPillTickTimer()
                self?.pillPipelineCancellables.removeAll()
                await appModel.stopRecording()
            }
        }

        machine.onViewSummary = { [weak self] in
            self?.tabsBridge.selectTab(.summary)
        }

        machine.onViewTranscript = { [weak self] in
            self?.tabsBridge.selectTab(.transcript)
        }
    }

    // Drive the pill state machine through transcribing → summarizing → done
    // after audio stops. Uses Combine to watch NoteTabsBridge's published states.
    private func drivePostStopPipeline(noteID: String, intent: StopIntent) {
        pillPipelineCancellables.removeAll()

        // Distinguish "transcription actually ran" from "nothing happened". A freshly
        // loaded note publishes `.empty` as its initial transcript state, so accepting the
        // very first non-generating value would instantly (and falsely) resolve the pill as
        // "Transcribed". Require the publisher to pass through `.generating` first — that's
        // the marker that transcription truly started — before treating `.empty`/`.failed`/
        // segments as the real terminal outcome.
        let didStartTranscribing = TranscribeStartFlag()
        tabsBridge.$transcriptState
            .receive(on: DispatchQueue.main)
            .filter { state in
                switch state {
                case .generating:
                    didStartTranscribing.value = true
                    return false
                case .segments(let segs):
                    return didStartTranscribing.value && !segs.isEmpty
                case .empty, .failed:
                    return didStartTranscribing.value
                }
            }
            .first()
            .sink { [weak self] state in
                self?.handlePostStopTerminal(state, noteID: noteID, intent: intent)
            }
            .store(in: &pillPipelineCancellables)

        // Safety net: if transcription never starts (e.g. transcribe disabled for this note),
        // `.generating` is never published and the pipeline above would never resolve, leaving
        // the pill stuck in `.transcribing`. After a short grace period, if transcription never
        // began, free the pill back to Record rather than showing a fake "Transcribed".
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            guard self.frontmatterBridge.noteID == noteID else { return }
            guard !didStartTranscribing.value else { return }
            guard self.recordPillMachine.state == .transcribing else { return }
            self.pillPipelineCancellables.removeAll()
            self.recordPillMachine.cancelBusyPipeline()
        }
    }

    /// Resolves the record pill once transcription reaches a terminal state.
    /// Only called after transcription was observed to actually start (see drivePostStopPipeline).
    private func handlePostStopTerminal(_ state: TranscriptState, noteID: String, intent: StopIntent) {
        switch state {
        case .segments(let segs) where !segs.isEmpty:
            handleTranscriptComplete(noteID: noteID, intent: intent)
        case .failed:
            // Surface the error in the Transcript tab and free the pill so the user can retry.
            recordPillMachine.cancelBusyPipeline()
            tabsBridge.selectTab(.transcript)
        case .empty:
            // Transcription ran but found no speech — nothing to summarize; finish as transcript-only.
            recordPillMachine.finishAsDoneTranscript()
            tabsBridge.selectTab(.transcript)
        default:
            // Transcription never produced a real terminal outcome; free the pill back to Record.
            recordPillMachine.cancelBusyPipeline()
        }
    }

    private func handleTranscriptComplete(noteID: String, intent: StopIntent) {
        if intent == .transcribe {
            recordPillMachine.finishAsDoneTranscript()
            tabsBridge.selectTab(.transcript)
        } else {
            recordPillMachine.beginSummarizing()
            tabsBridge.selectTab(.summary)
            tabsBridge.generateSummary()

            tabsBridge.$summaryState
                .receive(on: DispatchQueue.main)
                .filter {
                    if case .ready = $0 { return true }
                    if case .failed = $0 { return true }
                    return false
                }
                .first()
                .sink { [weak self] _ in
                    self?.recordPillMachine.finishAsDone()
                }
                .store(in: &pillPipelineCancellables)
        }
    }

    /// Shows a recording failure to the user (alert attached to the panel when possible).
    private func showRecordingError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Recording failed to start"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if message.localizedCaseInsensitiveContains("microphone")
            || message.localizedCaseInsensitiveContains("permission") {
            alert.addButton(withTitle: "Open Privacy Settings")
        }
        let response = alert.runModal()
        if response == .alertSecondButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
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

    private func wireCalendarSync(appModel: AppModel?) {
        guard let appModel else { return }
        appModelRef = appModel
        appModel.$upcomingEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                self?.refreshCalendarEvents(from: events)
            }
            .store(in: &calendarCancellables)
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
                // Keep the panel up front and key — creating a note must never look like the window closed.
                self.ensurePanelKey()
            }
        }
        switcherBridge.onDeleteNote = { [weak self] deletedID in
            guard let self else { return }
            // Only react when the deleted note is the one currently open in the editor;
            // otherwise the editor would be showing a note that no longer exists on disk.
            guard self.frontmatterBridge.noteID == deletedID else { return }
            let remaining = (try? self.store.list()) ?? []
            if let next = remaining.first(where: { $0.id != deletedID }) ?? remaining.first {
                self.loadNote(id: next.id)
            } else if let blank = try? self.store.create(title: "Untitled meeting", date: Date()) {
                self.loadNote(id: blank.id)
            }
            self.ensurePanelKey()
        }
        switcherBridge.onOpenSettings = { [weak self] in
            self?.settingsBridge.isVisible = true
        }
    }

    /// True while the record pill represents an in-progress (or paused) recording session.
    /// Used to avoid resetting the pill during the recording-start reload of `loadNote`.
    private var isPillActivelyRecording: Bool {
        switch recordPillMachine.state {
        case .recording, .paused: return true
        default: return false
        }
    }

    /// Re-asserts the panel as visible and key. Used after note create/delete so the floating
    /// window never appears to close out from under the user.
    private func ensurePanelKey() {
        guard let panel else { return }
        if !panel.isVisible || !panel.isKeyWindow {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Loads a note by ID into all bridges (editor, frontmatter, tabs).
    func loadNote(id: String) {
        // The pill is a single global machine shared across notes, so terminal states
        // (.done/.doneTranscript) and busy states would otherwise leak onto a freshly opened
        // note and make it look already "Transcribed". Reset the pill to `.idle` here so every
        // opened note starts at Record.
        //
        // EXCEPTION: a recording start re-invokes `loadNote` (onRecordingStarted → recordingStarted)
        // for the brand-new session id while the pill is already `.recording`. Resetting then would
        // knock the just-started recording back to `.idle`, so skip the reset while a recording is
        // active. (cancelBusyPipeline() previously used here never reset terminal states, hence the leak.)
        if !isPillActivelyRecording {
            pillPipelineCancellables.removeAll()
            recordPillMachine.reset()
        }
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
            frontmatterBridge.audioFileURL = Self.audioFileURL(for: session, store: ss)
            frontmatterBridge.hasCompletedRecording = frontmatterBridge.audioFileURL != nil
        }
    }

    /// Resolves the note's playable audio file (microphone preferred). Stored paths can
    /// be stale after a title rename moved the session folder, so fall back to the same
    /// filename inside the session's current directory.
    private static func audioFileURL(for session: MeetingSession, store: SessionStore) -> URL? {
        let dir = store.sessionURL(for: session)
        let candidates = session.audioFilePaths.sorted {
            // microphone first — it's the user's own voice and always present
            $0.contains("microphone") && !$1.contains("microphone")
        }
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
            let healed = dir.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
            if FileManager.default.fileExists(atPath: healed.path) {
                return healed
            }
        }
        return nil
    }
}

// MARK: -

/// Reference-type box so the transcript-state filter closure and the deferred timeout
/// block can share the "did `.generating` ever appear?" flag. All access happens on the
/// main queue (the publisher uses `.receive(on: .main)` and the timeout is on `.main`).
private final class TranscribeStartFlag {
    var value = false
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    private var localHoverMonitor: Any?
    private var globalHoverMonitor: Any?

    /// Called by the controller after the panel is built to wire the overlay checks.
    /// Return `true` to consume the ESC and prevent the panel from hiding.
    var cancelHandler: (() -> Bool)?

    override func cancelOperation(_ sender: Any?) {
        if let handler = cancelHandler, handler() { return }
        orderOut(nil)
    }

    /// Wire ⌘W to hide the floating panel. There is no standard window menu here, so the
    /// default ⌘W → performClose: responder-chain routing isn't reliably available; handle it
    /// explicitly. `isReleasedWhenClosed` is false, so ordering out simply hides the panel.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            orderOut(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func setCloseButtonVisible(_ isVisible: Bool) {
        standardWindowButton(.closeButton)?.isHidden = !isVisible
    }

    func updateCloseButtonVisibilityForCurrentMouse() {
        setCloseButtonVisible(isVisible && frame.contains(NSEvent.mouseLocation))
    }

    func startCloseButtonHoverTracking() {
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        localHoverMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.updateCloseButtonVisibilityForCurrentMouse()
            return event
        }
        globalHoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateCloseButtonVisibilityForCurrentMouse()
            }
        }
    }

    deinit {
        if let localHoverMonitor {
            NSEvent.removeMonitor(localHoverMonitor)
        }
        if let globalHoverMonitor {
            NSEvent.removeMonitor(globalHoverMonitor)
        }
    }
}

private final class HoverTrackingHostingView<Content: View>: NSHostingView<Content> {
    private var hoverChanged: (Bool) -> Void = { _ in }
    private var hoverTrackingArea: NSTrackingArea?

    init(rootView: Content, hoverChanged: @escaping (Bool) -> Void) {
        self.hoverChanged = hoverChanged
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    @MainActor dynamic required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            hoverChanged(false)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hoverChanged(true)
    }

    override func mouseExited(with event: NSEvent) {
        hoverChanged(false)
    }
}
