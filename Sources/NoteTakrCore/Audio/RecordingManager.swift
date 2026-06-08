import Foundation

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
    public func startRecording(title: String, date: Date = Date()) async throws -> MeetingSession {
        guard !recorder.isRecording else {
            throw RecordingManagerError.alreadyRecording
        }
        var session = MeetingSession(title: title, date: date, status: .recording)
        try store.save(session)
        let dir = store.sessionURL(for: session)
        do {
            try await recorder.startRecording(into: dir)
        } catch {
            session.status = .failed
            try store.save(session)
            throw error
        }
        _activeSession = session
        return session
    }

    /// Stops the recorder, saves the audio file paths, and transitions the session to .stopped.
    /// On recorder failure, the session is marked .failed.
    public func stopRecording() async throws -> MeetingSession {
        guard var session = _activeSession else {
            throw RecordingManagerError.noActiveSession
        }
        do {
            let urls = try await recorder.stopRecording()
            session.audioFilePaths = urls.map { $0.path }
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
}
