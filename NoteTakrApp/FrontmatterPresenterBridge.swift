import Foundation
import NoteTakrKit

/// ObservableObject wrapper around Kit's `FrontmatterPresenter`.
/// Call `load(note:)` whenever the active note changes.
@MainActor
final class FrontmatterPresenterBridge: ObservableObject {
    @Published private(set) var chips: [Chip] = []
    @Published private(set) var propertyRows: [PropertyRow] = []
    @Published var isExpanded: Bool = false

    private(set) var presenter: FrontmatterPresenter?
    private let store: any NoteStoring

    init(store: any NoteStoring) {
        self.store = store
    }

    func load(note: MeetingNote) {
        let p = FrontmatterPresenter(note: note, store: store, now: { Date() })
        p.onChange = { [weak self] in
            guard let self else { return }
            if Thread.isMainThread {
                self.refresh()
            } else {
                DispatchQueue.main.async { [weak self] in self?.refresh() }
            }
        }
        presenter = p
        isExpanded = false
        refresh()
    }

    // MARK: - Mutations (forwarded to Kit presenter)

    func setInPerson(_ value: Bool) {
        try? presenter?.setInPerson(value)
    }

    /// Link a calendar event. `attendees` is passed as plain tuples to avoid
    /// importing NoteTakrCore here (which would conflict with the Kit Participant type
    /// due to the public enum NoteTakrKit shadowing the module name).
    func linkCalendarEvent(id: String, title: String, attendees: [(name: String, email: String?)]) {
        let participants = attendees.map { Participant(name: $0.name, email: $0.email) }
        let info = LinkedEventInfo(eventID: id, title: title, participants: participants)
        try? presenter?.linkEvent(info)
    }

    func unlinkEvent() {
        try? presenter?.unlinkEvent()
    }

    func setTranscribe(_ value: Bool) {
        try? presenter?.setTranscribe(value)
    }

    func setLanguage(_ lang: TranscribeLanguage) {
        try? presenter?.setLanguage(lang)
    }

    func addVocabularyTerm(_ term: String) {
        try? presenter?.addVocabularyTerm(term)
    }

    func removeVocabularyTerm(_ term: String) {
        try? presenter?.removeVocabularyTerm(term)
    }

    // MARK: - Read-only access

    var participants: [Participant] {
        presenter?.note.participants ?? []
    }

    var noteID: String { presenter?.note.id ?? "" }
    var noteTitle: String { presenter?.note.title ?? "" }
    var noteTranscribe: Bool? { presenter?.note.transcribe }
    var noteLanguage: TranscribeLanguage? { presenter?.note.language }
    var noteVocabulary: [String] { presenter?.note.vocabulary ?? [] }
    var noteCalendarEvent: String? { presenter?.note.calendarEvent }

    /// Re-reads chips from the presenter (used by REC timer to tick the elapsed label).
    func refreshChips() {
        guard let p = presenter else { return }
        chips = p.chips
    }

    // MARK: - Private

    private func refresh() {
        guard let p = presenter else { return }
        chips = p.chips
        propertyRows = p.propertyRows
    }
}
