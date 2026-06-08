import Foundation

public struct MeetingSession: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var status: SessionStatus
    public var transcriptSegments: [TranscriptSegment]
    public var personalNotes: String
    public var audioFilePaths: [String]

    public init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        status: SessionStatus = .idle,
        transcriptSegments: [TranscriptSegment] = [],
        personalNotes: String = "",
        audioFilePaths: [String] = []
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.status = status
        self.transcriptSegments = transcriptSegments
        self.personalNotes = personalNotes
        self.audioFilePaths = audioFilePaths
    }
}
