import Foundation
import NoteTakrKit
import NoteTakrCore

/// ObservableObject wrapper around Kit's `FrontmatterPresenter`.
/// Call `load(note:)` whenever the active note changes.
@MainActor
final class FrontmatterPresenterBridge: ObservableObject {
    @Published private(set) var chips: [Chip] = []
    @Published private(set) var propertyRows: [PropertyRow] = []
    @Published var isExpanded: Bool = false
    @Published var calendarCandidates: [CalendarEvent] = []

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

    func linkEvent(_ event: CalendarEvent) {
        let info = LinkedEventInfo(
            eventID: event.id,
            title: event.title,
            participants: event.attendees
        )
        try? presenter?.linkEvent(info)
    }

    func unlinkEvent() {
        try? presenter?.unlinkEvent()
    }

    // MARK: - Private

    private func refresh() {
        guard let p = presenter else { return }
        chips = p.chips
        propertyRows = p.propertyRows
    }
}
