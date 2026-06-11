import Foundation

// MARK: - UpcomingEvent

public struct UpcomingEvent: Equatable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date?
    public var participants: [Participant]
    public var locationText: String?
    public var meetingLink: String?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date? = nil,
        participants: [Participant] = [],
        locationText: String? = nil,
        meetingLink: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.participants = participants
        self.locationText = locationText
        self.meetingLink = meetingLink
    }
}

// MARK: - DotState

public enum DotState: Equatable {
    case upcoming
    case current
    case past
}

// MARK: - SwitcherItemKind

public enum SwitcherItemKind: Equatable {
    case note(id: String, title: String, date: Date, participants: [Participant])
    case event(UpcomingEvent)
}

// MARK: - SwitcherItem

public struct SwitcherItem: Equatable {
    public var kind: SwitcherItemKind
    public var dotState: DotState

    public init(kind: SwitcherItemKind, dotState: DotState) {
        self.kind = kind
        self.dotState = dotState
    }
}

// MARK: - SwitcherGroup

public struct SwitcherGroup: Equatable {
    public var label: String
    public var items: [SwitcherItem]

    public init(label: String, items: [SwitcherItem]) {
        self.label = label
        self.items = items
    }
}

// MARK: - Protocols

public protocol NoteListProviding {
    func listNotes() -> [MeetingNote]
}

public protocol UpcomingEventsProviding {
    func listEvents() -> [UpcomingEvent]
}

/// Stub defaults provider — replaced by AppSettingsStore in Task 12.
public protocol NoteDefaultsProviding {
    var transcribeByDefault: Bool { get }
    var defaultLanguage: TranscribeLanguage { get }
    var inPersonByDefault: Bool { get }
}

public struct NoopDefaultsProvider: NoteDefaultsProviding {
    public var transcribeByDefault: Bool { true }
    public var defaultLanguage: TranscribeLanguage { .auto }
    public var inPersonByDefault: Bool { false }
    public init() {}
}

// MARK: - SwitcherViewModel

public final class SwitcherViewModel {
    private let noteListProvider: any NoteListProviding
    private let eventsProvider: any UpcomingEventsProviding
    private let nowProvider: () -> Date
    private let store: any NoteStoring
    private let defaultsProvider: any NoteDefaultsProviding
    private let calendar: Calendar

    public var searchQuery: String = "" {
        didSet {
            if searchQuery != oldValue { rebuildGroups() }
        }
    }

    public private(set) var groups: [SwitcherGroup] = []
    public private(set) var selectedIndex: Int = 0

    public var onChange: (() -> Void)?

    public init(
        noteListProvider: any NoteListProviding,
        eventsProvider: any UpcomingEventsProviding,
        now: @escaping () -> Date,
        store: any NoteStoring,
        defaultsProvider: any NoteDefaultsProviding = NoopDefaultsProvider(),
        calendar: Calendar = .current
    ) {
        self.noteListProvider = noteListProvider
        self.eventsProvider = eventsProvider
        self.nowProvider = now
        self.store = store
        self.defaultsProvider = defaultsProvider
        self.calendar = calendar
        rebuildGroups()
    }

    // MARK: - Reload

    public func reload() {
        rebuildGroups()
    }

    // MARK: - Selection navigation

    public func moveUp() {
        let total = flatItemCount
        guard total > 0 else { return }
        selectedIndex = (selectedIndex - 1 + total) % total
        onChange?()
    }

    public func moveDown() {
        let total = flatItemCount
        guard total > 0 else { return }
        selectedIndex = (selectedIndex + 1) % total
        onChange?()
    }

    public var selectedItem: SwitcherItem? {
        guard flatItemCount > 0, selectedIndex < flatItemCount else { return nil }
        var idx = 0
        for group in groups {
            for item in group.items {
                if idx == selectedIndex { return item }
                idx += 1
            }
        }
        return nil
    }

    // MARK: - Actions

    /// Returns the selected note's ID, or nil when the selection is a ghost event row.
    public func open() -> String? {
        guard let item = selectedItem else { return nil }
        switch item.kind {
        case .note(let id, _, _, _): return id
        case .event: return nil
        }
    }

