# Plan: Recording / transcription / window fixes (Agent 3)

Goal: fix the buggy record-pill + transcription state, stop the surprise keychain prompt,
make a new note never look "transcribed," keep the panel from vanishing on new-note, and
make closing the window reliable.

## Owned files (do NOT edit anything else)
- `NoteTakrApp/NotePanelController.swift`
- `NoteTakrKit/Sources/NoteTakrKit/RecordPillStateMachine.swift`
- `NoteTakrApp/AppModel.swift`
- `NoteTakrApp/Views/SettingsView.swift`

Do NOT touch the markdown/editor files, the switcher view-model/overlay/bridge, `NoteStore.swift`, `MarkdownSyntaxAnalyzer.swift`, `Package.swift`, or pbxproj. Add NO new files.

## Tasks
### Pill state leaks across notes (shows "Transcribed" on a brand-new note)
- `RecordPillStateMachine`: add `public func reset()` that transitions to `.idle` unconditionally.
- `NotePanelController.loadNote(...)`: call `recordPillMachine.reset()` (instead of relying on `cancelBusyPipeline()`, which only resets busy states) so every note opens at `.idle`/Record. Keep `pillPipelineCancellables.removeAll()`.

### Instant "Transcribed" on a fresh recording
- In `handlePostStopTerminal`, the `.empty` branch currently always finishes as `.doneTranscript`. Distinguish "transcription actually ran and found no speech" from "nothing happened": only treat `.empty` as a real terminal outcome if a `.generating` state was observed first (i.e. transcription truly started). If transcription never started, return the pill to `.idle` instead of `.doneTranscript`. (Track this in `drivePostStopPipeline`, e.g. require the publisher to pass through `.generating` before accepting `.empty`/`.failed`/segments, or capture a "did transcribe start" flag.)

### Surface transcription failures instead of hiding them
- Confirm the `.failed` path reaches the UI (it sets `TranscriptState.failed` → Transcript tab shows the error). When transcription yields nothing because the model is unavailable, the user must see a clear message (e.g. "Speech model not downloaded" / the real error) rather than a silent "Transcribed". Map `TranscriptionError.modelUnavailable` to a friendly message in the failure surfaced to the transcript tab.

### Surprise keychain prompt (`com.notetakr.openrouter`)
- The key is read eagerly: `SettingsView`'s `SummarizationViewModel.init()` / `reload()` call `keychain.hasValue`, and `AppModel.autoSummarizeIfNeeded` calls `keychainStore.hasValue` on every transcript completion. Make keychain access lazy: do NOT read the keychain on Settings view init or app launch. Only read it when the user (a) opens the summarization section and explicitly checks, (b) taps Generate/summarize, or (c) saves a key. Avoid `SecItemCopyMatching` running unprompted. If a "is a key configured?" flag is needed for UI, prefer a cached/lightweight check that doesn't prompt, or defer it behind a user action.

### New note must not hide/close the panel
- Reproduce: creating a note (⌘N `createNewNote`, switcher `onCreateBlankNote`) only dismisses the switcher overlay; the panel should stay visible and key. Ensure `loadNote`/createNewNote re-asserts the panel front (`makeKeyAndOrderFront`) if needed and that nothing orders it out. Fix any focus/ordering glitch that makes it look like the window closed.

### Reliable window close
- Wire `⌘W` to hide the panel (`orderOut`). Keep ESC behavior (close settings → close switcher → then hide). Make sure the native close button reliably hides the panel.

### Wire delete-note (contract with Agent 2)
- In `wireSwitcher()`, set `switcherBridge.onDeleteNote = { [weak self] deletedID in ... }`: if the deleted note is the currently-open one, load another note (or create a blank one) so the editor isn't showing a deleted note. Agent 2 adds `onDeleteNote` + `deleteNote(_:)` + `NoteStore.delete(id:)`; assume those exist.

## Checklist
- [x] `RecordPillStateMachine.reset()` added; `loadNote` resets pill to `.idle`.
- [x] Fresh recording no longer instantly shows "Transcribed" (require `.generating` before `.empty` is terminal; else back to `.idle`).
- [x] Transcription failures (incl. model unavailable) show a clear message in the Transcript tab.
- [x] Keychain no longer read on app launch / Settings init; only on explicit summarize/save.
- [x] Creating a new note keeps the panel visible/front (no perceived close).
- [x] ⌘W closes the window; ESC + native close button work reliably.
- [x] `switcherBridge.onDeleteNote` wired so deleting the open note reloads the editor.
- [x] `cd NoteTakrKit && swift build` passes. Do NOT run the full xcodebuild.
- [x] Check every box above as you finish.

## Acceptance
A brand-new note opens at "Record" (not Transcribing/Transcribed). Recording then stopping either shows a real transcript, a clear failure message, or returns to Record — never an instant fake "Transcribed". No keychain prompt appears unless you summarize/save a key. Creating a note keeps the window open; ⌘W / close button / ESC reliably close it.
