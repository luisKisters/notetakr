import AppKit
import AVFoundation
import NoteTakrKit
import NoteTakrCore
import os

/// Single shared source of truth for the app: owns the session store, recorder,
/// transcription pipeline, and calendar state.
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
    let appSettings: AppSettingsStore
    let keychainStore: KeychainStore
    private let summarizationService = SummarizationService()

    private let runtime = FluidAudioRuntime()
    private let audioLoader = FluidAudioSampleLoader()
    private let diarizer = OfflineDiarizationRuntime()
    private let booster = FluidAudioVocabularyBooster()
    private let notificationScheduler = MeetingNotificationScheduler()
    private var calendarAdapter: (any CalendarAdapter)?

    // Published pipeline state
    @Published private(set) var isRecording = false
    /// Set when starting/stopping a recording fails (e.g. mic permission denied);
    /// cleared on the next start attempt. The panel controller shows this to the user.
    @Published private(set) var recordingError: String?
    @Published private(set) var transcriptionStates: [UUID: TranscriptionState] = [:]
    @Published private(set) var summarizationStates: [UUID: SummarizationState] = [:]
    @Published private(set) var nextMeeting: CalendarEvent?
    @Published private(set) var upcomingEvents: [CalendarEvent] = []
    @Published private(set) var isCalendarLoading = false
    @Published private(set) var calendarError: String?
    @Published private(set) var calendarAuthorized = false

    private var transcribingIDs: Set<UUID> = []
    private var summarizingIDs: Set<UUID> = []

    /// Called when recording starts; argument is the session ID string.
    var onRecordingStarted: ((String) -> Void)?
    /// Called when recording stops; argument is the session ID string (nil on error).
    var onRecordingStopped: ((String?) -> Void)?

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
        appSettings = AppSettingsStore(root: base.appendingPathComponent("NoteTakr"))
        keychainStore = KeychainStore()
        recordingManager = RecordingManager(store: store, recorder: NativeAudioRecorder())

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleStartRecordingFromNotification),
            name: .meetingNotificationStartRecording, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCalendarAccessGranted),
            name: .noteTakrCalendarAccessGranted, object: nil
        )
    }

    // MARK: - Recording

    /// Microphone authorization, requesting it on first use. Returns true only when
    /// recording can actually capture audio — the gate that prevents "records nothing".
    func ensureMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            // Shows the system prompt and awaits the user's choice.
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func startRecording(title: String? = nil) async {
        guard !recordingManager.isRecording else { return }
        recordingError = nil

        // Gate on microphone permission BEFORE creating a session — otherwise the
        // recorder silently captures nothing and the note ends up with no audio.
        guard await ensureMicrophonePermission() else {
            recordingError = "Microphone access is required to record. Turn it on for "
                + "NoteTakr in System Settings → Privacy & Security → Microphone."
            FluidAudioAdapter.log.error("recording blocked: microphone permission not granted")
            return  // isRecording stays false → caller resets the pill + shows the alert
        }

        let name = title ?? nextMeeting?.title ?? "Meeting Recording"
        do {
            let session = try await recordingManager.startRecording(title: name)
            isRecording = true
            onRecordingStarted?(session.id.uuidString)
        } catch {
            isRecording = recordingManager.isRecording
            // Surface the failure — swallowing it leaves the pill "recording" nothing
            // (the classic cause: mic permission lost after an unsigned rebuild).
            let message = (error as? AudioRecorderError).map(Self.recorderErrorMessage)
                ?? error.localizedDescription
            recordingError = message
            FluidAudioAdapter.log.error("recording START failed: \(message, privacy: .public)")
        }
    }

    func quickRecording() async {
        await startRecording(title: "Quick Recording")
    }

    func stopRecording() async {
        guard recordingManager.isRecording else { return }
        let stopped: MeetingSession?
        do {
            stopped = try await recordingManager.stopRecording()
        } catch {
            stopped = nil
            recordingError = error.localizedDescription
            FluidAudioAdapter.log.error("recording STOP failed: \(String(describing: error), privacy: .public)")
        }
        isRecording = false
        onRecordingStopped?(stopped?.id.uuidString)
    }

    private static func recorderErrorMessage(_ error: AudioRecorderError) -> String {
        switch error {
        case .alreadyRecording:
            return "A recording is already in progress."
        case .notRecording:
            return "No recording is in progress."
        case .recordingFailed(let reason):
            return reason
        }
    }

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    // MARK: - Transcription (called by TranscriptionRequestingAdapter)

    /// Transcribes a session by ID with explicit vocabulary, returns raw segments.
    /// Also triggers auto-summarize if enabled.
    func transcribeForRecordingBridge(noteID: String, vocabulary: [String]) async throws -> [TranscriptSegment] {
        FluidAudioAdapter.log.info("transcribe requested for note \(noteID, privacy: .public)")
        guard let uuid = UUID(uuidString: noteID) else {
            FluidAudioAdapter.log.error("invalid note id \(noteID, privacy: .public)")
            throw TranscriptionError.audioFileNotFound
        }
        guard !transcribingIDs.contains(uuid) else {
            FluidAudioAdapter.log.error("already transcribing \(noteID, privacy: .public)")
            throw TranscriptionError.transcriptionFailed("Already transcribing this session")
        }
        guard let latest = try? store.load(id: uuid) else {
            FluidAudioAdapter.log.error("could not load session \(noteID, privacy: .public)")
            throw TranscriptionError.audioFileNotFound
        }
        FluidAudioAdapter.log.info("session loaded: \(latest.audioFilePaths.count) audio file(s)")

        let vocabEntries = vocabulary.map { VocabularyEntry(phrase: $0) }
        transcribingIDs.insert(uuid)
        transcriptionStates[uuid] = .transcribing
        defer { transcribingIDs.remove(uuid) }

        let engine = FluidAudioAdapter(
            settingsStore: transcriptionSettingsStore,
            runtime: runtime,
            audioLoader: audioLoader,
            diarizer: diarizer,
            booster: booster
        )
        let service = TranscriptionService(engine: engine, store: store)

        do {
            let updated = try await service.transcribe(session: latest, vocabulary: vocabEntries)
            transcriptionStates[uuid] = .completed
            FluidAudioAdapter.log.info("transcription COMPLETED for \(noteID, privacy: .public): \(updated.transcriptSegments.count) segment(s)")
            regenerateNote(for: updated)
            autoSummarizeIfNeeded(updated)
            return updated.transcriptSegments
        } catch TranscriptionError.modelUnavailable {
            transcriptionStates[uuid] = .modelUnavailable
            // Re-throw as a `transcriptionFailed` carrying a friendly message: the recording
            // bridge surfaces `error.localizedDescription` into the Transcript tab, and bare
            // `TranscriptionError.modelUnavailable` has no LocalizedError text (it would read
            // "modelUnavailable"). This makes the failure legible instead of a silent/cryptic state.
            throw TranscriptionError.transcriptionFailed(Self.transcriptionErrorMessage(.modelUnavailable))
        } catch TranscriptionError.audioFileNotFound {
            transcriptionStates[uuid] = .failed("Audio file not found")
            FluidAudioAdapter.log.error("transcription FAILED for \(noteID, privacy: .public): no usable audio files")
            throw TranscriptionError.transcriptionFailed(
                "No audio found for this note — the recording files are missing or empty."
            )
        } catch TranscriptionError.transcriptionFailed(let message) {
            transcriptionStates[uuid] = .failed(message)
            throw TranscriptionError.transcriptionFailed(message)
        } catch {
            transcriptionStates[uuid] = .failed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Summarization

    var hasSummarizationKey: Bool { keychainStore.hasValue }

    private func autoSummarizeIfNeeded(_ session: MeetingSession) {
        guard summarizationSettingsStore.load().autoSummarize else { return }
        guard !session.transcriptSegments.isEmpty else { return }
        // Do NOT probe the keychain here — that would call `SecItemCopyMatching` (and risk a
        // keychain prompt) on every transcription completion, even when no summary is wanted.
        // `summarize(_:)` reads the key only after the user opted into auto-summarize and sets
        // `.noAPIKey` if it's missing, so the access stays behind an explicit user choice.
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

        let latest = (try? store.load(id: session.id)) ?? session
        do {
            let yourName = appSettings.yourName
            let summary = try await summarizationService.summarize(
                session: latest,
                template: template,
                modelSlug: settings.selectedModelSlug,
                apiKey: apiKey,
                userName: yourName.isEmpty ? nil : yourName
            )
            var updated = latest
            updated.summary = summary
            try? store.save(updated)
            regenerateNote(for: updated)
            summarizationStates[session.id] = .completed
        } catch {
            summarizationStates[session.id] = .failed(Self.summarizationErrorMessage(error))
        }
        summarizingIDs.remove(session.id)
    }

    /// Maps a transcription error to a user-facing message for the Transcript tab.
    private static func transcriptionErrorMessage(_ error: TranscriptionError) -> String {
        switch error {
        case .modelUnavailable:
            return "Speech model not downloaded. Open Settings › Transcription Model to set it up."
        case .audioFileNotFound:
            return "Audio file not found for this recording."
        case .transcriptionFailed(let message):
            return message
        }
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

    /// Writes note.md without opening it (used after transcription/summarization updates it).
    private func regenerateNote(for session: MeetingSession) {
        let markdown = MarkdownNoteRenderer.render(session: session)
        let noteURL = store.sessionURL(for: session).appendingPathComponent("note.md")
        try? markdown.write(to: noteURL, atomically: true, encoding: .utf8)
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