    /// Creates a note from a calendar event (prefilled frontmatter + materialized defaults), saves it,
    /// and rebuilds groups so the new note appears immediately.
    @discardableResult
    public func createNote(from event: UpcomingEvent) throws -> MeetingNote {
        let note = MeetingNote(
            id: UUID().uuidString,
            title: event.title,
            date: event.start,
            end: event.end,
            calendarEvent: event.id,
            participants: event.participants,
            inPerson: defaultsProvider.inPersonByDefault ? true : nil,
            transcribe: defaultsProvider.transcribeByDefault,
            language: {
                switch defaultsProvider.defaultLanguage {
                case .auto: return nil
                case .code(let s): return .code(s)
                }
            }()
        )
        try store.save(note)
        rebuildGroups()
        return note
    }

    // MARK: - Groups computation

    private func rebuildGroups() {
        let notes = noteListProvider.listNotes()
        let events = eventsProvider.listEvents()
        let nowDate = nowProvider()
        let todayStart = calendar.startOfDay(for: nowDate)

        let linkedEventIDs = Set(notes.compactMap { $0.calendarEvent })

        var dayBuckets: [Date: [SwitcherItem]] = [:]

        for note in notes {
            let dayStart = calendar.startOfDay(for: note.date)
            let item = SwitcherItem(
                kind: .note(id: note.id, title: note.title, date: note.date, participants: note.participants),
                dotState: computeDotState(date: note.date, end: note.end, now: nowDate)
            )
            dayBuckets[dayStart, default: []].append(item)
        }

        for event in events {
            guard !linkedEventIDs.contains(event.id) else { continue }
            let dayStart = calendar.startOfDay(for: event.start)
            let item = SwitcherItem(
                kind: .event(event),
                dotState: computeDotState(date: event.start, end: event.end, now: nowDate)
            )
            dayBuckets[dayStart, default: []].append(item)
        }

        let query = searchQuery.trimmingCharacters(in: .whitespaces)

        // Future days shown ascending (soonest first); today and past shown descending (most recent first).
        let futureDays = dayBuckets.keys.filter { $0 > todayStart }.sorted()
        let todayAndPastDays = dayBuckets.keys.filter { $0 <= todayStart }.sorted(by: >)

        var newGroups: [SwitcherGroup] = []
        for dayStart in futureDays + todayAndPastDays {
            var items = dayBuckets[dayStart] ?? []
            if dayStart > todayStart {
                items.sort { dateOf($0) < dateOf($1) }
            } else {
                items.sort { dateOf($0) > dateOf($1) }
            }
            if !query.isEmpty {
                items = items.filter { matches($0, query: query) }
            }
            guard !items.isEmpty else { continue }
            newGroups.append(SwitcherGroup(label: dayLabel(dayStart, todayStart: todayStart), items: items))
        }

        self.groups = newGroups

        let total = flatItemCount
        if total == 0 {
            selectedIndex = 0
        } else if selectedIndex >= total {
            selectedIndex = total - 1
        }

        onChange?()
    }

    // MARK: - Helpers

    private var flatItemCount: Int {
        groups.reduce(0) { $0 + $1.items.count }
    }

    private func computeDotState(date: Date, end: Date?, now: Date) -> DotState {
        if date > now { return .upcoming }
        if let end = end, end > now { return .current }
        return .past
    }

    private func dayLabel(_ dayStart: Date, todayStart: Date) -> String {
        let diff = calendar.dateComponents([.day], from: todayStart, to: dayStart).day ?? 0
        switch diff {
        case 0:   return "Today"
        case 1:   return "Tomorrow"
        case -1:  return "Yesterday"
        case 2...7, -7 ..< -1:
            let fmt = DateFormatter()
            fmt.calendar = calendar
            fmt.timeZone = calendar.timeZone
            fmt.dateFormat = "EEEE"
            return fmt.string(from: dayStart)
        default:
            let fmt = DateFormatter()
            fmt.calendar = calendar
            fmt.timeZone = calendar.timeZone
            fmt.dateFormat = "MMM d"
            return fmt.string(from: dayStart)
        }
    }

    private func dateOf(_ item: SwitcherItem) -> Date {
        switch item.kind {
        case .note(_, _, let d, _): return d
        case .event(let e):         return e.start
        }
    }

    private func matches(_ item: SwitcherItem, query: String) -> Bool {
        switch item.kind {
        case .note(_, let title, _, let participants):
            if diacriticInsensitiveContains(title, query) { return true }
            return participants.contains { diacriticInsensitiveContains($0.name, query) }
        case .event(let e):
            if diacriticInsensitiveContains(e.title, query) { return true }
            return e.participants.contains { diacriticInsensitiveContains($0.name, query) }
        }
    }

    private func diacriticInsensitiveContains(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
