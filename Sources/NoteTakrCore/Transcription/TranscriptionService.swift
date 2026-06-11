import Foundation
import NoteTakrKit

public final class TranscriptionService: @unchecked Sendable {
    private let engine: any TranscriptionEngine
    private let store: SessionStore

    public init(engine: any TranscriptionEngine, store: SessionStore) {
        self.engine = engine
        self.store = store
    }

    /// Transcribes every captured audio stream in the session (microphone +
    /// system audio), merges them into one speaker-labelled transcript, persists
    /// the result to session.json, regenerates note.md, and returns the updated
    /// session.
    public func transcribe(session: MeetingSession, vocabulary: [VocabularyEntry]) async throws -> MeetingSession {
        let sources = Self.transcriptionSources(for: session)
        guard !sources.isEmpty else {
            throw TranscriptionError.audioFileNotFound
        }
        let segments = try await engine.transcribe(sources: sources, vocabulary: vocabulary)
        var updated = session
        updated.transcriptSegments = segments
        try store.save(updated)
        generateNote(for: updated)
        return updated
    }

    /// Builds the transcription sources from a session's audio files, skipping
    /// missing or empty files and inferring each file's role from its name
    /// (`microphone.m4a` / `system-audio.m4a`).
    static func transcriptionSources(for session: MeetingSession) -> [TranscriptionSource] {
        session.audioFilePaths.compactMap { path -> TranscriptionSource? in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else { return nil }
            let role = role(forFileName: URL(fileURLWithPath: path).lastPathComponent)
            return TranscriptionSource(url: URL(fileURLWithPath: path), role: role)
        }
    }

    static func role(forFileName name: String) -> AudioSourceType {
        let lower = name.lowercased()
        if lower.hasPrefix(AudioSourceType.systemAudio.fileNamePrefix) {
            return .systemAudio
        }
        return .microphone
    }

    private func generateNote(for session: MeetingSession) {
        let markdown = MarkdownNoteRenderer.render(session: session)
        let noteURL = store.sessionURL(for: session).appendingPathComponent("note.md")
        try? markdown.write(to: noteURL, atomically: true, encoding: .utf8)
    }
}
