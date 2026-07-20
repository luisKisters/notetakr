import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

public enum RecordingManagerError: Error, Sendable, Equatable {
    case noActiveSession
    case alreadyRecording
    case recorderDoesNotSupportReconfiguration
}

public final class RecordingManager: @unchecked Sendable {
    public let store: SessionStore
    public let recorder: any AudioRecorder
    private var _activeSession: MeetingSession?
    private var _recordingStartedAt: Date?

    public var activeSession: MeetingSession? { _activeSession }
    public var isRecording: Bool { recorder.isRecording }

    public init(store: SessionStore, recorder: any AudioRecorder) {
        self.store = store
        self.recorder = recorder
    }

    /// Creates a new session in .recording state, starts the recorder, and persists the session.
    /// If the recorder fails to start, the session is saved as .failed.
    public func startRecording(title: String, date: Date = Date()) async throws -> MeetingSession {
        try await startRecording(session: MeetingSession(title: title, date: date))
    }

    /// Starts recording into an existing logical session. This lets the app bind a recording
    /// to an already-open note instead of creating a new meeting note for every start.
    public func startRecording(session input: MeetingSession) async throws -> MeetingSession {
        guard !recorder.isRecording else {
            throw RecordingManagerError.alreadyRecording
        }
        var session = input
        // In-person meetings are microphone-only. Normalize the stored session as
        // well as the options sent to the recorder so no later pipeline can revive
        // a stale desktop-audio stream from contradictory metadata.
        let options = session.audioRecordingOptions
        session.microphoneEnabled = options.microphoneEnabled
        session.systemAudioEnabled = options.systemAudioEnabled
        session.status = .recording
        session.audioFilePaths = []
        session.audioSourceStatuses = []
        let recordingStartedAt = Date()
        _recordingStartedAt = recordingStartedAt
        try store.save(session)
        let dir = store.sessionURL(for: session)
        do {
            if !options.microphoneEnabled && !options.systemAudioEnabled {
                throw AudioRecorderError.recordingFailed("No audio sources are enabled")
            }
            if let configurable = recorder as? any ConfigurableAudioRecorder {
                try await configurable.startRecording(into: dir, options: options)
            } else {
                try await recorder.startRecording(into: dir)
            }
        } catch {
            session.status = .failed
            try store.save(session)
            _recordingStartedAt = nil
            throw error
        }
        _activeSession = session
        return session
    }

    /// Stops the recorder, saves the audio file paths and per-source capture statuses, and transitions to .stopped.
    /// On recorder failure, the session is marked .failed.
    public func stopRecording() async throws -> MeetingSession {
        guard var session = _activeSession else {
            throw RecordingManagerError.noActiveSession
        }
        do {
            let reportedURLs = try await recorder.stopRecording()
            let enabledSources = session.audioRecordingOptions.enabledSources
            let recordingStartedAt = _recordingStartedAt ?? .distantPast
            let urls = Self.recoverRecordedURLs(
                for: session,
                store: store,
                returnedURLs: reportedURLs,
                enabledSources: enabledSources,
                recordingStartedAt: recordingStartedAt
            )
            let missingReasons = (recorder as? AudioCaptureReporter)?.lastMissingReasons ?? [:]
            session.audioFilePaths = urls.map { $0.path }
            session.audioSourceStatuses = await Self.deriveSourceStatuses(
                returnedURLs: urls,
                missingReasons: missingReasons
            )
            session.status = .stopped
            try store.save(session)
            let persisted = (try? store.load(id: session.id)) ?? session
            _activeSession = nil
            _recordingStartedAt = nil
            return persisted
        } catch {
            session.status = .failed
            try store.save(session)
            _activeSession = nil
            _recordingStartedAt = nil
            throw error
        }
    }

    /// Updates the capture sources and metadata of the active session without
    /// ending the recording. The recorder is changed before the session is
    /// persisted, so stored metadata never promises a source change that failed.
    public func updateActiveRecording(
        inPerson: Bool,
        options requestedOptions: AudioRecordingOptions
    ) async throws -> MeetingSession {
        guard var session = _activeSession else {
            throw RecordingManagerError.noActiveSession
        }
        guard let recorder = recorder as? any ReconfigurableAudioRecorder else {
            throw RecordingManagerError.recorderDoesNotSupportReconfiguration
        }

        let options = AudioRecordingOptions(
            microphoneEnabled: requestedOptions.microphoneEnabled,
            systemAudioEnabled: requestedOptions.systemAudioEnabled && !inPerson
        )
        guard options.microphoneEnabled || options.systemAudioEnabled else {
            throw AudioRecorderError.recordingFailed("No audio sources are enabled")
        }

        try await recorder.updateRecording(options: options)
        session.inPerson = inPerson
        session.microphoneEnabled = options.microphoneEnabled
        session.systemAudioEnabled = options.systemAudioEnabled
        try store.save(session)
        _activeSession = session
        return session
    }

