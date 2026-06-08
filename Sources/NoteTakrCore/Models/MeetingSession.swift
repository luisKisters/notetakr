import Foundation

public struct MeetingSession: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var status: SessionStatus
    public var transcriptSegments: [TranscriptSegment]
    public var personalNotes: String
    public var audioFilePaths: [String]
    public var audioSourceStatuses: [AudioSourceStatus]

    public init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        status: SessionStatus = .idle,
        transcriptSegments: [TranscriptSegment] = [],
        personalNotes: String = "",
        audioFilePaths: [String] = [],
        audioSourceStatuses: [AudioSourceStatus] = []
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.status = status
        self.transcriptSegments = transcriptSegments
        self.personalNotes = personalNotes
        self.audioFilePaths = audioFilePaths
        self.audioSourceStatuses = audioSourceStatuses
    }

    // Custom decoder so existing session.json files without audioSourceStatuses decode cleanly.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        date = try c.decode(Date.self, forKey: .date)
        status = try c.decode(SessionStatus.self, forKey: .status)
        transcriptSegments = try c.decode([TranscriptSegment].self, forKey: .transcriptSegments)
        personalNotes = try c.decode(String.self, forKey: .personalNotes)
        audioFilePaths = try c.decode([String].self, forKey: .audioFilePaths)
        audioSourceStatuses = (try? c.decode([AudioSourceStatus].self, forKey: .audioSourceStatuses)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id, title, date, status, transcriptSegments, personalNotes, audioFilePaths, audioSourceStatuses
    }
}
