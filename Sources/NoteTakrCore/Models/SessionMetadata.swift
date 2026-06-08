import Foundation

public struct SessionMetadata: Codable, Equatable, Sendable {
    public var title: String
    public var date: Date
    public var duration: TimeInterval?
    public var transcriptSegmentCount: Int
    public var hasPersonalNotes: Bool

    public init(
        title: String,
        date: Date,
        duration: TimeInterval? = nil,
        transcriptSegmentCount: Int,
        hasPersonalNotes: Bool
    ) {
        self.title = title
        self.date = date
        self.duration = duration
        self.transcriptSegmentCount = transcriptSegmentCount
        self.hasPersonalNotes = hasPersonalNotes
    }

    public init(from session: MeetingSession, duration: TimeInterval? = nil) {
        self.title = session.title
        self.date = session.date
        self.duration = duration
        self.transcriptSegmentCount = session.transcriptSegments.count
        self.hasPersonalNotes = !session.personalNotes.isEmpty
    }
}
