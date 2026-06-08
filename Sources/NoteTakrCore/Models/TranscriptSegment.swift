import Foundation

public struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: TimeInterval
    public var speaker: String?
    public var text: String

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        speaker: String? = nil,
        text: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.speaker = speaker
        self.text = text
    }
}
