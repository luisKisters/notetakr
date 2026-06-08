import Foundation

public enum SessionStatus: String, Codable, Equatable, CaseIterable, Sendable {
    case idle
    case recording
    case paused
    case stopped
    case failed
}
