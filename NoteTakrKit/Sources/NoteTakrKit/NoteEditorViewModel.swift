import Foundation

public protocol NoteStoring {
    func load(id: String) throws -> MeetingNote?
    func save(_ note: MeetingNote) throws
}

public final class NoteEditorViewModel {
    public var onChange: (() -> Void)?

    private let store: any NoteStoring
    private let scheduler: any Scheduler
    private static let saveKey = "noteEditorSave"

    private var currentNote: MeetingNote?
    var isDirty: Bool = false

    public init(store: any NoteStoring, scheduler: any Scheduler) {
        self.store = store
        self.scheduler = scheduler
    }

    // MARK: - Accessors

    public var title: String { currentNote?.title ?? "" }
    public var body: String { currentNote?.body ?? "" }
    public var noteID: String? { currentNote?.id }

    // MARK: - API

    public func load(noteID: String) throws {
        try flush()
        currentNote = try store.load(id: noteID)
        if var loadedNote = currentNote {
            loadedNote.body = Self.userAuthoredNotes(from: loadedNote.body)
            currentNote = loadedNote
        }
        isDirty = false
        onChange?()
    }

    public func setTitle(_ newTitle: String) {
        guard currentNote != nil else { return }
        currentNote!.title = newTitle
        isDirty = true
        scheduleSave()
        onChange?()
    }

    public func setBody(_ newBody: String) {
        guard currentNote != nil else { return }
        currentNote!.body = newBody
        isDirty = true
        scheduleSave()
        onChange?()
    }

    public func flush() throws {
        scheduler.cancel(id: Self.saveKey)
        guard isDirty, let note = try noteForSavingEditorEdits() else { return }
        try store.save(note)
        currentNote = note
        isDirty = false
    }

    // MARK: - Private

    private func scheduleSave() {
        scheduler.schedule(id: Self.saveKey, delay: 1.0) { [weak self] in
            guard let self, self.isDirty else { return }
            guard let note = try? self.noteForSavingEditorEdits() else { return }
            guard (try? self.store.save(note)) != nil else { return }
            self.currentNote = note
            self.isDirty = false
        }
    }

    private func noteForSavingEditorEdits() throws -> MeetingNote? {
        guard let currentNote else { return nil }
        var latest = (try store.load(id: currentNote.id)) ?? currentNote
        latest.title = currentNote.title
        latest.body = currentNote.body
        return latest
    }

    /// Older recording folders may use the generated session markdown as the
    /// note body. The Notes editor must contain only text the user authored;
    /// summary, audio-source, status, and transcript content have dedicated UI.
    static func userAuthoredNotes(from body: String) -> String {
        let lines = body.components(separatedBy: .newlines)
        let isGeneratedSessionDocument = lines.contains { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("**Status:**")
        }
        guard isGeneratedSessionDocument else { return body }
        guard let headingIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "## Personal Notes"
        }) else { return "" }

        let contentStart = lines.index(after: headingIndex)
        let following = lines[contentStart...]
        let contentEnd = following.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("## ")
        }) ?? lines.endIndex
        return lines[contentStart..<contentEnd]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
