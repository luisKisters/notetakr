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

// MARK: - ActiveRecordingInfo

public struct ActiveRecordingInfo: Equatable {
    public var noteID: String
    public var title: String
    public var startedAt: Date
    public var calendarEvent: String?
    public var participants: [Participant]

    public init(
        noteID: String,
        title: String,
        startedAt: Date,
        calendarEvent: String? = nil,
        participants: [Participant] = []
    ) {
        self.noteID = noteID
        self.title = title
        self.startedAt = startedAt
        self.calendarEvent = calendarEvent
        self.participants = participants
    }
}

// MARK: - DotState

public enum DotState: Equatable {
    case upcoming
    case current
    case past
}

// MARK: - SwitcherCommand

public struct SwitcherCommand: Equatable {
    public enum CommandID: String, Equatable {
        case openSettings
        case newNote
    }

    public var id: CommandID
    public var title: String
    public var subtitle: String
    public var shortcut: String

    public init(id: CommandID, title: String, subtitle: String, shortcut: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.shortcut = shortcut
    }
}

// MARK: - SwitcherIconKind

/// Deterministic icon shape for a switcher row — computed from note/event metadata.
public enum SwitcherIconKind: Equatable {
    case videoCall      // note or event with a meeting link (Zoom/Meet/Teams)
    case groupMeeting   // 2+ participants, no video link
    case oneOnOne       // exactly 1 participant, no video link
    case soloNote       // 0 participants, no video link
    case ghostEvent     // calendar event row (no associated note)
    case recording      // actively recording note
    case openSettings   // "Open Settings…" command row
    case newNote        // "New note" command row
}

// MARK: - SwitcherItemKind

public enum SwitcherItemKind: Equatable {
    case note(id: String, title: String, date: Date, participants: [Participant])
    case event(UpcomingEvent)
    case activeRecording(ActiveRecordingInfo)
    case command(SwitcherCommand)
}

// MARK: - SwitcherItem

public struct SwitcherItem: Equatable {
    public var kind: SwitcherItemKind
    public var dotState: DotState
    public var isRecording: Bool

