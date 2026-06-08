import Foundation

public final class TranscriptionService: @unchecked Sendable {
    private let engine: any TranscriptionEngine
    private let store: SessionStore

    public init(engine: any TranscriptionEngine, store: SessionStore) {
        self.engine = engine
        self.store = store
    }

    /// Transcribes the first audio file in the session using the provided vocabulary,
    /// persists the resulting segments to session.json, and returns the updated session.
    public func transcribe(session: MeetingSession, vocabulary: [VocabularyEntry]) async throws -> MeetingSession {
        guard let audioPath = session.audioFilePaths.first else {
            throw TranscriptionError.audioFileNotFound
        }
        let audioURL = URL(fileURLWithPath: audioPath)
        let segments = try await engine.transcribe(audioURL: audioURL, vocabulary: vocabulary)
        var updated = session
        updated.transcriptSegments = segments
        try store.save(updated)
        return updated
    }
}
