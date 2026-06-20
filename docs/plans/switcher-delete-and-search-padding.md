# Plan: Switcher polish + delete notes (Agent 2)

Goal: (1) the ⌘K switcher "Search meetings…" field should sit flush at the top of the
window (no weird top gap); (2) the user must be able to delete notes.

## Owned files (do NOT edit anything else)
- `NoteTakrApp/Views/SwitcherOverlayView.swift`
- `NoteTakrKit/Sources/NoteTakrKit/SwitcherViewModel.swift`
- `NoteTakrApp/SwitcherBridge.swift`
- `NoteTakrKit/Sources/NoteTakrKit/NoteStore.swift`
- `NoteTakrApp/Views/WindowChromeView.swift` (only if needed for the delete affordance; otherwise leave it)

Do NOT touch `NotePanelController.swift` (Agent 3 wires the delete callback), `EditorView.swift`, `MarkdownSyntaxAnalyzer.swift`, `Package.swift`, or pbxproj. Add NO new files.

## Tasks
### Search field flush to top
- In `SwitcherOverlayView.swift` the overlay VStack has `.padding(.top, 46)` — that's the gap. Reduce it so the search field is near the very top of the window (use a small top padding, ~12–16, that clears the native close button area). Verify the search bar no longer looks "weirdly spaced."

### Delete notes
- `NoteStore` has no delete. Add:
  ```swift
  public func delete(id: String) throws
  ```
  Remove the note's directory/file (mirror the load/save path logic in this file). Be safe if it doesn't exist.
- `SwitcherViewModel`: add a way to remove a note from the in-memory list and refresh results after deletion (so the row disappears immediately). Add whatever method the overlay needs, e.g. `deleteSelectedNote()` / `delete(noteID:)`.
- `SwitcherBridge`: add `var onDeleteNote: ((String) -> Void)?` and a `func deleteNote(_ id: String)` that calls the view-model removal AND `onDeleteNote?(id)`. **The callback name MUST be exactly `onDeleteNote`** — Agent 3 wires it in the controller.
- `SwitcherOverlayView`: add a delete affordance on note rows — a trash button that appears on row hover, AND/OR a `⌘⌫` / `delete` key handler on the selected row. Tapping it calls `bridge.deleteNote(id)`. Only notes (`.note` kind) are deletable — not events or commands. Confirm-on-delete is NOT required (keep it snappy), but make the hit target small so it isn't fired by accident.

## Checklist
- [x] Remove the top gap; search field flush near the top of the window.
- [x] `NoteStore.delete(id:)` added and removes the note from disk.
- [x] `SwitcherViewModel` removes the note from its list + refreshes results.
- [x] `SwitcherBridge.onDeleteNote` callback + `deleteNote(_:)` added (exact name `onDeleteNote`).
- [x] Switcher row delete affordance (hover trash button and/or delete-key) wired to `bridge.deleteNote(id)`, notes only.
- [x] `cd NoteTakrKit && swift build` passes. Do NOT run the full xcodebuild.
- [x] Check every box above as you finish.

## Acceptance
Open ⌘K: the search field is at the top with no odd gap. Hovering a note row shows a delete control; using it removes the note from the list and from disk. Agent 3's controller will react to `onDeleteNote` to reload the editor if the open note was deleted.
