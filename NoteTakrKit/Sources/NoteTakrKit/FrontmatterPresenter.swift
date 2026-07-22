import Foundation

// MARK: - Chip

public enum Chip: Equatable {
    case timeRange(String)
    case location(String)
    case participants(String)
    case recording(String)
}

// MARK: - PropertyRow

public enum PropertyRow: Equatable {
    /// Linked calendar event chip — id is nil when nothing is linked.
    case event(id: String?, title: String)
    /// Date and optional end date (for displaying time range in the panel).
    case dateTime(date: Date, end: Date?)
    /// Participant circles.
    case people([Participant])
    /// Free-text location (nil = "No location").
    case location(String?)
    /// Meeting URL, nil = "No link".
    case meetingLink(String?)
    /// In-person toggle.
    case inPerson(Bool)
    /// Transcript row — renders the record pill or player depending on recording state.
    case transcript
}

// MARK: - LinkedEventInfo

public struct LinkedEventInfo: Equatable {
    public var eventID: String
    public var title: String
    public var participants: [Participant]
    public var startDate: Date?
    public var endDate: Date?
    public var locationText: String?
    public var meetingLink: String?

    public init(
        eventID: String,
        title: String,
        participants: [Participant] = [],
        startDate: Date? = nil,
        endDate: Date? = nil,
        locationText: String? = nil,
        meetingLink: String? = nil
    ) {
        self.eventID = eventID
        self.title = title
        self.participants = participants
        self.startDate = startDate
        self.endDate = endDate
        self.locationText = locationText
        self.meetingLink = meetingLink
    }
}

// MARK: - FrontmatterPresenter

public final class FrontmatterPresenter {
    private let store: any NoteStoring
    private let now: () -> Date
    private let timeZone: TimeZone

    public private(set) var note: MeetingNote
    public var isExpanded: Bool = false
    public var onChange: (() -> Void)?
    public var recordingStartedAt: Date?

    public init(
        note: MeetingNote,
        store: any NoteStoring,
        now: @escaping () -> Date,
        timeZone: TimeZone = .current
    ) {
        self.note = note
        self.store = store
        self.now = now
        self.timeZone = timeZone
    }

    // MARK: - Computed

    public var chips: [Chip] {
        var result: [Chip] = []
        result.append(.timeRange(timeRangeLabel()))
        if let label = locationLabel() {
            result.append(.location(label))
        }
        if !note.participants.isEmpty {
            let n = note.participants.count
            result.append(.participants(n == 1 ? "1 person" : "\(n) people"))
        }
        if let startedAt = recordingStartedAt {
            let elapsed = now().timeIntervalSince(startedAt)
            result.append(.recording(Self.formatRecordingElapsed(elapsed)))
        }
        return result
    }

    public var propertyRows: [PropertyRow] {
        [
            .event(id: note.calendarEvent, title: note.title),
            .dateTime(date: note.date, end: note.end),
            .people(note.participants),
            .location(note.locationText),
            .meetingLink(note.meetingLink),
            .inPerson(note.inPerson ?? false),
            .transcript
        ]
    }

    // MARK: - Mutations

    public func setInPerson(_ inPerson: Bool) throws {
        note.inPerson = inPerson
        try store.save(note)
        onChange?()
    }

    public func linkEvent(_ event: LinkedEventInfo) throws {
        note.calendarEvent = event.eventID
        note.title = event.title
        if let startDate = event.startDate {
            note.date = startDate
            note.end = event.endDate
        }
        note.locationText = Self.trimmedNonEmpty(event.locationText)
        note.meetingLink = Self.trimmedNonEmpty(event.meetingLink)
        note.participants = Self.normalizedParticipants(event.participants)
        try store.save(note)
        onChange?()
    }

    public func unlinkEvent() throws {
        note.calendarEvent = nil
        try store.save(note)
        onChange?()
    }

    public func addParticipant(_ participant: Participant) throws {
        let normalized = Self.normalizedParticipant(participant)
        guard !note.participants.contains(where: { ParticipantIdentity.matches($0, normalized) }) else { return }
        note.participants.append(normalized)
        try store.save(note)
        onChange?()
    }

    public func removeParticipant(_ participant: Participant) throws {
        note.participants.removeAll { $0 == participant }
        try store.save(note)
        onChange?()
    }

    public func setLocationText(_ text: String?) throws {
        let trimmed = text?.trimmingCharacters(in: .whitespaces)
        note.locationText = trimmed?.isEmpty == false ? trimmed : nil
        try store.save(note)
        onChange?()
    }

    public func setMeetingLink(_ link: String?) throws {
        let trimmed = link?.trimmingCharacters(in: .whitespaces)
        note.meetingLink = trimmed?.isEmpty == false ? trimmed : nil
        try store.save(note)
        onChange?()
    }

    public func setDate(_ date: Date, end: Date? = nil) throws {
        note.date = date
        note.end = end
        try store.save(note)
        onChange?()
    }

    public func setTranscribe(_ transcribe: Bool) throws {
        note.transcribe = transcribe
        try store.save(note)
        onChange?()
    }

    public func setLanguage(_ language: TranscribeLanguage) throws {
        note.language = language
        try store.save(note)
        onChange?()
    }

    public func addVocabularyTerm(_ term: String) throws {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !note.vocabulary.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return }
        note.vocabulary.append(trimmed)
        try store.save(note)
        onChange?()
    }

    public func removeVocabularyTerm(_ term: String) throws {
        note.vocabulary.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        try store.save(note)
        onChange?()
    }

    // MARK: - Formatting

    private func timeRangeLabel() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = timeZone
        let start = fmt.string(from: note.date)
        guard let end = note.end else { return start }
        return "\(start)–\(fmt.string(from: end))"
    }

    private func locationLabel() -> String? {
        // Prefer free-text location when set
        if let text = note.locationText, !text.isEmpty {
            return text
        }
        guard let loc = note.location else {
            return note.inPerson == true ? "In person" : nil
        }
        switch loc {
        case .zoom: return "Zoom"
        case .meet: return "Google Meet"
        case .teams: return "Teams"
        case .inPerson: return "In person"
        case .none: return note.inPerson == true ? "In person" : nil
        }
    }

    public static func formatElapsed(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Compact live-recording duration shown as an hours-and-minutes clock.
    /// Any started partial minute occupies the next minute bucket, so the display
    /// reads 00:01 throughout the first minute without ticking through seconds.
    public static func formatRecordingElapsed(_ elapsed: TimeInterval) -> String {
        let clamped = max(0, elapsed)
        let totalMinutes = clamped == 0 ? 0 : Int(ceil(clamped / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func normalizedParticipants(_ participants: [Participant]) -> [Participant] {
        var result: [Participant] = []

        for participant in participants {
            let normalized = normalizedParticipant(participant)
            guard !result.contains(where: { ParticipantIdentity.matches($0, normalized) }) else { continue }
            result.append(normalized)
        }

        return result
    }

    private static func normalizedParticipant(_ participant: Participant) -> Participant {
        let email = trimmedNonEmpty(participant.email)
        let crm = trimmedNonEmpty(participant.crm)
        let name = Participant.displayName(name: trimmedNonEmpty(participant.name), email: email)
        return Participant(name: name, email: email, crm: crm)
    }
}
