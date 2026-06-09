import Foundation

/// UI-facing state for a session's summarization, mirroring `TranscriptionState`.
public enum SummarizationState: Equatable, Sendable {
    case idle
    case summarizing
    case completed
    case noAPIKey
    case failed(String)
}
