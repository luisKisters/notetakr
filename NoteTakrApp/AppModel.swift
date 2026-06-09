import AppKit
import SwiftUI
import NoteTakrCore

/// Top-level navigation tabs shown in the window sidebar.
enum MainTab: Hashable {
    case sessions
    case calendar
    case settings
}

/// Single shared source of truth for the app: owns the session store, recorder,
/// transcription pipeline, and calendar state. Drives both the main window UI
/// and the menu-bar controller so they never diverge.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // Stores / services
    let store: SessionStore
    let recordingManager: RecordingManager
    let vocabularyStore: VocabularyStore
    let transcriptionSettingsStore: TranscriptionSettingsStore
    let summaryTemplateStore: SummaryTemplateStore
    let summarizationSettingsStore: SummarizationSettingsStore
    let keychainStore: KeychainStore
    private let summarizationService = SummarizationService()

    private let runtime = FluidAudioRuntime()
    private let audioLoader = FluidAudioSampleLoader()
    private let diarizer = OfflineDiarizationRuntime()
    private let booster = FluidAudioVocabularyBooster()
    private let notificationScheduler = MeetingNotificationScheduler()
    private var calendarAdapter: (any CalendarAdapter)?

    // Published UI state
    @Published var selectedTab: MainTab = .sessions
    @Published private(set) var sessions: [MeetingSession] = []
    @Published var selectedSessionID: UUID?
    @Published private(set) var isRecording = false
    @Published private(set) var transcriptionStates: [UUID: TranscriptionState] = [:]
    @Published private(set) var summarizationStates: [UUID: SummarizationState] = [:]
    @Published private(set) var nextMeeting: CalendarEvent?
    @Published private(set) var upcomingEvents: [CalendarEvent] = []
    @Published private(set) var isCalendarLoading = false
    @Published private(set) var calendarError: String?
    @Published private(set) var calendarAuthorized = false

    private var transcribingIDs: Set<UUID> = []
    private var summarizingIDs: Set<UUID> = []

    /// The hosting NSWindow, captured from SwiftUI so the menu bar can surface it.
    weak var mainWindow: NSWindow?

    /// Brings the main window to the front, optionally switching tabs first.
    func showWindow(tab: MainTab? = nil) {
        if let tab { selectedTab = tab }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let sessionsDir = base.appendingPathComponent("NoteTakr/Sessions", isDirectory: true)
        store = SessionStore(baseURL: sessionsDir)
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        try? store.recoverInterruptedSessions()

        vocabularyStore = VocabularyStore(
            fileURL: base.appendingPathComponent("NoteTakr/vocabulary.json")
        )
        transcriptionSettingsStore = TranscriptionSettingsStore(
            fileURL: base
                .appendingPathComponent("NoteTakr", isDirectory: true)
                .appendingPathComponent("transcription-settings.json")
        )
        summaryTemplateStore = SummaryTemplateStore(
            fileURL: base.appendingPathComponent("NoteTakr/summary-templates.json")
        )
        summarizationSettingsStore = SummarizationSettingsStore(
            fileURL: base.appendingPathComponent("NoteTakr/summarization-settings.json")
        )
        keychainStore = KeychainStore()
        recordingManager = RecordingManager(store: store, recorder: NativeAudioRecorder())

        refreshSessions()
        selectedSessionID = sessions.first?.id

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleStartRecordingFromNotification),
            name: .meetingNotificationStartRecording, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCalendarAccessGranted),
            name: .noteTakrCalendarAccessGranted, object: nil
        )
    }

    // MARK: - Sessions

    func refreshSessions() {
        sessions = (try? store.loadAll()) ?? []
    }

    var selectedSession: MeetingSession? {
        guard let id = selectedSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    func session(for id: UUID) -> MeetingSession? {
        sessions.first { $0.id == id }
    }

    /// Persists user edits (title/notes) without disturbing selection or the
    /// detail view's local draft.
    func persist(_ session: MeetingSession) {
        try? store.save(session)
        applyUpdatedSession(session)
    }

    func deleteSession(_ session: MeetingSession) {
        try? store.delete(session)
        sessions.removeAll { $0.id == session.id }
        transcriptionStates[session.id] = nil
        if selectedSessionID == session.id {
            selectedSessionID = sessions.first?.id
        }
    }

    private func applyUpdatedSession(_ session: MeetingSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        sessions.sort { $0.date > $1.date }
    }

    // MARK: - Recording

    func startRecording(title: String? = nil) async {
        guard !recordingManager.isRecording else { return }
        let name = title ?? nextMeeting?.title ?? "Meeting Recording"
        do {
            let session = try await recordingManager.startRecording(title: name)
            isRecording = true
            refreshSessions()
            selectedTab = .sessions
            selectedSessionID = session.id
        } catch {
            isRecording = recordingManager.isRecording
        }
    }

    func quickRecording() async {
        await startRecording(title: "Quick Recording")
    }

    func stopRecording() async {
        guard recordingManager.isRecording else { return }
        let stopped = try? await recordingManager.stopRecording()
        isRecording = false
        refreshSessions()
        if let stopped {
            selectedSessionID = stopped.id
            autoTranscribeIfNeeded(stopped)
        }
    }

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    // MARK: - Transcription (diarization + vocabulary boosting, automatic)

    /// Kicks off transcription for a session that has audio but no transcript yet.
    /// Called when a session is selected and right after a recording stops, so
    /// transcripts appear without any manual step.
    func autoTranscribeIfNeeded(_ session: MeetingSession) {
        guard !session.audioFilePaths.isEmpty, session.transcriptSegments.isEmpty else { return }
        guard session.status == .stopped else { return }
        guard !transcribingIDs.contains(session.id) else { return }
        guard transcriptionSettingsStore.load().source != .notConfigured else {
            transcriptionStates[session.id] = .modelUnavailable
            return
        }
        Task { await transcribe(session) }
    }

    func autoTranscribeSelected() {
        guard let session = selectedSession else { return }
        autoTranscribeIfNeeded(session)
    }

    /// Re-runs transcription from scratch (used by the manual "Transcribe again" button).
    func retranscribe(_ session: MeetingSession) {
        guard !transcribingIDs.contains(session.id) else { return }
        var cleared = session
        cleared.transcriptSegments = []
        persist(cleared)
        Task { await transcribe(cleared) }
    }

    func transcribe(_ session: MeetingSession) async {
        guard !transcribingIDs.contains(session.id) else { return }
        transcribingIDs.insert(session.id)
        transcriptionStates[session.id] = .transcribing

        // Reload the freshest copy so concurrent note edits are not clobbered.
        let latest = (try? store.load(id: session.id)) ?? session
        let vocab = (try? vocabularyStore.enabledEntries()) ?? []
        let engine = FluidAudioAdapter(
            settingsStore: transcriptionSettingsStore,
            runtime: runtime,
            audioLoader: audioLoader,
            diarizer: diarizer,
            booster: booster
        )
        let service = TranscriptionService(engine: engine, store: store)

        do {
            let updated = try await service.transcribe(session: latest, vocabulary: vocab)
            transcriptionStates[session.id] = .completed
            applyUpdatedSession(updated)
            autoSummarizeIfNeeded(updated)
        } catch TranscriptionError.modelUnavailable {
            transcriptionStates[session.id] = .modelUnavailable
        } catch TranscriptionError.audioFileNotFound {
            transcriptionStates[session.id] = .failed("Audio file not found")
        } catch TranscriptionError.transcriptionFailed(let message) {
            transcriptionStates[session.id] = .failed(message)
        } catch {
            transcriptionStates[session.id] = .failed(error.localizedDescription)
        }
        transcribingIDs.remove(session.id)
    }

    func transcriptionState(for id: UUID) -> TranscriptionState {
        transcriptionStates[id] ?? .idle
    }

    // MARK: - Summarization (OpenRouter, automatic after transcription)

    func summarizationState(for id: UUID) -> SummarizationState {
        summarizationStates[id] ?? .idle
    }

    /// Whether an OpenRouter API key is configured in the Keychain.
    var hasSummarizationKey: Bool { keychainStore.hasValue }

    /// Runs summarization automatically once a transcript exists, if the user has
    /// enabled it and supplied an API key.
    private func autoSummarizeIfNeeded(_ session: MeetingSession) {
        guard summarizationSettingsStore.load().autoSummarize else { return }
        guard !session.transcriptSegments.isEmpty else { return }
        guard keychainStore.hasValue else {
            summarizationStates[session.id] = .noAPIKey
            return
        }
        Task { await summarize(session) }
    }

    /// Re-runs summarization from the user's "Summarize" / "Summarize again" button.
    func summarizeSelected() {
        guard let session = selectedSession else { return }
        Task { await summarize(session) }
    }

    func summarize(_ session: MeetingSession) async {
        guard !summarizingIDs.contains(session.id) else { return }

        guard let apiKey = keychainStore.read(), !apiKey.isEmpty else {
            summarizationStates[session.id] = .noAPIKey
            return
        }
        let settings = summarizationSettingsStore.load()
        let templates = summaryTemplateStore.load()
        let template = templates.first { $0.id == settings.activeTemplateID } ?? templates.first
        guard let template else {
            summarizationStates[session.id] = .failed("No summary template configured")
            return
        }

        summarizingIDs.insert(session.id)
        summarizationStates[session.id] = .summarizing

        // Reload the freshest copy so concurrent edits are not clobbered.
        let latest = (try? store.load(id: session.id)) ?? session
        do {
            let summary = try await summarizationService.summarize(
                session: latest,
                template: template,
                modelSlug: settings.selectedModelSlug,
                apiKey: apiKey
            )
            var updated = latest
            updated.summary = summary
            try? store.save(updated)
            regenerateNote(for: updated)
            applyUpdatedSession(updated)
            summarizationStates[session.id] = .completed
        } catch {
            summarizationStates[session.id] = .failed(Self.summarizationErrorMessage(error))
        }
        summarizingIDs.remove(session.id)
    }

    private static func summarizationErrorMessage(_ error: Error) -> String {
        guard let error = error as? OpenRouterError else {
            return error.localizedDescription
        }
        switch error {
        case .missingAPIKey:
            return "No OpenRouter API key configured"
        case .unauthorized:
            return "Invalid OpenRouter API key"
        case .paymentRequired:
            return "OpenRouter account is out of credits"
        case .rateLimited:
            return "Rate limited by OpenRouter — try again shortly"
        case .server(let code):
            return "OpenRouter server error (\(code))"
        case .http(let code):
            return "OpenRouter request failed (HTTP \(code))"
        case .invalidResponse:
            return "OpenRouter returned an unexpected response — check the model slug"
        case .transport(let message):
            return "Network error: \(message)"
        }
    }

    // MARK: - Notes

    /// Writes note.md without opening it (used after summarization updates it).
    private func regenerateNote(for session: MeetingSession) {
        let markdown = MarkdownNoteRenderer.render(session: session)
        let noteURL = store.sessionURL(for: session).appendingPathComponent("note.md")
        try? markdown.write(to: noteURL, atomically: true, encoding: .utf8)
    }

    func openNote(for session: MeetingSession) {
        let markdown = MarkdownNoteRenderer.render(session: session)
        let noteURL = store.sessionURL(for: session).appendingPathComponent("note.md")
        try? markdown.write(to: noteURL, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(noteURL)
    }

    func openRecordingsFolder() {
        let folder = store.baseURL
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    // MARK: - Calendar

    @objc private func handleCalendarAccessGranted() {
        if calendarAdapter == nil {
            calendarAdapter = EventKitCalendarAdapter()
        }
        calendarAuthorized = calendarAdapter?.hasAccess ?? false
        Task {
            await refreshNextMeeting()
            await loadUpcomingEvents()
        }
    }

    private func ensureCalendarAdapter() -> (any CalendarAdapter)? {
        if calendarAdapter == nil {
            calendarAdapter = EventKitCalendarAdapter()
        }
        calendarAuthorized = calendarAdapter?.hasAccess ?? false
        return calendarAdapter
    }

    /// Fetches events from now to seven days out for the Calendar tab.
    func loadUpcomingEvents() async {
        isCalendarLoading = true
        calendarError = nil
        defer { isCalendarLoading = false }

        guard let adapter = ensureCalendarAdapter(), adapter.hasAccess else {
            upcomingEvents = []
            return
        }
        do {
            let now = Date()
            let events = try await adapter.fetchUpcomingEvents(
                from: now, to: now.addingTimeInterval(7 * 86_400)
            )
            upcomingEvents = events.sorted { $0.startDate < $1.startDate }
        } catch {
            calendarError = "Calendar unavailable"
            upcomingEvents = []
        }
    }

    /// Links a calendar event to a session, copying the event's attendees into the
    /// session's participants, and persists.
    func linkEvent(_ event: CalendarEvent, to session: MeetingSession) {
        var updated = session
        updated.linkedEventID = event.id
        updated.linkedEventTitle = event.title
        updated.participants = event.attendees
        persist(updated)
        regenerateNote(for: updated)
    }

    /// Removes a previously-linked event from a session.
    func unlinkEvent(from session: MeetingSession) {
        var updated = session
        updated.linkedEventID = nil
        updated.linkedEventTitle = nil
        updated.participants = []
        persist(updated)
        regenerateNote(for: updated)
    }

    /// Events near the session's date, for the link picker (±2 hours).
    func eventsNear(_ date: Date, window: TimeInterval = 2 * 3_600) -> [CalendarEvent] {
        upcomingEvents.filter { abs($0.startDate.timeIntervalSince(date)) <= window }
    }

    @objc private func handleStartRecordingFromNotification() {
        Task { @MainActor in
            guard !recordingManager.isRecording else { return }
            await startRecording(title: nextMeeting?.title ?? "Meeting Recording")
        }
    }

    func refreshNextMeeting() async {
        isCalendarLoading = true
        calendarError = nil
        defer { isCalendarLoading = false }

        guard let adapter = calendarAdapter, adapter.hasAccess else {
            nextMeeting = nil
            calendarError = nil
            return
        }
        do {
            let now = Date()
            let events = try await adapter.fetchUpcomingEvents(from: now, to: now.addingTimeInterval(86_400))
            if let top = MeetingDetector.nextMeeting(from: events, after: now) {
                nextMeeting = top.event
                notificationScheduler.scheduleReminder(for: top.event)
            } else {
                nextMeeting = nil
            }
        } catch {
            calendarError = "Calendar unavailable"
        }
    }
}
