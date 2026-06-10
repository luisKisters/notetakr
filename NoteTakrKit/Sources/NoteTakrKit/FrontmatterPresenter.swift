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
    case date(Date)
    case calendarEvent(String?)
    case participants([Participant])
    case location(Location?)
    case inPerson(Bool)
    case transcribe(Bool?)
}

// MARK: - LinkedEventInfo

public struct LinkedEventInfo: Equatable {
    public var eventID: String
    public var title: String
    public var participants: [Participant]

    public init(eventID: String, title: String, participants: [Participant] = []) {
        self.eventID = eventID
        self.title = title
        self.participants = participants
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
            result.append(.recording(Self.formatElapsed(elapsed)))
        }
        return result
    }

    public var propertyRows: [PropertyRow] {
        [
            .date(note.date),
            .calendarEvent(note.calendarEvent),
            .participants(note.participants),
            .location(note.location),
            .inPerson(note.inPerson ?? false),
            .transcribe(note.transcribe)
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
        for p in event.participants where !note.participants.contains(p) {
            note.participants.append(p)
        }
        try store.save(note)
        onChange?()
    }

    public func unlinkEvent() throws {
        note.calendarEvent = nil
        try store.save(note)
        onChange?()
    }

    public func addParticipant(_ participant: Participant) throws {
        note.participants.append(participant)
        try store.save(note)
        onChange?()
    }

    public func removeParticipant(_ participant: Participant) throws {
        note.participants.removeAll { $0 == participant }
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
        note.vocabulary.removeAll { $0 == term }
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
}
