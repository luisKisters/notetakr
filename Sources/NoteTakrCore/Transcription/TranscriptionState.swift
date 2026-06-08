import Foundation

public enum TranscriptionState: Equatable, Sendable {
    case idle
    case transcribing
    case completed
    case modelUnavailable
    case failed(String)
}
