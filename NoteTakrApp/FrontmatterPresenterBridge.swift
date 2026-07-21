import Foundation
import NoteTakrKit

/// ObservableObject wrapper around Kit's `FrontmatterPresenter`.
/// Call `load(note:)` whenever the active note changes.
@MainActor
final class FrontmatterPresenterBridge: ObservableObject {
    @Published private(set) var chips: [Chip] = []
    @Published private(set) var propertyRows: [PropertyRow] = []
    /// Per-note override used by the This Meeting settings toggle. Publishing
    /// it keeps SwiftUI in sync after presenter mutations persist the note.
    @Published private(set) var noteInPerson: Bool?
    @Published private(set) var noteLocalOnly: Bool?
    @Published var isExpanded: Bool = false
    /// Set by the recording pipeline when a recording completes and audio is available.
    @Published var hasCompletedRecording: Bool = false
    /// The note's recorded audio file (microphone preferred), if any exists on disk.
    /// Set by NotePanelController on note load; drives the Transcript-row audio player.
    @Published var audioFileURL: URL?
    /// Calendar events available for the event picker; updated live by NotePanelController.
    @Published var availableEvents: [UpcomingEvent] = [] {
        didSet { rebuildPeopleSources(notes: indexedNotes) }
    }
    @Published var availableEventWindow: EventPickerWindow?
    @Published var isLoadingAvailableEvents: Bool = false
    @Published var availableEventsError: String?
    @Published private(set) var peopleIndexEntries: [PersonIndexEntry] = []
    @Published private(set) var peopleDirectory = PeopleDirectory(sources: [])
    @Published private(set) var pastMeetingsIndex = PastMeetingsIndex(notes: [])
    @Published var crmConnected: Bool = false {
        didSet { refreshCrmStatus() }
    }
    @Published private(set) var crmBannerText: String?
    /// Meeting capture sources are fixed for the lifetime of a recording. The
    /// in-person toggle is disabled while this is true so system audio cannot
    /// continue behind metadata that was changed mid-recording.
    @Published private(set) var isRecording: Bool = false

    private(set) var presenter: FrontmatterPresenter?
    private let store: any NoteStoring
    private let crmPeopleSource: (any PeopleSource)?
    private var indexedNotes: [MeetingNote] = []
    private var crmStatusPresenter = CrmStatusPresenter()
    var onRequestCalendarEvents: ((EventPickerWindow) -> Void)?
    var onDidSave: ((String) -> Void)?

    init(store: any NoteStoring, crmPeopleSource: (any PeopleSource)? = nil) {
        self.store = store
        self.crmPeopleSource = crmPeopleSource
    }

    func load(note: MeetingNote) {
        let p = FrontmatterPresenter(note: note, store: store, now: { Date() })
        p.onDidSave = { [weak self] savedNote in
            self?.onDidSave?(savedNote.id)
        }
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
        refreshPeopleIndexFromStoreIfPossible()
        #if DEBUG
        if ProcessInfo.processInfo.environment["NOTETAKR_E2E_EXPAND_FRONTMATTER"] == "1" {
            isExpanded = true
        }
        #endif
    }

    // MARK: - Mutations (forwarded to Kit presenter)

    func setInPerson(_ value: Bool) {
        guard !isRecording else { return }
        try? presenter?.setInPerson(value)
    }

    func setLocalOnly(_ value: Bool) {
        try? presenter?.setLocalOnly(value)
    }

    func setCrmPushEnabled(_ value: Bool) {
        try? presenter?.setCrmPushEnabled(value)
    }

    func applyPersistedCrmPushStatus(_ status: CrmPushStatus, for noteID: String) {
        guard presenter?.note.id == noteID else { return }
        presenter?.applyPersistedCrmPushStatus(status)
    }

    func dismissCrmBanner() {
        guard let meetingId = presenter?.note.id, !meetingId.isEmpty else { return }
        crmStatusPresenter.dismiss(meetingId: meetingId)
        refreshCrmStatus()
    }

    func setRecordingActive(_ active: Bool) {
        isRecording = active
    }

