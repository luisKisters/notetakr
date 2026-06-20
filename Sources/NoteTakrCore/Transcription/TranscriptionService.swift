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
        let sources = Self.transcriptionSources(
            for: session, sessionDir: store.sessionURL(for: session)
        )
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
    ///
    /// Stored paths can go stale when the session folder is renamed (title change
    /// moves the folder but old session.json files keep absolute paths). When a
    /// stored path is missing, fall back to the same filename inside the session's
    /// *current* directory so those recordings stay transcribable.
    static func transcriptionSources(
        for session: MeetingSession,
        sessionDir: URL? = nil
    ) -> [TranscriptionSource] {
        session.audioFilePaths.compactMap { path -> TranscriptionSource? in
            var url = URL(fileURLWithPath: path)
            if !FileManager.default.fileExists(atPath: url.path), let sessionDir {
                let healed = sessionDir.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: healed.path) {
                    url = healed
                }
            }
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else { return nil }
            let role = role(forFileName: url.lastPathComponent)
            return TranscriptionSource(url: url, role: role)
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
