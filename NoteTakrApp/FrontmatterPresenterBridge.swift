import Foundation
import NoteTakrKit

/// ObservableObject wrapper around Kit's `FrontmatterPresenter`.
/// Call `load(note:)` whenever the active note changes.
@MainActor
final class FrontmatterPresenterBridge: ObservableObject {
    @Published private(set) var chips: [Chip] = []
    @Published private(set) var propertyRows: [PropertyRow] = []
    @Published var isExpanded: Bool = false
    /// Set by the recording pipeline when a recording completes and audio is available.
    @Published var hasCompletedRecording: Bool = false
    /// The note's recorded audio file (microphone preferred), if any exists on disk.
    /// Set by NotePanelController on note load; drives the Transcript-row audio player.
    @Published var audioFileURL: URL?
    /// Calendar events available for the event picker; updated live by NotePanelController.
    @Published var availableEvents: [UpcomingEvent] = []
    @Published var availableEventWindow: EventPickerWindow?
    @Published var isLoadingAvailableEvents: Bool = false
    @Published var availableEventsError: String?

    private(set) var presenter: FrontmatterPresenter?
    private let store: any NoteStoring
    var onRequestCalendarEvents: ((EventPickerWindow) -> Void)?

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
        hasCompletedRecording = false
        audioFileURL = nil  // re-set by NotePanelController right after load
        refresh()
    }

    // MARK: - Mutations (forwarded to Kit presenter)

    func setInPerson(_ value: Bool) {
        try? presenter?.setInPerson(value)
    }

    func linkCalendarEvent(
        id: String,
        title: String,
        attendees: [(name: String, email: String?)],
        startDate: Date? = nil,
        endDate: Date? = nil,
        locationText: String? = nil,
        meetingLink: String? = nil
    ) {
        let participants = attendees.map { Participant(name: $0.name, email: $0.email) }
        let info = LinkedEventInfo(
            eventID: id,
            title: title,
            participants: participants,
            startDate: startDate,
            endDate: endDate,
            locationText: locationText,
            meetingLink: meetingLink
        )
        try? presenter?.linkEvent(info)
    }

    func unlinkEvent() {
        try? presenter?.unlinkEvent()
    }

    func addParticipant(name: String, email: String? = nil) {
        try? presenter?.addParticipant(Participant(name: name, email: email))
    }

    func removeParticipant(_ participant: Participant) {
        try? presenter?.removeParticipant(participant)
    }

    func setLocationText(_ text: String?) {
        try? presenter?.setLocationText(text)
    }

    func setMeetingLink(_ link: String?) {
        try? presenter?.setMeetingLink(link)
    }

    func setDate(_ date: Date, end: Date? = nil) {
        try? presenter?.setDate(date, end: end)
    }

    func requestCalendarEvents(window: EventPickerWindow) {
        onRequestCalendarEvents?(window)
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
