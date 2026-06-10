import Foundation
import NoteTakrKit

@MainActor
final class NoteTabsBridge: ObservableObject {
    @Published private(set) var selectedTab: NoteTab = .privateNotes
    @Published private(set) var summaryState: SummaryState = .missing
    @Published private(set) var transcriptState: TranscriptState = .empty

    let presenter: NoteTabsPresenter
    private(set) var currentNoteID: String?

    init(presenter: NoteTabsPresenter) {
        self.presenter = presenter
        presenter.onChange = { [weak self] in
            guard let self else { return }
            if Thread.isMainThread {
                self.refresh()
            } else {
                DispatchQueue.main.async { [weak self] in self?.refresh() }
            }
        }
    }

    func load(noteID: String) {
        currentNoteID = noteID
        refresh()
    }

    func selectTab(_ tab: NoteTab) {
        guard let id = currentNoteID else { return }
        try? presenter.selectTab(tab, for: id)
    }

    func generateSummary() {
        guard let id = currentNoteID else { return }
        presenter.generateSummary(for: id)
    }

    private func refresh() {
        guard let id = currentNoteID else { return }
        selectedTab = presenter.selectedTab(for: id)
        summaryState = presenter.summaryState(for: id)
        transcriptState = presenter.transcriptState(for: id)
    }
}