    public init(kind: SwitcherItemKind, dotState: DotState, isRecording: Bool = false) {
        self.kind = kind
        self.dotState = dotState
        self.isRecording = isRecording
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

public enum ViewportRevealEdge: Equatable {
    case top
    case bottom
}

/// Shared edge-only scrolling rule for keyboard-driven picker lists.
public enum EdgeAwareScrollPolicy {
    public static func revealEdge(
        rowMinY: Double,
        rowMaxY: Double,
        viewportHeight: Double,
        topInset: Double = 0,
        bottomInset: Double = 0
    ) -> ViewportRevealEdge? {
        if rowMinY < topInset { return .top }
        if rowMaxY > viewportHeight - bottomInset { return .bottom }
        return nil
    }
}

// MARK: - Protocols

public protocol NoteListProviding {
    func listNotes() -> [MeetingNote]
}

public protocol NoteDeleting {
    func delete(id: String) throws
}

public protocol UpcomingEventsProviding {
    func listEvents() -> [UpcomingEvent]
}

public protocol ActiveRecordingProviding {
    func currentRecording() -> ActiveRecordingInfo?
}

public struct NoopActiveRecordingProvider: ActiveRecordingProviding {
    public init() {}
    public func currentRecording() -> ActiveRecordingInfo? { nil }
}

/// Stub defaults provider — replaced by AppSettingsStore in Task 12.
public protocol NoteDefaultsProviding {
    var transcribeByDefault: Bool { get }
    var defaultLanguage: TranscribeLanguage { get }
    var inPersonByDefault: Bool { get }
    var localOnlyByDefault: Bool { get }
}

public struct NoopDefaultsProvider: NoteDefaultsProviding {
    public var transcribeByDefault: Bool { true }
    public var defaultLanguage: TranscribeLanguage { .auto }
    public var inPersonByDefault: Bool { false }
    public var localOnlyByDefault: Bool { false }
    public init() {}
}

// MARK: - SwitcherViewModel

public final class SwitcherViewModel {
    private let noteListProvider: any NoteListProviding
    private let eventsProvider: any UpcomingEventsProviding
    private let activeRecordingProvider: any ActiveRecordingProviding
    private let nowProvider: () -> Date
    private let store: any NoteStoring
    private let defaultsProvider: any NoteDefaultsProviding
    private let calendar: Calendar
    private let maxCurrentCalendarGhostDuration: TimeInterval = 6 * 60 * 60
    private var locallyDeletedNoteIDs: Set<String> = []

    /// All available commands — surfaced when the search query matches their keywords.
    private static let allCommands: [SwitcherCommand] = [
        SwitcherCommand(
            id: .openSettings,
            title: "Open Settings\u{2026}",
            subtitle: "Preferences \u{B7} vocabulary \u{B7} permissions",
            shortcut: "\u{2318},"
        ),
        SwitcherCommand(
            id: .newNote,
            title: "New note",
            subtitle: "Start a fresh meeting note",
            shortcut: "\u{2318}N"
        ),
    ]

    /// Keywords associated with each command for search matching.
    private static let commandKeywords: [SwitcherCommand.CommandID: [String]] = [
        .openSettings: ["settings", "preferences", "vocabulary", "permissions"],
        .newNote:       ["new", "create", "note"],
    ]

    public var searchQuery: String = "" {
        didSet {
            if searchQuery != oldValue {
                rebuildGroups(resetSelection: true)
            }
        }
    }

    public var activeRecordingNoteID: String? {
        didSet {
            if activeRecordingNoteID != oldValue {
                rebuildGroups()
            }
        }
    }

    public private(set) var groups: [SwitcherGroup] = []
    public private(set) var selectedIndex: Int = 0

    public var onChange: (() -> Void)?

    public init(
        noteListProvider: any NoteListProviding,
        eventsProvider: any UpcomingEventsProviding,
        activeRecordingProvider: any ActiveRecordingProviding = NoopActiveRecordingProvider(),
        now: @escaping () -> Date,
        store: any NoteStoring,
        defaultsProvider: any NoteDefaultsProviding = NoopDefaultsProvider(),
        calendar: Calendar = .current
    ) {
        self.noteListProvider = noteListProvider
        self.eventsProvider = eventsProvider
        self.activeRecordingProvider = activeRecordingProvider
        self.nowProvider = now
        self.store = store
        self.defaultsProvider = defaultsProvider
        self.calendar = calendar
        rebuildGroups(resetSelection: true)
    }

    // MARK: - Reload

    public func reload(resetSelection: Bool = false) {
        rebuildGroups(resetSelection: resetSelection)
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

    public func select(index: Int, notify: Bool = true) {
        guard index >= 0, index < flatItemCount else { return }
        guard selectedIndex != index else { return }
        selectedIndex = index
        if notify { onChange?() }
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

    /// Returns the selected note's ID, or nil when the selection is a ghost event or command row.
    public func open() -> String? {
        guard let item = selectedItem else { return nil }
        switch item.kind {
        case .note(let id, _, _, _): return id
        case .activeRecording(let recording): return recording.noteID
        case .event, .command: return nil
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
            locationText: event.locationText,
            meetingLink: event.meetingLink,
            inPerson: defaultsProvider.inPersonByDefault ? true : nil,
            transcribe: defaultsProvider.transcribeByDefault,
            localOnly: defaultsProvider.localOnlyByDefault ? true : nil,
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

    /// Deletes a note from disk and rebuilds groups so the row disappears immediately.
    /// Also tombstones the id locally, so stale list providers can't re-surface the row.
    public func delete(noteID: String) {
        if let deletingStore = store as? any NoteDeleting {
            try? deletingStore.delete(id: noteID)
        }
        locallyDeletedNoteIDs.insert(noteID)
        rebuildGroups()
    }

    // MARK: - Icon kind

    /// Deterministic icon kind for a row — computed from the note/event/command metadata.
    public static func iconKind(for item: SwitcherItem) -> SwitcherIconKind {
        switch item.kind {
        case .event(let ev):
            if ev.meetingLink != nil { return .videoCall }
            return .ghostEvent
        case .activeRecording:
            return .recording
        case .note(_, _, _, let participants):
            switch participants.count {
            case 0:  return .soloNote
            case 1:  return .oneOnOne
            default: return .groupMeeting
            }
        case .command(let cmd):
            switch cmd.id {
            case .openSettings: return .openSettings
            case .newNote:      return .newNote
            }
        }
    }

    // MARK: - Groups computation

    private func rebuildGroups(resetSelection: Bool = false) {
        let activeRecording = activeRecordingProvider.currentRecording()
        let activeNoteID = activeRecording?.noteID
        let notes = noteListProvider.listNotes().filter {
            !locallyDeletedNoteIDs.contains($0.id) && $0.id != activeNoteID
        }
        let events = eventsProvider.listEvents()
        let nowDate = nowProvider()
        let todayStart = calendar.startOfDay(for: nowDate)

        var linkedEventIDs = Set(notes.compactMap { $0.calendarEvent })
        if let activeEventID = activeRecording?.calendarEvent {
            linkedEventIDs.insert(activeEventID)
        }

        var dayBuckets: [Date: [SwitcherItem]] = [:]
        var upcomingItems: [SwitcherItem] = []

        if let activeRecording {
            let dayStart = calendar.startOfDay(for: activeRecording.startedAt)
            dayBuckets[dayStart, default: []].append(
                SwitcherItem(kind: .activeRecording(activeRecording), dotState: .current)
            )
        }

        for note in notes {
            let item = SwitcherItem(
                kind: .note(id: note.id, title: note.title, date: note.date, participants: note.participants),
                dotState: computeDotState(date: note.date, end: note.end, now: nowDate),
                isRecording: note.id == activeRecordingNoteID
            )
            if item.dotState == .upcoming {
                upcomingItems.append(item)
            } else {
                let dayStart = calendar.startOfDay(for: note.date)
                dayBuckets[dayStart, default: []].append(item)
            }
        }

        for event in events {
            guard !linkedEventIDs.contains(event.id) else { continue }
            guard shouldSurfaceCalendarGhost(event, now: nowDate) else { continue }
            let dotState = computeDotState(date: event.start, end: event.end, now: nowDate)
            let item = SwitcherItem(
                kind: .event(event),
                dotState: dotState
            )
            if dotState == .upcoming || dotState == .current {
                upcomingItems.append(item)
            }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespaces)

        var newGroups: [SwitcherGroup] = []

        // Prepend command rows when the query matches.
        if !query.isEmpty {
            let matchingCmds = Self.allCommands.filter { cmd in
                let keywords = Self.commandKeywords[cmd.id] ?? []
                let lq = query.lowercased()
                return keywords.contains { $0.hasPrefix(lq) }
                    || cmd.title.lowercased().contains(lq)
            }
            if !matchingCmds.isEmpty {
                let cmdItems = matchingCmds.map {
                    SwitcherItem(kind: .command($0), dotState: .past)
                }
                newGroups.append(SwitcherGroup(label: "Commands", items: cmdItems))
            }
        }

        if !query.isEmpty {
            upcomingItems = upcomingItems.filter { matches($0, query: query) }
        }

        upcomingItems.sort { lhs, rhs in
            let lhsRank = upcomingSortRank(lhs)
            let rhsRank = upcomingSortRank(rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return dateOf(lhs) < dateOf(rhs)
        }
        appendGroup(label: "Upcoming", items: upcomingItems, to: &newGroups)

        for dayStart in dayBuckets.keys.sorted(by: >) {
            var items = dayBuckets[dayStart] ?? []
            if !query.isEmpty {
                items = items.filter { matches($0, query: query) }
            }
            guard !items.isEmpty else { continue }
            items.sort { lhs, rhs in
                let lhsRank = daySortRank(lhs)
                let rhsRank = daySortRank(rhs)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return dateOf(lhs) > dateOf(rhs)
            }
            appendGroup(label: dayLabel(dayStart, todayStart: todayStart), items: items, to: &newGroups)
        }

        self.groups = newGroups

        let total = flatItemCount
        if total == 0 {
            selectedIndex = 0
        } else if resetSelection {
            selectedIndex = preferredInitialSelectionIndex(in: newGroups, query: query)
        } else if selectedIndex >= total {
            selectedIndex = total - 1
        }

        onChange?()
    }

    // MARK: - Helpers

    private var flatItemCount: Int {
        groups.reduce(0) { $0 + $1.items.count }
    }

    private func preferredInitialSelectionIndex(in groups: [SwitcherGroup], query: String) -> Int {
        guard query.isEmpty, let upcoming = groups.first, upcoming.label == "Upcoming" else {
            return 0
        }
        guard upcoming.items.count >= 3 else {
            return 0
        }
        return upcoming.items.count - 2
    }

    private func appendGroup(label: String, items: [SwitcherItem], to groups: inout [SwitcherGroup]) {
        guard !items.isEmpty else { return }
        groups.append(SwitcherGroup(label: label, items: items))
    }

    private func computeDotState(date: Date, end: Date?, now: Date) -> DotState {
        if date > now { return .upcoming }
        if let end = end, end > now { return .current }
        return .past
    }

    private func shouldSurfaceCalendarGhost(_ event: UpcomingEvent, now: Date) -> Bool {
        if event.start >= now { return true }
        guard let end = event.end, end > now else { return false }
        return end.timeIntervalSince(event.start) <= maxCurrentCalendarGhostDuration
    }

    private func dayLabel(_ dayStart: Date, todayStart: Date) -> String {
        let diff = calendar.dateComponents([.day], from: todayStart, to: dayStart).day ?? 0
        switch diff {
        case 0:
            return "Today"
        case -1:
            return "Yesterday"
        default:
            return dateHeading(for: dayStart, todayStart: todayStart)
        }
    }

    private func dateOf(_ item: SwitcherItem) -> Date {
        switch item.kind {
        case .note(_, _, let d, _):        return d
        case .event(let e):                return e.start
        case .activeRecording(let rec):    return rec.startedAt
        case .command:                     return .distantFuture
        }
    }

    private func upcomingSortRank(_ item: SwitcherItem) -> Int {
        if item.dotState == .current { return 0 }
        return 1
    }

    private func daySortRank(_ item: SwitcherItem) -> Int {
        if case .activeRecording = item.kind { return 0 }
        return 1
    }

    private func matches(_ item: SwitcherItem, query: String) -> Bool {
        switch item.kind {
        case .note(_, let title, _, let participants):
            if diacriticInsensitiveContains(title, query) { return true }
            return participants.contains { diacriticInsensitiveContains($0.name, query) }
        case .event(let e):
            if diacriticInsensitiveContains(e.title, query) { return true }
            return e.participants.contains { diacriticInsensitiveContains($0.name, query) }
        case .activeRecording(let recording):
            if diacriticInsensitiveContains(recording.title, query) { return true }
            if diacriticInsensitiveContains("recording", query) { return true }
            if diacriticInsensitiveContains("open", query) { return true }
            return recording.participants.contains { diacriticInsensitiveContains($0.name, query) }
        case .command:
            return false  // commands filtered separately
        }
    }

    private func dateHeading(for dayStart: Date, todayStart: Date) -> String {
        let year = calendar.component(.year, from: dayStart)
        let currentYear = calendar.component(.year, from: todayStart)
        let format = year == currentYear ? "d MMM" : "d MMM yyyy"
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: dayStart)
    }

    private func diacriticInsensitiveContains(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