    /// Cancels any in-progress recording without throwing; session is marked .failed.
    public func cancelRecording() async {
        guard var session = _activeSession else { return }
        _ = try? await recorder.stopRecording()
        session.status = .failed
        try? store.save(session)
        _activeSession = nil
        _recordingStartedAt = nil
    }

    // Derives per-source statuses from the URLs returned by stopRecording().
    // A source is considered present when a matching URL appears in returnedURLs.
    static func deriveSourceStatuses(
        returnedURLs: [URL],
        missingReasons: [String: String]
    ) async -> [AudioSourceStatus] {
        var result: [AudioSourceStatus] = []
        for source in AudioSourceType.allCases {
            let url = returnedURLs.first {
                $0.deletingPathExtension().lastPathComponent == source.fileNamePrefix
            }
            if let url {
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? NSNumber).map { Int64($0.int64Value) }
                #if canImport(AVFoundation)
                let duration = await Self.loadDuration(from: url)
                #else
                let duration: Double? = nil
                #endif
                result.append(AudioSourceStatus(source: source, fileSizeBytes: size, durationSeconds: duration))
            } else {
                result.append(AudioSourceStatus(source: source, missingReason: missingReasons[source.rawValue]))
            }
        }
        return result
    }

    private static func recoverRecordedURLs(
        for session: MeetingSession,
        store: SessionStore,
        returnedURLs: [URL],
        enabledSources: Set<AudioSourceType>,
        recordingStartedAt: Date
    ) -> [URL] {
        var bySource: [AudioSourceType: URL] = [:]
        let earliestAllowedModification = recordingStartedAt.addingTimeInterval(-1)

        for url in returnedURLs where isUsableAudioFile(url) {
            guard let source = sourceType(forAudioURL: url) else { continue }
            guard enabledSources.contains(source) else { continue }
            bySource[source] = url
        }

        let candidateDirs = candidateSessionDirectories(for: session, store: store)
        for source in enabledSources where bySource[source] == nil {
            let candidates = candidateDirs.compactMap { directory -> URL? in
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: .skipsHiddenFiles
                )) ?? []
                return contents
                    .filter { sourceType(forAudioURL: $0) == source && isUsableAudioFile($0) }
                    .filter { modificationDate(for: $0) >= earliestAllowedModification }
                    .sorted { modificationDate(for: $0) > modificationDate(for: $1) }
                    .first
            }
            if let recovered = candidates
                .sorted(by: { modificationDate(for: $0) > modificationDate(for: $1) })
                .first {
                bySource[source] = recovered
            }
        }

        return AudioSourceType.allCases.compactMap { bySource[$0] }
    }

    private static func candidateSessionDirectories(
        for session: MeetingSession,
        store: SessionStore
    ) -> [URL] {
        var directories: [URL] = []
        func appendUnique(_ url: URL) {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            guard !directories.contains(url) else { return }
            directories.append(url)
        }

        appendUnique(store.sessionURL(for: session))

        let shortID = String(session.id.uuidString.prefix(8))
        let matchingDirs = (try? FileManager.default.contentsOfDirectory(
            at: store.baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []
        for url in matchingDirs where url.lastPathComponent.hasSuffix("_\(shortID)") {
            appendUnique(url)
        }
        return directories
    }

    private static func sourceType(forAudioURL url: URL) -> AudioSourceType? {
        let stem = url.deletingPathExtension().lastPathComponent
        return AudioSourceType.allCases.first { $0.fileNamePrefix == stem }
    }

    private static func isUsableAudioFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return size > 0
    }

    private static func modificationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    #if canImport(AVFoundation)
    private static func loadDuration(from url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        if #available(macOS 12, iOS 15, *) {
            guard let cmDuration = try? await asset.load(.duration) else { return nil }
            let secs = CMTimeGetSeconds(cmDuration)
            return (secs.isNaN || secs.isInfinite || secs <= 0) ? nil : secs
        } else {
            return await withCheckedContinuation { continuation in
                asset.loadValuesAsynchronously(forKeys: ["duration"]) {
                    let secs = CMTimeGetSeconds(asset.duration)
                    continuation.resume(returning: (secs.isNaN || secs.isInfinite || secs <= 0) ? nil : secs)
                }
            }
        }
    }
    #endif
}

private extension AudioRecordingOptions {
    var enabledSources: Set<AudioSourceType> {
        var sources: Set<AudioSourceType> = []
        if microphoneEnabled { sources.insert(.microphone) }
        if systemAudioEnabled { sources.insert(.systemAudio) }
        return sources
    }
}
