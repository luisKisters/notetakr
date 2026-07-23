import Foundation
import NoteTakrKit

@MainActor
final class NoteTabsBridge: ObservableObject {
    @Published private(set) var selectedTab: NoteTab = .privateNotes
    @Published private(set) var summaryState: SummaryState = .needsTranscript
    @Published private(set) var transcriptState: TranscriptState = .empty
    @Published private(set) var speakerResolutions: [String: SpeakerResolution] = [:]

    let presenter: NoteTabsPresenter
    private(set) var currentNoteID: String?

    var canGenerateTranscript: Bool {
        guard let currentNoteID else { return false }
        return presenter.canGenerateTranscript(for: currentNoteID)
    }

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

    func generateTranscript() {
        guard let id = currentNoteID else { return }
        presenter.generateTranscript(for: id)
    }

    func transcribeAndSummarize() {
        guard let id = currentNoteID else { return }
        presenter.transcribeAndSummarize(for: id)
    }

    private func refresh() {
        guard let id = currentNoteID else { return }
        selectedTab = presenter.selectedTab(for: id)
        summaryState = presenter.summaryState(for: id)
        transcriptState = presenter.transcriptState(for: id)
        speakerResolutions = presenter.speakerResolutions(for: id)
    }
}
