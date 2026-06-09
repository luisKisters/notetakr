import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

public enum RecordingManagerError: Error, Sendable, Equatable {
    case noActiveSession
    case alreadyRecording
}

public final class RecordingManager: @unchecked Sendable {
    public let store: SessionStore
    public let recorder: any AudioRecorder
    private var _activeSession: MeetingSession?

    public var activeSession: MeetingSession? { _activeSession }
    public var isRecording: Bool { recorder.isRecording }

    public init(store: SessionStore, recorder: any AudioRecorder) {
        self.store = store
        self.recorder = recorder
    }

    /// Creates a new session in .recording state, starts the recorder, and persists the session.
    /// If the recorder fails to start, the session is saved as .failed.
    public func startRecording(
        title: String,
        date: Date = Date(),
        mode: MeetingMode = .online
    ) async throws -> MeetingSession {
        guard !recorder.isRecording else {
            throw RecordingManagerError.alreadyRecording
        }
        var session = MeetingSession(title: title, date: date, status: .recording, meetingMode: mode)
        try store.save(session)
        let dir = store.sessionURL(for: session)
        do {
            try await recorder.startRecording(into: dir, mode: mode)
        } catch {
            session.status = .failed
            try store.save(session)
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
            let urls = try await recorder.stopRecording()
            let missingReasons = (recorder as? AudioCaptureReporter)?.lastMissingReasons ?? [:]
            session.audioFilePaths = urls.map { $0.path }
            session.audioSourceStatuses = await Self.deriveSourceStatuses(
                returnedURLs: urls,
                missingReasons: missingReasons
            )
            session.status = .stopped
            try store.save(session)
            _activeSession = nil
            return session
        } catch {
            session.status = .failed
            try store.save(session)
            _activeSession = nil
            throw error
        }
    }

    /// Cancels any in-progress recording without throwing; session is marked .failed.
    public func cancelRecording() async {
        guard var session = _activeSession else { return }
        _ = try? await recorder.stopRecording()
        session.status = .failed
        try? store.save(session)
        _activeSession = nil
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
