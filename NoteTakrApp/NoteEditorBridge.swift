import Foundation
import NoteTakrKit

/// ObservableObject wrapper around Kit's `NoteEditorViewModel`.
/// SwiftUI views bind to the published properties; edits are forwarded
/// back into the view model.
final class NoteEditorBridge: ObservableObject {
    @Published private(set) var title: String = ""
    @Published private(set) var body: String = ""

    let viewModel: NoteEditorViewModel

    init(store: any NoteStoring, onDidSave: ((String) -> Void)? = nil) {
        viewModel = NoteEditorViewModel(
            store: store,
            scheduler: FoundationScheduler(),
            onDidSave: onDidSave
        )
        viewModel.onChange = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.title = self.viewModel.title
                self.body = self.viewModel.body
            }
        }
    }

    func setTitle(_ newTitle: String) {
        viewModel.setTitle(newTitle)
    }

    func setBody(_ newBody: String) {
        viewModel.setBody(newBody)
    }
}
