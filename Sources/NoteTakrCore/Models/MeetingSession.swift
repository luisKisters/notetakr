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
    public var summary: String?
    public var linkedEventID: String?
    public var linkedEventTitle: String?
    public var participants: [Participant]
    public var meetingMode: MeetingMode

    public init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        status: SessionStatus = .idle,
        transcriptSegments: [TranscriptSegment] = [],
        personalNotes: String = "",
        audioFilePaths: [String] = [],
        audioSourceStatuses: [AudioSourceStatus] = [],
        summary: String? = nil,
        linkedEventID: String? = nil,
        linkedEventTitle: String? = nil,
        participants: [Participant] = [],
        meetingMode: MeetingMode = .online
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.status = status
        self.transcriptSegments = transcriptSegments
        self.personalNotes = personalNotes
        self.audioFilePaths = audioFilePaths
        self.audioSourceStatuses = audioSourceStatuses
        self.summary = summary
        self.linkedEventID = linkedEventID
        self.linkedEventTitle = linkedEventTitle
        self.participants = participants
        self.meetingMode = meetingMode
    }

    // Custom decoder so existing session.json files without the newer fields
    // (audioSourceStatuses, summary, calendar links) decode cleanly.
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
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        linkedEventID = try? c.decodeIfPresent(String.self, forKey: .linkedEventID)
        linkedEventTitle = try? c.decodeIfPresent(String.self, forKey: .linkedEventTitle)
        participants = (try? c.decode([Participant].self, forKey: .participants)) ?? []
        meetingMode = (try? c.decodeIfPresent(MeetingMode.self, forKey: .meetingMode)) ?? .online
    }

    enum CodingKeys: String, CodingKey {
        case id, title, date, status, transcriptSegments, personalNotes
        case audioFilePaths, audioSourceStatuses
        case summary, linkedEventID, linkedEventTitle, participants, meetingMode
    }
}
