import AppKit
import AVFoundation
import NoteTakrKit
import NoteTakrCore
import NoteTakrSync
import os

private typealias AppSyncBackend = SyncBackend & SyncAccountControlling

/// Single shared source of truth for the app: owns the session store, recorder,
/// transcription pipeline, and calendar state.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // Stores / services
    let store: SessionStore
    let noteStore: NoteStore
    let recordingManager: RecordingManager
    let vocabularyStore: VocabularyStore
    let transcriptionSettingsStore: TranscriptionSettingsStore
    let summaryTemplateStore: SummaryTemplateStore
    let summarizationSettingsStore: SummarizationSettingsStore
    let appSettings: AppSettingsStore
    let keychainStore: KeychainStore
    let crmKeychainStore: KeychainStore
    let crmPeopleCacheSource: ConvexPeopleCacheSource
    private let summarizationService = SummarizationService()
    private var syncBackend: (any AppSyncBackend)?
    private var syncService: SyncService?
    private var syncRunTask: Task<Void, Never>?
    private var syncAccountTask: Task<Void, Never>?
    private var syncedSummaryWaiters: [String: [SyncedSummaryWaiter]] = [:]
    private var syncedSummaryContentHashes: [String: String] = [:]
    private var crmConnectionVerified = false

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
    @Published private(set) var calendarEventWindow: EventPickerWindow?
    @Published private(set) var isCalendarLoading = false
    @Published private(set) var calendarError: String?
    @Published private(set) var calendarAuthorized = false
    @Published private(set) var syncAccountState: AccountState = .signedOut
    @Published private(set) var syncAccountMessage: String?
    @Published private(set) var syncSummaryStates: [String: SummaryState] = [:]
    @Published private(set) var crmConnected: Bool = false
    @Published private(set) var crmAPIKeyConfigured: Bool = false
    @Published private(set) var crmMessage: String?
    @Published private(set) var crmPeopleCacheRevision: Int = 0
    @Published private(set) var crmPushStatuses: [String: CrmPushStatus] = [:]

    private var transcribingIDs: Set<UUID> = []
    private var summarizingIDs: Set<UUID> = []
    private var recordingActivity: NSObjectProtocol?
    private static let cloudSummaryTimeoutNanoseconds: UInt64 = 120_000_000_000

    private struct SyncedSummaryWaiter {
        var contentHash: String?
        var continuation: CheckedContinuation<String, Error>
    }

    /// Called when recording starts; argument is the session ID string.
    var onRecordingStarted: ((String) -> Void)?
    /// Called when recording stops; argument is the session ID string (nil on error).
    var onRecordingStopped: ((String?) -> Void)?

    init() {
        let base = Self.applicationSupportBaseURL()
        let sessionsDir = base.appendingPathComponent("NoteTakr/Sessions", isDirectory: true)
        store = SessionStore(baseURL: sessionsDir)
        noteStore = NoteStore(root: sessionsDir)
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
        crmKeychainStore = KeychainStore(service: "com.notetakr.crm.twenty", account: "api-key")
        crmPeopleCacheSource = ConvexPeopleCacheSource(rootURL: base)
        recordingManager = RecordingManager(store: store, recorder: Self.makeAudioRecorder())
        configureSync(rootURL: base)
        refreshCrmConnectionState()

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleStartRecordingFromNotification),
            name: .meetingNotificationStartRecording, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCalendarAccessGranted),
            name: .noteTakrCalendarAccessGranted, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleContactsAccessGranted),
            name: .noteTakrContactsAccessGranted, object: nil
        )
    }

    private static func applicationSupportBaseURL() -> URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["NOTETAKR_E2E_APP_SUPPORT_ROOT"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif

        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
    }

    private static var usesE2EMockRecorder: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["NOTETAKR_E2E_USE_MOCK_RECORDER"] == "1"
        #else
        false
        #endif
    }

    private static var usesE2EMockCrmConnected: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["NOTETAKR_E2E_MOCK_CRM_CONNECTED"] == "1"
        #else
        false
        #endif
    }

    private static func makeAudioRecorder() -> any AudioRecorder {
        #if DEBUG
        if usesE2EMockRecorder {
            return MockAudioRecorder()
        }
        #endif
        return NativeAudioRecorder()
    }

    // MARK: - Sync

    private func configureSync(rootURL: URL) {
        let backend = Self.makeSyncBackend(rootURL: rootURL)
        let outbox = SyncOutbox(rootURL: rootURL)
        let sessionStore = store
        let notes = noteStore

        syncBackend = backend
        syncAccountState = backend.accountState

        let service = SyncService(
            backend: backend,
            outbox: outbox,
            loadSession: { localId in
                guard let uuid = UUID(uuidString: localId) else { return nil }
                return try sessionStore.load(id: uuid)
            },
            loadNote: { localId in
                try notes.load(id: localId)
            },
            persistSummary: { [weak self, sessionStore, notes] localId, text, contentHash in
                guard let uuid = UUID(uuidString: localId),
                      var session = try sessionStore.load(id: uuid) else { return }
                let currentContentHash = Self.currentSyncContentHash(
                    session: session,
                    noteStore: notes
                )
                if let contentHash,
                   let currentContentHash,
                   contentHash != currentContentHash {
                    return
                }
                let summaryContentHash = contentHash ?? currentContentHash
                session.summary = text
                session.summaryContentHash = summaryContentHash
                try sessionStore.save(session)
                Task { @MainActor [weak self] in
                    self?.handleSyncedSummary(
                        localId: localId,
                        text: text,
                        contentHash: summaryContentHash
                    )
                }
            },
            persistSummaryFailure: { [weak self] localId, message, contentHash in
                Task { @MainActor [weak self] in
                    self?.handleSyncedSummaryFailure(
                        localId: localId,
                        message: message,
                        contentHash: contentHash
                    )
                }
            },
            persistCrmPushStatus: { [weak self, notes] localId, status in
                guard var note = try notes.load(id: localId) else { return }
                note.crmPushStatus = status
                try notes.save(note)
                Task { @MainActor [weak self] in
                    self?.handleCrmPushStatus(localId: localId, status: status)
                }
            },
            peopleCacheSource: crmPeopleCacheSource,
            peopleCacheDidRefresh: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.crmPeopleCacheRevision &+= 1
                }
            }
        )
        syncService = service

        recordingManager.markDirty = { [weak self] localId in
            Task { @MainActor [weak self] in
                self?.markSyncDirty(localId: localId)
            }
        }

        syncRunTask = Task {
            await service.run()
        }
        syncAccountTask = Task { [weak self, backend] in
            for await state in backend.accountStateUpdates() {
                await MainActor.run {
                    self?.syncAccountState = state
                    if state.isSignedIn {
                        self?.syncAccountMessage = nil
                        service.resetPeopleCacheRefreshThrottle()
                        service.startSummaryUpdatesIfNeeded()
                    } else {
                        service.cancelSummaryUpdates()
                        service.resetPeopleCacheRefreshThrottle()
                        self?.syncSummaryStates.removeAll()
                        self?.syncedSummaryContentHashes.removeAll()
                        try? self?.crmPeopleCacheSource.refresh(people: [])
                        self?.crmPeopleCacheRevision &+= 1
                        self?.resumeSyncedSummaryWaiters(throwing: CloudSummaryError.unavailable)
                        self?.crmConnectionVerified = false
                    }
                    self?.refreshCrmConnectionState()
                }
                if state.isSignedIn {
                    await service.runOnce()
                    await self?.refreshCrmConnectionStateFromServer()
                }
            }
        }
    }

    @MainActor
    private static func makeSyncBackend(rootURL: URL) -> any AppSyncBackend {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["NOTETAKR_E2E_MOCK_SYNC_BACKEND"] == "1" {
            let spoolRoot = env["NOTETAKR_E2E_SYNC_SPOOL_ROOT"].flatMap { value -> URL? in
                guard !value.isEmpty else { return nil }
                return URL(fileURLWithPath: value, isDirectory: true)
            } ?? rootURL
                .appendingPathComponent("NoteTakr", isDirectory: true)
                .appendingPathComponent("MockSyncBackend", isDirectory: true)
            return FileSpoolSyncBackend(rootURL: spoolRoot)
        }
        #endif

        guard let configuration = syncConfiguration() else {
            return UnavailableSyncBackend(
                missingConfiguration: [
                    "CONVEX_DEPLOYMENT_URL or NOTETAKR_CONVEX_DEPLOYMENT_URL",
                    "CLERK_PUBLISHABLE_KEY or NOTETAKR_CLERK_PUBLISHABLE_KEY",
                ]
            )
        }
        return ConvexSyncBackend(configuration: configuration)
    }

    private static func syncConfiguration() -> ConvexSyncConfiguration? {
        let env = ProcessInfo.processInfo.environment
        guard let deployment = firstNonEmpty(
            env["NOTETAKR_CONVEX_DEPLOYMENT_URL"],
            env["CONVEX_DEPLOYMENT_URL"],
            env["CONVEX_URL"],
            Bundle.main.object(forInfoDictionaryKey: "NOTETAKR_CONVEX_DEPLOYMENT_URL") as? String
        ),
              let deploymentURL = URL(string: deployment),
              deploymentURL.scheme?.hasPrefix("http") == true,
              let clerkKey = firstNonEmpty(
                  env["NOTETAKR_CLERK_PUBLISHABLE_KEY"],
                  env["CLERK_PUBLISHABLE_KEY"],
                  Bundle.main.object(forInfoDictionaryKey: "NOTETAKR_CLERK_PUBLISHABLE_KEY") as? String
              )
        else {
            return nil
        }
        let callbackScheme = firstNonEmpty(Bundle.main.bundleIdentifier) ?? "notetakr"
        return ConvexSyncConfiguration(
            deploymentURL: deploymentURL.absoluteString,
            clerkPublishableKey: clerkKey,
            callbackURLScheme: callbackScheme
        )
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var hasCloudSummaryBackend: Bool {
        syncAccountState.isSignedIn
    }

    func canUseCloudSummary(for noteID: String) -> Bool {
        guard syncAccountState.isSignedIn else { return false }
        guard let uuid = UUID(uuidString: noteID) else { return false }
        guard let session = try? store.load(id: uuid),
              let note = try? noteStore.load(id: noteID) else {
            return false
        }
        return (note.localOnly ?? session.localOnly) != true
    }

    @discardableResult
    func markSyncDirty(localId: String) -> Bool {
        guard let syncService else { return false }
        do {
            let canUseCloud = canUseCloudSummary(for: localId)
            if !canUseCloud {
                syncSummaryStates.removeValue(forKey: localId)
                syncedSummaryContentHashes.removeValue(forKey: localId)
                resumeSyncedSummaryWaiters(for: localId, throwing: CloudSummaryError.unavailable)
            }
            let didEnqueue = try syncService.markDirty(localId: localId)
            guard didEnqueue else {
                return false
            }
            if canUseCloud, hasTranscriptContent(for: localId) {
                resumeSyncedSummaryWaiters(
                    for: localId,
                    notMatching: currentSyncContentHash(for: localId),
                    throwing: CloudSummaryError.unavailable
                )
                syncSummaryStates[localId] = .generating
                syncedSummaryContentHashes.removeValue(forKey: localId)
            }
            Task { [syncService] in
                await syncService.runOnce()
            }
            return true
        } catch {
            syncAccountMessage = Self.syncErrorMessage(error)
            return false
        }
    }

    func generateServerSummary(for noteID: String) async throws -> String {
        guard canUseCloudSummary(for: noteID) else {
            throw CloudSummaryError.unavailable
        }
        guard hasTranscriptContent(for: noteID) else {
            throw CloudSummaryError.unavailable
        }
        let currentHash = currentSyncContentHash(for: noteID)
        if case .ready(let text) = syncSummaryStates[noteID],
           !text.isEmpty,
           syncedSummaryContentHashes[noteID] == currentHash {
            return text
        }
        if let uuid = UUID(uuidString: noteID),
           let session = try? store.load(id: uuid),
           let summary = session.summary,
           !summary.isEmpty,
           session.summaryContentHash == currentHash {
            syncSummaryStates[noteID] = .ready(summary)
            if let currentHash {
                syncedSummaryContentHashes[noteID] = currentHash
            }
            return summary
        }

        syncSummaryStates[noteID] = .waiting
        _ = markSyncDirty(localId: noteID)
        let service = syncService
        Task { [weak self, service] in
            await service?.runOnce()
            await MainActor.run {
                if self?.syncSummaryStates[noteID] == .waiting {
                    self?.syncSummaryStates[noteID] = .generating
                }
            }
        }
        return try await waitForSyncedSummary(noteID: noteID, contentHash: currentHash)
    }

    func signInWithGoogle() async {
        guard let syncBackend else {
            syncAccountMessage = "Cloud sync is not configured."
            return
        }
        do {
            try await syncBackend.signInWithGoogle()
            syncAccountState = syncBackend.accountState
            syncAccountMessage = nil
            await syncService?.runOnce()
            await refreshCrmConnectionStateFromServer()
        } catch {
            syncAccountMessage = Self.syncErrorMessage(error)
        }
    }

    func signOut() async {
        guard let syncBackend else { return }
        do {
            try await syncBackend.signOut()
            syncAccountState = syncBackend.accountState
            syncSummaryStates.removeAll()
            syncedSummaryContentHashes.removeAll()
            syncService?.cancelSummaryUpdates()
            resumeSyncedSummaryWaiters(throwing: CloudSummaryError.unavailable)
            crmConnectionVerified = false
            refreshCrmConnectionState(forceConnected: false)
            syncAccountMessage = nil
        } catch {
            syncAccountMessage = Self.syncErrorMessage(error)
        }
    }

    func saveCrmSettings(baseURL: String, apiKey: String?) async {
        guard let configuration = currentCrmConfiguration(
            baseURLOverride: baseURL,
            apiKeyOverride: apiKey
        ) else {
            crmMessage = "Twenty base URL and API key are required."
            refreshCrmConnectionState()
            return
        }

        do {
            guard let manager = syncBackend as? any CrmSettingsManaging else {
                throw CrmBackendError.configuration("Cloud sync is not configured.")
            }
            try await manager.testCrmConnection(configuration)
            try await manager.saveCrmConfiguration(configuration)
            appSettings.crmTwentyBaseURL = baseURL
            if let apiKey, !apiKey.isEmpty {
                try crmKeychainStore.save(apiKey)
            }
            await refreshCrmConnectionStateFromServer()
            crmMessage = "CRM settings saved."
        } catch {
            crmMessage = Self.syncErrorMessage(error)
            await refreshCrmConnectionStateFromServer()
            return
        }
    }

    func testCrmConnection(baseURL: String, apiKey: String?) async {
        guard let configuration = currentCrmConfiguration(
            baseURLOverride: baseURL,
            apiKeyOverride: apiKey
        ) else {
            crmMessage = "Twenty base URL and API key are required."
            refreshCrmConnectionState()
            return
        }

        if Self.usesE2EMockCrmConnected {
            crmMessage = "CRM connection succeeded."
            refreshCrmConnectionState()
            return
        }

        do {
            guard let manager = syncBackend as? any CrmSettingsManaging else {
                throw CrmBackendError.configuration("Cloud sync is not configured.")
            }
            try await manager.testCrmConnection(configuration)
            crmMessage = "CRM connection succeeded."
            refreshCrmConnectionState()
        } catch {
            crmMessage = Self.syncErrorMessage(error)
            refreshCrmConnectionState()
        }
    }

    func refreshCrmPeople() async {
        guard syncAccountState.isSignedIn else {
            crmMessage = "Sign in to refresh CRM people."
            refreshCrmConnectionState()
            return
        }
        do {
            guard let manager = syncBackend as? any CrmSettingsManaging else {
                throw CrmBackendError.configuration("Cloud sync is not configured.")
            }
            let people = try await manager.refreshCrmPeople()
            try crmPeopleCacheSource.refresh(people: people)
            crmPeopleCacheRevision &+= 1
            await refreshCrmConnectionStateFromServer()
            crmMessage = "CRM people refreshed."
        } catch {
            crmMessage = Self.syncErrorMessage(error)
            await refreshCrmConnectionStateFromServer()
        }
    }

    private func currentCrmConfiguration(
        baseURLOverride: String? = nil,
        apiKeyOverride: String? = nil
    ) -> CrmConfiguration? {
        let baseURL = Self.firstNonEmpty(baseURLOverride, appSettings.crmTwentyBaseURL)
        let apiKey = Self.firstNonEmpty(apiKeyOverride, crmKeychainStore.read())
        guard let baseURL, let apiKey else { return nil }
        return CrmConfiguration(provider: "twenty", baseURL: baseURL, apiKey: apiKey)
    }

    private func refreshCrmConnectionState(forceConnected: Bool? = nil) {
        crmAPIKeyConfigured = crmKeychainStore.hasValue
        let confirmed = crmConnectionVerified && syncAccountState.isSignedIn
        crmConnected = forceConnected ?? (Self.usesE2EMockCrmConnected || confirmed)
    }

    private func refreshCrmConnectionStateFromServer() async {
        guard syncAccountState.isSignedIn else {
            crmConnectionVerified = false
            refreshCrmConnectionState()
            return
        }
        guard !Self.usesE2EMockCrmConnected else {
            refreshCrmConnectionState()
            return
        }
        guard let manager = syncBackend as? any CrmSettingsManaging else {
            crmConnectionVerified = false
            refreshCrmConnectionState()
            return
        }

        do {
            crmConnectionVerified = try await manager.hasSavedCrmConfiguration()
        } catch {
            crmConnectionVerified = false
        }
        refreshCrmConnectionState()
    }

    private func hasTranscriptContent(for localId: String) -> Bool {
        guard let uuid = UUID(uuidString: localId),
              let session = try? store.load(id: uuid) else {
            return false
        }
        return !session.transcriptSegments.isEmpty
    }

    private func currentSyncContentHash(for localId: String) -> String? {
        guard let uuid = UUID(uuidString: localId),
              let session = try? store.load(id: uuid) else {
            return nil
        }
        return Self.currentSyncContentHash(session: session, noteStore: noteStore)
    }

    nonisolated private static func currentSyncContentHash(
        session: MeetingSession,
        noteStore: NoteStore
    ) -> String? {
        guard let note = try? noteStore.load(id: session.id.uuidString) else {
            return nil
        }
        return try? SyncEnvelope.payload(session: session, note: note).contentHash
    }

    private func waitForSyncedSummary(noteID: String, contentHash: String?) async throws -> String {
        if case .ready(let text) = syncSummaryStates[noteID],
           !text.isEmpty,
           syncedSummaryContentHashes[noteID] == contentHash {
            return text
        }
        if case .failed(let message) = syncSummaryStates[noteID] {
            throw CloudSummaryError.failed(message)
        }
        return try await withCheckedThrowingContinuation { continuation in
            syncedSummaryWaiters[noteID, default: []].append(
                SyncedSummaryWaiter(contentHash: contentHash, continuation: continuation)
            )
            scheduleSyncedSummaryTimeout(noteID: noteID, contentHash: contentHash)
        }
    }

    private func scheduleSyncedSummaryTimeout(noteID: String, contentHash: String?) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.cloudSummaryTimeoutNanoseconds)
            guard let self,
                  self.syncedSummaryWaiters[noteID]?.contains(where: {
                      Self.summaryContentHash($0.contentHash, matches: contentHash)
                  }) == true,
                  self.currentSyncContentHash(for: noteID) == contentHash else {
                return
            }
            self.handleSyncedSummaryFailure(
                localId: noteID,
                message: "Cloud summary generation timed out.",
                contentHash: contentHash
            )
        }
    }

    private func handleSyncedSummary(localId: String, text: String, contentHash: String?) {
        if let contentHash,
           let currentHash = currentSyncContentHash(for: localId),
           contentHash != currentHash {
            return
        }
        syncSummaryStates[localId] = .ready(text)
        if let contentHash {
            syncedSummaryContentHashes[localId] = contentHash
        }
        let waiters = syncedSummaryWaiters.removeValue(forKey: localId) ?? []
        var remaining: [SyncedSummaryWaiter] = []
        for waiter in waiters {
            if Self.summaryContentHash(waiter.contentHash, matches: contentHash) {
                waiter.continuation.resume(returning: text)
            } else {
                remaining.append(waiter)
            }
        }
        if !remaining.isEmpty {
            syncedSummaryWaiters[localId] = remaining
        }
    }

    private func handleSyncedSummaryFailure(localId: String, message: String, contentHash: String?) {
        if let contentHash,
           currentSyncContentHash(for: localId) != contentHash {
            return
        }
        syncSummaryStates[localId] = .failed(message)
        syncedSummaryContentHashes.removeValue(forKey: localId)
        let waiters = syncedSummaryWaiters.removeValue(forKey: localId) ?? []
        var remaining: [SyncedSummaryWaiter] = []
        let error = CloudSummaryError.failed(message)
        for waiter in waiters {
            if Self.summaryContentHash(waiter.contentHash, matches: contentHash) {
                waiter.continuation.resume(throwing: error)
            } else {
                remaining.append(waiter)
            }
        }
        if !remaining.isEmpty {
            syncedSummaryWaiters[localId] = remaining
        }
    }

    private func handleCrmPushStatus(localId: String, status: CrmPushStatus) {
        crmPushStatuses[localId] = status
    }

    private func resumeSyncedSummaryWaiters(throwing error: Error) {
        let waiters = syncedSummaryWaiters
        syncedSummaryWaiters.removeAll()
        for noteWaiters in waiters.values {
            for waiter in noteWaiters {
                waiter.continuation.resume(throwing: error)
            }
        }
    }

    private func resumeSyncedSummaryWaiters(for localId: String, throwing error: Error) {
        let waiters = syncedSummaryWaiters.removeValue(forKey: localId) ?? []
        for waiter in waiters {
            waiter.continuation.resume(throwing: error)
        }
    }

    private func resumeSyncedSummaryWaiters(
        for localId: String,
        notMatching contentHash: String?,
        throwing error: Error
    ) {
        let waiters = syncedSummaryWaiters.removeValue(forKey: localId) ?? []
        var remaining: [SyncedSummaryWaiter] = []
        for waiter in waiters {
            if waiter.contentHash == contentHash {
                remaining.append(waiter)
            } else {
                waiter.continuation.resume(throwing: error)
            }
        }
        if !remaining.isEmpty {
            syncedSummaryWaiters[localId] = remaining
        }
    }

    private static func summaryContentHash(_ waiterHash: String?, matches updateHash: String?) -> Bool {
        guard let updateHash else { return true }
        return waiterHash == nil || waiterHash == updateHash
    }

    private static func syncErrorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private enum CloudSummaryError: LocalizedError {
        case unavailable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Cloud summaries are unavailable for this meeting."
            case .failed(let message):
                return message
            }
        }
    }

    // MARK: - Recording

    /// Read-only permission preflight. Recording start never triggers an OS prompt;
    /// users grant access deliberately from NoteTakr's Permissions settings.
    private func validateRequiredAudioPermissions(for options: AudioRecordingOptions) -> Bool {
        #if DEBUG
        if Self.usesE2EMockRecorder {
            return true
        }
        #endif

        let microphoneStatus: PermissionStatus
        if options.microphoneEnabled {
            microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                ? .granted
                : .denied
        } else {
            microphoneStatus = .granted
        }

        let systemAudioStatus: PermissionStatus
        if options.systemAudioEnabled {
            systemAudioStatus = CGPreflightScreenCaptureAccess() ? .granted : .denied
        } else {
            // Mic-only/in-person recordings must not ask for screen capture access.
            systemAudioStatus = .granted
        }

        switch AudioRecordingPermissionGate.failure(
            for: options,
            microphoneStatus: microphoneStatus,
            systemAudioStatus: systemAudioStatus
        ) {
        case .microphone:
            recordingError = "Microphone access is required to record. Turn it on for "
                + "NoteTakr in System Settings → Privacy & Security → Microphone."
            FluidAudioAdapter.log.error("recording blocked: microphone permission not granted")
            return false
        case .systemAudio:
            recordingError = "Screen & System Audio Recording access is required for online meetings. "
                + "Turn it on for NoteTakr in System Settings → Privacy & Security, then restart NoteTakr. "
                + "Or mark this as an in-person meeting to record microphone audio only."
            FluidAudioAdapter.log.error("recording blocked: screen/system audio permission not granted")
            return false
        case nil:
            return true
        }
    }

    func startRecording(title: String? = nil) async {
        guard !recordingManager.isRecording else { return }
        recordingError = nil
        let inPerson = appSettings.inPersonByDefault
        let options = audioOptions(inPerson: inPerson)

        guard options.microphoneEnabled || options.systemAudioEnabled else {
            recordingError = "Turn on at least one audio source before recording."
            return
        }

        guard validateRequiredAudioPermissions(for: options) else {
            return  // isRecording stays false → caller resets the pill + shows the alert
        }

        let name = title ?? nextMeeting?.title ?? "Meeting Recording"
        do {
            beginRecordingActivity()
            var pendingSession = MeetingSession(
                title: name,
                date: Date(),
                inPerson: inPerson,
                microphoneEnabled: options.microphoneEnabled,
                systemAudioEnabled: options.systemAudioEnabled
            )
            pendingSession.localOnly = appSettings.localOnlyByDefault ? true : nil
            let session = try await recordingManager.startRecording(session: pendingSession)
            isRecording = true
            onRecordingStarted?(session.id.uuidString)
        } catch {
            endRecordingActivity()
            isRecording = recordingManager.isRecording
            // Surface the failure — swallowing it leaves the pill "recording" nothing
            // (the classic cause: mic permission lost after an unsigned rebuild).
            let message = (error as? AudioRecorderError).map(Self.recorderErrorMessage)
                ?? error.localizedDescription
            recordingError = message
            FluidAudioAdapter.log.error("recording START failed: \(message, privacy: .public)")
        }
    }

    @discardableResult
    func startRecording(for note: MeetingNote) async -> Bool {
        NSLog("NoteTakr recording start requested for note \(note.id)")
        guard !recordingManager.isRecording else { return true }
        recordingError = nil
        let inPerson = effectiveInPerson(for: note)
        let options = audioOptions(inPerson: inPerson)

        guard options.microphoneEnabled || options.systemAudioEnabled else {
            recordingError = "Turn on at least one audio source before recording."
            NSLog("NoteTakr recording start blocked: no enabled audio sources")
            return false
        }

        guard validateRequiredAudioPermissions(for: options) else {
            NSLog("NoteTakr recording start blocked: required audio permission missing")
            return false
        }

        guard let session = sessionForRecording(note: note, options: options) else {
            NSLog("NoteTakr recording start blocked: invalid note id \(note.id)")
            return false
        }

        do {
            beginRecordingActivity()
            NSLog("NoteTakr recording manager start begin for session \(session.id.uuidString)")
            let started = try await recordingManager.startRecording(session: session)
            NSLog("NoteTakr recording manager start returned for session \(started.id.uuidString)")
            isRecording = true
            onRecordingStarted?(started.id.uuidString)
            NSLog("NoteTakr recording started for session \(started.id.uuidString)")
            return true
        } catch {
            endRecordingActivity()
            isRecording = recordingManager.isRecording
            let message = (error as? AudioRecorderError).map(Self.recorderErrorMessage)
                ?? error.localizedDescription
            recordingError = message
            FluidAudioAdapter.log.error("recording START failed: \(message, privacy: .public)")
            NSLog("NoteTakr recording START failed: \(message)")
            return false
        }
    }

    func quickRecording() async {
        await startRecording(title: "Quick Recording")
    }

    func stopRecording() async {
        guard recordingManager.isRecording else { return }
        let stopped: MeetingSession?
        defer { endRecordingActivity() }
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

    /// Applies an in-person change to an active recording without stopping it.
    /// Turning in-person on disables desktop audio immediately; turning it off
    /// resumes desktop capture when the configured source and permission allow it.
    @discardableResult
    func updateActiveRecordingInPerson(_ inPerson: Bool) async -> Bool {
        guard recordingManager.isRecording else { return true }
        recordingError = nil
        let options = audioOptions(inPerson: inPerson)
        guard validateRequiredAudioPermissions(for: options) else { return false }

        do {
            _ = try await recordingManager.updateActiveRecording(
                inPerson: inPerson,
                options: options
            )
            return true
        } catch {
            let message = (error as? AudioRecorderError).map(Self.recorderErrorMessage)
                ?? error.localizedDescription
            recordingError = message
            FluidAudioAdapter.log.error(
                "recording source update failed: \(message, privacy: .public)"
            )
            return false
        }
    }

    func renameSpeaker(noteID: String, from oldName: String, to newName: String) {
        guard let uuid = UUID(uuidString: noteID) else { return }
        guard let updated = try? store.renameSpeaker(in: uuid, from: oldName, to: newName) else { return }
        regenerateNote(for: updated)
        markSyncDirty(localId: noteID)
    }

    private func beginRecordingActivity() {
        guard recordingActivity == nil else { return }
        recordingActivity = ProcessInfo.processInfo.beginActivity(
            options: [
                .userInitiated,
                .idleSystemSleepDisabled,
                .suddenTerminationDisabled,
                .automaticTerminationDisabled
            ],
            reason: "Recording audio"
        )
    }

    private func endRecordingActivity() {
        guard let activity = recordingActivity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        recordingActivity = nil
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

    private func sessionForRecording(
        note: MeetingNote,
        options: AudioRecordingOptions? = nil
    ) -> MeetingSession? {
        guard let uuid = UUID(uuidString: note.id) else {
            recordingError = "This note cannot be recorded because it has an invalid ID."
            return nil
        }

        var session = (try? store.load(id: uuid)) ?? MeetingSession(
            id: uuid,
            title: note.title,
            date: note.date
        )
        session.title = note.title.isEmpty ? "Meeting Recording" : note.title
        session.date = note.date
        session.linkedEventID = note.calendarEvent
        session.linkedEventTitle = note.calendarEvent == nil ? nil : note.title
        session.participants = note.participants.map {
            NoteTakrCore.Participant(name: $0.name, email: $0.email, crm: $0.crm)
        }
        let inPerson = effectiveInPerson(for: note)
        let options = options ?? audioOptions(inPerson: inPerson)
        session.inPerson = inPerson
        session.microphoneEnabled = options.microphoneEnabled
        session.systemAudioEnabled = options.systemAudioEnabled
        session.personalNotes = note.body
        session.localOnly = note.localOnly ?? (appSettings.localOnlyByDefault ? true : nil)
        return session
    }

    private func effectiveInPerson(for note: MeetingNote) -> Bool {
        EffectiveMeetingSettings.resolve(note: note, defaults: appSettings, globalVocabulary: []).inPerson
    }

    private func audioOptions(inPerson: Bool) -> AudioRecordingOptions {
        AudioRecordingOptions(
            microphoneEnabled: appSettings.micEnabled,
            systemAudioEnabled: appSettings.systemAudioEnabled && !inPerson
        )
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
        let service = TranscriptionService(
            engine: engine,
            store: store,
            markDirty: { [weak self] localId in
                Task { @MainActor [weak self] in
                    self?.markSyncDirty(localId: localId)
                }
            }
        )

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
        let noteID = session.id.uuidString
        if canUseCloudSummary(for: noteID) {
            Task { [weak self] in
                guard let self else { return }
                do {
                    _ = try await self.generateServerSummary(for: noteID)
                } catch CloudSummaryError.unavailable {
                    await self.summarize(session)
                } catch {
                    // Cloud failures are reflected in the Summary tab by the sync update path.
                }
            }
            return
        }
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

    /// Keeps session.json canonical for private editor content, then restores
    /// the generated note.md sections from that same session snapshot.
    func persistEditorChanges(_ note: MeetingNote) {
        guard let id = UUID(uuidString: note.id),
              let updated = try? store.updateEditorContent(
                id: id,
                title: note.title,
                personalNotes: note.body
              ) else { return }
        regenerateNote(for: updated)
        _ = markSyncDirty(localId: note.id)
    }

    /// Writes note.md without opening it (used after transcription/summarization updates it).
    private func regenerateNote(for session: MeetingSession) {
        Self.regenerateNote(for: session, store: store, noteStore: noteStore)
    }

    private static func regenerateNote(
        for session: MeetingSession,
        store: SessionStore,
        noteStore: NoteStore? = nil
    ) {
        let markdown = MarkdownNoteRenderer.render(session: session)
        if let noteStore,
           var note = try? noteStore.load(id: session.id.uuidString) {
            note.body = markdown
            try? noteStore.save(note)
            return
        }

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

    @objc private func handleContactsAccessGranted() {
        // Re-fetch so attendee names already visible in the UI are enriched.
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
        await loadCalendarEvents(window: EventPickerWindow.defaultWindow(now: Date()))
    }

    func loadCalendarEvents(window: EventPickerWindow) async {
        isCalendarLoading = true
        calendarError = nil
        defer { isCalendarLoading = false }

        guard let adapter = ensureCalendarAdapter(), adapter.hasAccess else {
            upcomingEvents = []
            calendarEventWindow = window
            return
        }
        do {
            let events = try await adapter.fetchUpcomingEvents(
                from: window.start,
                to: window.end
            )
            upcomingEvents = events.sorted { $0.startDate < $1.startDate }
            calendarEventWindow = window
        } catch {
            calendarError = "Calendar unavailable"
            upcomingEvents = []
            calendarEventWindow = window
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
