import Foundation

/// How a meeting is being held, which decides what audio is captured.
///
/// - `.online`: a remote call — both the microphone (you) and system audio
///   (the other participants coming out of the speakers) are recorded as
///   separate streams.
/// - `.inPerson`: everyone is in the room — only the microphone is recorded and
///   speaker separation is left entirely to diarization.
public enum MeetingMode: String, Codable, Equatable, Sendable, CaseIterable {
    case online
    case inPerson

    public var displayName: String {
        switch self {
        case .online: return "Online"
        case .inPerson: return "In Person"
        }
    }

    /// Whether system audio should be captured alongside the microphone.
    public var capturesSystemAudio: Bool {
        switch self {
        case .online: return true
        case .inPerson: return false
        }
    }
}
