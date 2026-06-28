import Foundation

public struct Participant: Equatable, Hashable, Codable {
    public var name: String
    public var email: String?

    public init(name: String, email: String? = nil) {
        self.name = name
        self.email = email
    }

    public var displayName: String {
        Self.displayName(name: name, email: email)
    }

    public static func displayName(name: String?, email: String?) -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedName,
           !trimmedName.isEmpty,
           trimmedName.caseInsensitiveCompare(trimmedEmail ?? "") != .orderedSame {
            return trimmedName
        }

        if let trimmedEmail,
           let inferred = inferredName(fromEmail: trimmedEmail) {
            return inferred
        }

        return trimmedName?.isEmpty == false ? trimmedName! : "Unknown"
    }

    public static func inferredName(fromEmail email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.firstIndex(of: "@") else { return nil }
        let localPart = trimmed[..<atIndex].split(separator: "+", maxSplits: 1).first ?? ""
        let pieces = localPart
            .split { character in
                character == "." || character == "_" || character == "-"
            }
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !pieces.isEmpty else { return nil }
        return pieces
            .map { $0.localizedCapitalized }
            .joined(separator: " ")
    }
}

public enum Location: String, Equatable, Hashable, Codable, CaseIterable {
    case zoom
    case meet
    case teams
    case inPerson = "in-person"
    case none
}

public enum TranscribeLanguage: Equatable, Hashable, Codable {
    case auto
    case code(String)

    public var rawValue: String {
        switch self {
        case .auto: return "auto"
        case .code(let s): return s
        }
    }

    public init(rawValue: String) {
        if rawValue == "auto" { self = .auto } else { self = .code(rawValue) }
    }
}

public struct MeetingNote: Equatable {
    public var id: String
    public var title: String
    public var date: Date
    public var end: Date?
    public var calendarEvent: String?
    public var participants: [Participant]
    public var location: Location?
    /// Free-text location from the linked calendar event (e.g. "Acme HQ · Room 4").
    public var locationText: String?
    /// Meeting URL (Zoom/Meet/Teams link) from the linked calendar event.
    public var meetingLink: String?
    public var inPerson: Bool?
    public var transcribe: Bool?
    public var language: TranscribeLanguage?
    public var vocabulary: [String]
    public var unknownFrontmatterKeys: [(key: String, rawLine: String)]
    public var body: String

    public init(
        id: String,
        title: String,
        date: Date,
        end: Date? = nil,
        calendarEvent: String? = nil,
        participants: [Participant] = [],
        location: Location? = nil,
        locationText: String? = nil,
        meetingLink: String? = nil,
        inPerson: Bool? = nil,
        transcribe: Bool? = nil,
        language: TranscribeLanguage? = nil,
        vocabulary: [String] = [],
        unknownFrontmatterKeys: [(key: String, rawLine: String)] = [],
        body: String = ""
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.end = end
        self.calendarEvent = calendarEvent
        self.participants = participants
        self.location = location
        self.locationText = locationText
        self.meetingLink = meetingLink
        self.inPerson = inPerson
        self.transcribe = transcribe
        self.language = language
        self.vocabulary = vocabulary
        self.unknownFrontmatterKeys = unknownFrontmatterKeys
        self.body = body
    }

    public static func == (lhs: MeetingNote, rhs: MeetingNote) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.date == rhs.date &&
        lhs.end == rhs.end &&
        lhs.calendarEvent == rhs.calendarEvent &&
        lhs.participants == rhs.participants &&
        lhs.location == rhs.location &&
        lhs.locationText == rhs.locationText &&
        lhs.meetingLink == rhs.meetingLink &&
        lhs.inPerson == rhs.inPerson &&
        lhs.transcribe == rhs.transcribe &&
        lhs.language == rhs.language &&
        lhs.vocabulary == rhs.vocabulary &&
        lhs.body == rhs.body
    }
}
