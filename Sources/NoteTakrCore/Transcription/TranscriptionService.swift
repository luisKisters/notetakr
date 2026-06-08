import Foundation

public final class TranscriptionService: @unchecked Sendable {
    private let engine: any TranscriptionEngine
    private let store: SessionStore

    public init(engine: any TranscriptionEngine, store: SessionStore) {
        self.engine = engine
        self.store = store
    }

    /// Transcribes the first audio file in the session using the provided vocabulary,
    /// persists the resulting segments to session.json, generates note.md, and returns
    /// the updated session.
    public func transcribe(session: MeetingSession, vocabulary: [VocabularyEntry]) async throws -> MeetingSession {
        guard let audioPath = session.audioFilePaths.first else {
            throw TranscriptionError.audioFileNotFound
        }
        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw TranscriptionError.audioFileNotFound
        }
        let audioURL = URL(fileURLWithPath: audioPath)
        let segments = try await engine.transcribe(audioURL: audioURL, vocabulary: vocabulary)
        var updated = session
        updated.transcriptSegments = segments
        try store.save(updated)
        generateNote(for: updated)
        return updated
    }

    private func generateNote(for session: MeetingSession) {
        let markdown = MarkdownNoteRenderer.render(session: session)
        let noteURL = store.sessionURL(for: session).appendingPathComponent("note.md")
        try? markdown.write(to: noteURL, atomically: true, encoding: .utf8)
    }
}
