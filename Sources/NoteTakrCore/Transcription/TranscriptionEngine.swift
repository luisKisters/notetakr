import Foundation
import NoteTakrKit

public enum TranscriptionError: Error, Sendable, Equatable {
    case audioFileNotFound
    case modelUnavailable
    case noSpeechDetected
    case transcriptionFailed(String)
}

extension TranscriptionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .audioFileNotFound:
            return "No recording is available for this note."
        case .modelUnavailable:
            return "The speech model is not configured."
        case .noSpeechDetected:
            return "No speech was detected in the recording."
        case .transcriptionFailed(let message):
            return message
        }
    }
}

/// One audio stream to transcribe, tagged with the role it played in the
/// recording so the engine can label it appropriately (the microphone collapses
/// to a single speaker; system audio is diarized).
public struct TranscriptionSource: Sendable, Equatable {
    public var url: URL
    public var role: AudioSourceType

    public init(url: URL, role: AudioSourceType) {
        self.url = url
        self.role = role
    }
}

public protocol TranscriptionEngine: AnyObject, Sendable {
    /// Transcribes a single audio file with no role context (used by the CLI probe
    /// and as the building block for the multi-source path).
    func transcribe(audioURL: URL, vocabulary: [VocabularyEntry]) async throws -> [TranscriptSegment]

    /// Transcribes several streams and merges them into one timeline-ordered,
    /// speaker-labelled transcript.
    func transcribe(sources: [TranscriptionSource], vocabulary: [VocabularyEntry]) async throws -> [TranscriptSegment]
}

public extension TranscriptionEngine {
    /// Generic multi-source implementation: transcribe each stream independently
    /// via the single-URL method, then merge by role. Engines that can do better
    /// (e.g. skipping diarization for the microphone) override this. A single
    /// source behaves exactly like the legacy single-stream path.
    func transcribe(sources: [TranscriptionSource], vocabulary: [VocabularyEntry]) async throws -> [TranscriptSegment] {
        guard !sources.isEmpty else { throw TranscriptionError.audioFileNotFound }
        if sources.count == 1 {
            return try await transcribe(audioURL: sources[0].url, vocabulary: vocabulary)
        }
        var groups: [[TranscriptSegment]] = []
        for source in sources {
            let segments = try await transcribe(audioURL: source.url, vocabulary: vocabulary)
            switch source.role {
            case .microphone:
                groups.append(TranscriptMerger.forceSingleSpeaker(segments, label: TranscriptMerger.primarySpeakerLabel))
            case .systemAudio:
                groups.append(TranscriptMerger.offsetSpeakers(segments, startingAt: 2))
            }
        }
        return TranscriptMerger.merge(groups)
    }
}
