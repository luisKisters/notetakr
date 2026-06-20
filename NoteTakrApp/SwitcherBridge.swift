import Foundation
import NoteTakrKit

/// ObservableObject wrapper around Kit's SwitcherViewModel.
/// Drives the ⌘K overlay: toggle, dismiss, selection navigation, and note creation.
@MainActor
final class SwitcherBridge: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var groups: [SwitcherGroup] = []
    @Published var selectedIndex: Int = 0
    @Published var searchQuery: String = "" {
        didSet {
            if searchQuery != oldValue {
                viewModel.searchQuery = searchQuery
            }
        }
    }

    let viewModel: SwitcherViewModel

    /// Called when a note is selected or created — controller loads the note.
    var onOpenNote: ((String) -> Void)?
    /// Called when overlay dismisses — controller returns focus to the editor.
    var onEditorFocusRequest: (() -> Void)?
    /// Called when ⌘N is pressed or the New note command is activated.
    var onCreateBlankNote: (() -> Void)?
    /// Called when the Open Settings command is activated from the switcher.
    var onOpenSettings: (() -> Void)?
    /// Called after a note is deleted from the switcher — controller reloads the editor
    /// if the deleted note was the one currently open.
    var onDeleteNote: ((String) -> Void)?

    init(viewModel: SwitcherViewModel) {
        self.viewModel = viewModel
        viewModel.onChange = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.groups = self.viewModel.groups
                self.selectedIndex = self.viewModel.selectedIndex
            }
        }
        groups = viewModel.groups
        selectedIndex = viewModel.selectedIndex
    }

    // MARK: - Toggle / show / dismiss

    func toggle() {
        if isVisible { dismiss() } else { show() }
    }

    func show() {
        searchQuery = ""
        viewModel.searchQuery = ""
        viewModel.reload(resetSelection: true)
        groups = viewModel.groups
        selectedIndex = viewModel.selectedIndex
        isVisible = true
    }

    func dismiss() {
        isVisible = false
        searchQuery = ""
        onEditorFocusRequest?()
    }

    // MARK: - Navigation

    func moveUp() { viewModel.moveUp() }
    func moveDown() { viewModel.moveDown() }

    // MARK: - Actions

    /// Opens the selected note, creates one from a ghost calendar event, or executes a command.
    func openOrCreateSelected() {
        guard let item = viewModel.selectedItem else {
            dismiss()
            return
        }
        switch item.kind {
        case .note(let id, _, _, _):
            onOpenNote?(id)
            dismiss()
        case .event(let ev):
            if let note = try? viewModel.createNote(from: ev) {
                onOpenNote?(note.id)
                dismiss()
            }
        case .command(let cmd):
            switch cmd.id {
            case .openSettings:
                dismiss()
                onOpenSettings?()
            case .newNote:
                dismiss()
                onCreateBlankNote?()
            }
        }
    }

    /// Opens a specific ghost event row directly (tap or ↩ on that row).
    func openOrCreate(event: UpcomingEvent) {
        if let note = try? viewModel.createNote(from: event) {
            onOpenNote?(note.id)
            dismiss()
        }
    }

    /// Triggers ⌘N blank-note creation via the controller callback.
    func triggerCreateBlankNote() {
        onCreateBlankNote?()
        dismiss()
    }

    /// Deletes a note: removes it from disk + the in-memory list (so the row vanishes),
    /// then notifies the controller so it can reload the editor if needed.
    func deleteNote(_ id: String) {
        viewModel.delete(noteID: id)
        groups = viewModel.groups
        selectedIndex = viewModel.selectedIndex
        onDeleteNote?(id)
    }
}

// MARK: - CalendarEventsProvider

/// Holds a snapshot of upcoming calendar events converted from Core CalendarEvent.
/// Updated by NotePanelController before the overlay opens.
final class CalendarEventsProvider: UpcomingEventsProviding {
    var events: [UpcomingEvent] = []
    func listEvents() -> [UpcomingEvent] { events }
}

// MARK: - NoteStoreListProvider

/// Adapts NoteStore.list() to the NoteListProviding protocol.
struct NoteStoreListProvider: NoteListProviding {
    let store: NoteStore
    func listNotes() -> [MeetingNote] { (try? store.list()) ?? [] }
}