    func linkCalendarEvent(
        id: String,
        title: String,
        attendees: [Participant],
        startDate: Date? = nil,
        endDate: Date? = nil,
        locationText: String? = nil,
        meetingLink: String? = nil
    ) {
        let participants = attendees.map {
            let email = $0.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let crm = $0.crm?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            return autoMatchedParticipant(
                Participant(
                    name: Participant.displayName(name: $0.name, email: email),
                    email: email,
                    crm: crm
                )
            )
        }
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

    func addParticipant(name: String, email: String? = nil, crm: String? = nil) {
        try? presenter?.addParticipant(Participant(name: name, email: email, crm: crm))
    }

    func addParticipant(_ participant: Participant) {
        try? presenter?.addParticipant(participant)
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

    func rebuildPeopleIndex(notes: [MeetingNote]) {
        rebuildPeopleSources(notes: notes)
    }

    func peoplePickerSections(
        matching query: String,
        excluding selectedParticipants: [Participant]
    ) -> [PeoplePickerPresenter.Section] {
        peoplePickerPresenter(excluding: selectedParticipants).sections(for: query)
    }

    func addParticipant(fromPickerRow row: PeoplePickerPresenter.Row, excluding selectedParticipants: [Participant]) {
        let participant = peoplePickerPresenter(excluding: selectedParticipants).participant(from: row)
        addParticipant(participant)
    }

    func company(for participant: Participant) -> String? {
        if let email = participant.email,
           let person = peopleDirectory.person(forEmail: email),
           let company = person.company?.trimmingCharacters(in: .whitespacesAndNewlines),
           !company.isEmpty {
            return company
        }

        guard let email = participant.email else { return nil }
        return Person(name: participant.displayName, emails: [email]).company
    }

    func pastMeetingEntry(for participant: Participant) -> PastMeetingsIndexEntry? {
        guard let email = participant.email else { return nil }
        return pastMeetingsIndex.entry(forEmail: email)
    }

    func participantSuggestions(matching query: String, excluding selectedParticipants: [Participant], limit: Int = 6) -> [PersonIndexEntry] {
        PeopleIndex(entries: peopleIndexEntries).suggestions(
            matching: query,
            excluding: selectedParticipants,
            limit: limit
        )
    }

    func personEntry(for participant: Participant) -> PersonIndexEntry? {
        PeopleIndex(entries: peopleIndexEntries).entry(for: participant)
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
    var noteDate: Date? { presenter?.note.date }
    var noteEnd: Date? { presenter?.note.end }
    var noteLocationText: String? { presenter?.note.locationText }
    var noteMeetingLink: String? { presenter?.note.meetingLink }
    var noteTranscribe: Bool? { presenter?.note.transcribe }
    var noteLocalOnlyValue: Bool? { presenter?.note.localOnly }
    var noteCrmPushEnabled: Bool { presenter?.note.crmPushOptOut != true }
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
        noteInPerson = p.note.inPerson
        noteLocalOnly = p.note.localOnly
        refreshPeopleIndexFromStoreIfPossible()
        refreshCrmStatus()
    }

    private func refreshPeopleIndexFromStoreIfPossible() {
        guard let noteStore = store as? NoteStore,
              let notes = try? noteStore.list() else { return }
        rebuildPeopleSources(notes: notes)
    }

    private func rebuildPeopleSources(notes: [MeetingNote]) {
        indexedNotes = notes
        let activeNoteID = presenter?.note.id
        let indexNotes = notes.filter { $0.id != activeNoteID }
        let pastIndex = PastMeetingsIndex(notes: indexNotes)

        var sources: [any PeopleSource] = []
        #if canImport(Contacts)
        sources.append(AppleContactsSource())
        #endif
        if let crmPeopleSource {
            sources.append(crmPeopleSource)
        }
        sources.append(pastIndex)

        pastMeetingsIndex = pastIndex
        peopleDirectory = PeopleDirectory(sources: sources)
        peopleIndexEntries = PeopleIndex(notes: indexNotes, events: availableEvents).entries
        refreshCrmStatus()
    }

    private func peoplePickerPresenter(excluding selectedParticipants: [Participant]) -> PeoplePickerPresenter {
        PeoplePickerPresenter(
            directory: peopleDirectory,
            eventAttendees: linkedEventAttendees(),
            alreadyAdded: selectedParticipants
        )
    }

    private func linkedEventAttendees() -> [Participant] {
        guard let eventID = presenter?.note.calendarEvent else { return [] }
        return availableEvents.first(where: { $0.id == eventID })?.participants ?? []
    }

    private func refreshCrmStatus() {
        guard let note = presenter?.note else {
            crmBannerText = nil
            return
        }
        crmBannerText = crmStatusPresenter.bannerText(
            meetingId: note.id,
            crmConnected: crmConnected,
            unmatchedParticipants: unmatchedCrmParticipants(in: note)
        )
    }

    private func unmatchedCrmParticipants(in note: MeetingNote) -> [Participant] {
        guard crmConnected else { return [] }
        let knownRemoteIds = knownCrmRemoteIds()
        return note.participants.filter { participant in
            if let crmRemoteId = normalizedCrmRemoteId(participant.crm),
               knownRemoteIds.contains(crmRemoteId) {
                return false
            }
            guard let email = participant.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
                return true
            }
            return crmRemoteId(forEmail: email) == nil
        }
    }

    private func autoMatchedParticipant(_ participant: Participant) -> Participant {
        guard participant.crm?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty == nil,
              let email = participant.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
              let remoteId = crmRemoteId(forEmail: email) else {
            return participant
        }
        return Participant(name: participant.name, email: participant.email, crm: remoteId)
    }

    private func crmRemoteId(forEmail email: String) -> String? {
        guard let person = peopleDirectory.person(forEmail: email) else { return nil }
        return person.sourceRefs.lazy.compactMap { sourceRef in
            guard sourceRef.provider == "crm" else { return nil }
            return normalizedCrmRemoteId(sourceRef.remoteId)
        }.first
    }

    private func knownCrmRemoteIds() -> Set<String> {
        Set(peopleDirectory.people(fromProvider: "crm").flatMap { person in
            person.sourceRefs.compactMap { sourceRef in
                guard sourceRef.provider == "crm" else { return nil }
                return normalizedCrmRemoteId(sourceRef.remoteId)
            }
        })
    }

    private func normalizedCrmRemoteId(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
