import Foundation

public enum TranscriptionError: Error, Sendable, Equatable {
    case audioFileNotFound
    case modelUnavailable
    case transcriptionFailed(String)
}

public protocol TranscriptionEngine: AnyObject, Sendable {
    func transcribe(audioURL: URL, vocabulary: [VocabularyEntry]) async throws -> [TranscriptSegment]
}
