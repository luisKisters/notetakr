# Plan: NoteTakr floating-window redesign

## Overview

Rebuild NoteTakr's UI as one floating macOS panel (~420×620): markdown meeting notes with
YAML frontmatter, chips + expandable property panel, footer tabs (Private Notes · Summary ·
Transcript), a ⌘K "Timeline Lite" switcher merged with the calendar, an icon-tab settings
sheet (per-meeting overrides vs. general defaults), Glass/Dark/Light appearance, and a
global hotkey — then cut over from the legacy main window.

Read FIRST, in every session:
- `docs/DESIGN.md` — product/visual/architecture principles, the Kit/Core/App layer rules,
  the frontmatter schema, and the Linux + GitHub-macOS-runner execution model. It is binding.
- `ideas.md` at the repo root (locked spec summary, formerly `design/mockups/IDEAS.md`) and the relevant `design/mockups/final-*.html`
  for the screen being built.

Execution environment: **Linux with Swift installed**. macOS compilation/tests happen ONLY on
the GitHub Actions macOS runner (workflow `.github/workflows/macos-ci.yml`). Anything in
`NoteTakrKit/` is built and tested locally; anything in `Sources/NoteTakrCore` or
`NoteTakrApp/` is validated by pushing and watching CI with `gh`. Do not run `xcodebuild`,
the app, or anything AppKit locally. The legacy UI must keep building until Task 17.

Existing code to reuse (do not rewrite): `Sources/NoteTakrCore` (SessionStore, MeetingSession,
TranscriptionService/FluidAudio adapters, OpenRouterClient/SummarizationService, VocabularyStore,
MeetingDetector, CalendarEvent/CalendarAdapter), `NoteTakrApp/` (AppModel, EventKitCalendarAdapter,
NativeAudioRecorder, StatusBarController, existing views/tests).

## Validation Commands

Run after every task (Kit loop, works on Linux):

```bash
cd NoteTakrKit && swift build && swift test
```

For tasks touching `Sources/NoteTakrCore`, `NoteTakrApp/`, `Notetakr.xcodeproj`, or
`.github/workflows/` — push and gate on the macOS runner:

```bash
git push origin HEAD
RUN_ID=$(gh run list --branch "$(git branch --show-current)" --workflow macos-ci.yml --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$RUN_ID" --exit-status   # on failure: gh run view "$RUN_ID" --log-failed
```

### Task 1: Scaffold NoteTakrKit package and layered CI

- [x] Create `NoteTakrKit/` as a standalone SPM package (swift-tools 5.9): library target
      `NoteTakrKit` (Foundation only — no AppKit/Combine/FluidAudio) and test target
      `NoteTakrKitTests`, with a placeholder type + one passing test.
- [x] Add the local package to the root `Package.swift` (`.package(path: "NoteTakrKit")`) and
      make `NoteTakrCore` depend on the `NoteTakrKit` product. Add the package reference to
      `Notetakr.xcodeproj` so the app target can import it (edit `project.pbxproj` carefully:
      XCLocalSwiftPackageReference + product dependency on the NoteTakr target).
- [x] Add an `ubuntu-latest` job `kit-tests` to `.github/workflows/macos-ci.yml` running
      `cd NoteTakrKit && swift test` (use `swift-actions/setup-swift` or the `swift:6.0`
      container); make both macOS jobs `needs: kit-tests`.
- [x] Validate: Kit tests pass locally; push and confirm the full workflow (ubuntu + both
      macOS jobs) is green via `gh run watch`.

### Task 2: Frontmatter model and serializer (Kit)

- [x] In NoteTakrKit, add `MeetingNote`: the frontmatter fields from the schema in
      `docs/DESIGN.md` §3 (id, title, date, end, calendar_event, participants
      [name + optional email], location enum zoom|meet|teams|in-person|none, in_person,
      transcribe, language auto|code, vocabulary) plus `body: String`.
- [x] Add `FrontmatterSerializer` with `parse(fileText:) -> MeetingNote` and
      `render(note:) -> String`. Hand-rolled YAML subset: lenient parse (flow `[a, b]` and
      block `- item` lists, quoted/unquoted scalars, `Name <email>` participant form,
      unknown keys preserved verbatim on re-render), canonical emit (fixed key order,
      ISO8601 dates with timezone). Files without frontmatter parse as body-only notes.
- [x] Tests: round-trip every field; umlauts/em-dashes/quotes/colons in titles; unknown-key
      preservation; body containing `---` lines; empty body; missing optional keys;
      body-only file; malformed frontmatter degrades to body-only without throwing.
- [x] Validate (Kit loop), commit, push.

### Task 3: NoteStore with legacy migration (Kit)

- [x] In NoteTakrKit, add `NoteStore` operating on a root directory (injected URL): list all
      notes (folders containing `note.md`), load, save (atomic write), create (folder name
      `YYYY-MM-DD_sanitized-title_shortid` — port the sanitization rules from
      `Sources/NoteTakrCore/Storage/SessionStore.swift` into Kit), rename folder on title
      change preserving other files.
- [x] Migration: a folder with `session.json` but no frontmatter in `note.md` gets
      frontmatter synthesized on first load — read the JSON leniently via a Kit-local
      `LegacySessionMetadata` Codable (id, title, date, linkedEventID, linkedEventTitle,
      participants). Idempotent: second load does not rewrite. Never modify `session.json`.
- [x] Tests against real temp directories: CRUD; listing sorted by date desc; rename keeps
      sibling files (fake `.m4a` fixtures); migration from a fixture `session.json`
      (copy a real shape from `Tests/NoteTakrCoreTests/SessionStoreTests.swift`);
      idempotency; corrupt `session.json` → body-only note, no crash.
- [x] Validate (Kit loop), commit, push.

### Task 4: NoteEditorViewModel (Kit)

- [x] In NoteTakrKit, add `NoteEditorViewModel`: plain class, no Combine — change
      notification via a `onChange: (() -> Void)?` callback (App will bridge to SwiftUI).
      API: `load(noteID:)` exposing `title`/`body`; edits mark dirty and schedule a save
      through an injected `Scheduler` protocol (debounce 1s); `flush()` saves immediately
      (used on tab switch/panel hide); title commit triggers store rename.
- [x] Tests with a virtual `TestScheduler`: typing twice within the window → exactly one
      save; flush cancels pending debounce and saves once; title change persists + renames
      via store spy; loading a new note flushes the previous one; no save when not dirty.
- [x] Validate (Kit loop), commit, push.

### Task 5: Floating panel with editor (App — CI-validated)

- [x] In NoteTakrApp, add `NotePanelController`: an NSPanel 420×620, corner radius 16,
      floating level, resizable within reason, closable with esc. Set `collectionBehavior`
      BEFORE showing the panel (a known launch-abort crash — see git history/memory note).
      Menu bar gains "Open Note Panel" which shows the panel with the most recent note (or
      creates "Untitled meeting" if none).
- [x] Add `EditorView` (SwiftUI, hosted in the panel): hidden chrome title, H1 title
      TextField, plain `TextEditor` body — bound to Kit's `NoteEditorViewModel` through a
      small `ObservableObject` bridge that forwards `onChange`. Per the mockups: dark
      default for now (appearance system arrives in Task 15), generous padding, no footer
      content yet.
- [x] App-target tests (`NoteTakrTests/`): panel creation does not crash and is key-able;
      the bridge forwards edits to the Kit view model (spy store); legacy main window still
      launches.
- [x] Validate: Kit loop locally, then push and gate on `gh run watch` (both macOS jobs
      green). Commit message notes the panel feature.

### Task 6: FrontmatterPresenter — chips and properties (Kit)

- [x] In NoteTakrKit, add `FrontmatterPresenter` (injected `now: () -> Date`): exposes
      `chips: [Chip]` (time range "14:00–14:45"; location label — "Zoom"/"In person"/…;
      "N people" only when participants exist; REC chip with elapsed "12:34" only while
      recording) and `propertyRows: [PropertyRow]` (Date, Calendar event, Participants,
      Location, In-person, Transcript) for the expanded panel; `isExpanded` toggle state.
- [x] Mutations persisting through `NoteStore`: `setInPerson(_:)`,
      `linkEvent(_ event: LinkedEventInfo)` (sets calendar_event + title + merges
      participants), `unlinkEvent()`, `addParticipant(_:)` / `removeParticipant(_:)`.
- [x] Tests: chip matrix (full/partial/empty metadata, in-person, cross-midnight range);
      elapsed formatting (0:09 / 12:34 / 1:02:03); each mutation reflected in the rendered
      `note.md` (temp-dir store); unlink clears event but keeps manually added participants.
- [x] Validate (Kit loop), commit, push.

### Task 7: Chips row and property panel UI (App — CI-validated)

- [x] Add `ChipsRowView` under the title in `EditorView`: quiet chips per the final mockup
      (SF Symbols ~1.5pt stroke: clock, video, person.2; avatar-initial circles for up to 3
      participants; pulsing red REC dot), faint chevron, whole row toggles expansion.
- [x] Add `PropertyPanelView`: hairline rows (icon + muted label left, value right), purple
      toggle for In-person, quiet Unlink text button. Animate expand/collapse.
- [x] Both views bind to `FrontmatterPresenter` via the ObservableObject bridge; calendar
      linking UI reuses `AppModel.eventsNear(_:)` for candidates.
- [x] App-target tests: bridge round-trip (toggle in-person from the view model → file
      changes via spy); chips view model state for a fixture note matches the Kit presenter.
- [x] Validate: Kit loop + push + `gh run watch` green. Commit.

### Task 8: NoteTabsPresenter — Private Notes / Summary / Transcript (Kit)

- [x] In NoteTakrKit, add `NoteTabsPresenter`: `selectedTab` (persists per note id in-memory),
      tab content states — `privateNotes` (editor passthrough), `summary(SummaryState)`
      (`missing | generating | ready(String) | failed(String)`), `transcript(TranscriptState)`
      (`empty | segments([DisplaySegment])`).
- [x] `DisplaySegment` grouping: consecutive same-speaker raw segments (speaker?, timestamp,
      text — generic input structs, not Core types) merge into one display segment with
      `mm:ss` start stamp.
- [x] Summary generation drives an injected `SummaryGenerating` protocol (async, returns
      String or throws) with state transitions missing → generating → ready/failed; a
      `onPersist(String)` hook lets Core write it to `session.json` later.
- [x] Tests: state matrices for notes with/without transcript and summary; grouping fixtures
      (speaker changes, nil speakers, out-of-order timestamps sorted); generate happy path +
      failure surfaces message and allows retry; switching tabs calls editor `flush()`
      (injected hook) exactly once.
- [x] Validate (Kit loop), commit, push.

### Task 9: Footer tabs, Summary and Transcript views (App — CI-validated)

- [x] Add the footer to `EditorView` per the final mockup: ONLY three bare text tabs
      `Private Notes · Summary · Transcript`, centered, generous spacing, active purple /
      inactive 45% opacity, no separators, no word count.
- [x] Add `SummaryView` (markdown text; when `missing`: quiet "Generate summary" button;
      `generating`: spinner; `failed`: message + retry) and `TranscriptView` (quiet rows:
      speaker name, mm:ss muted, text) bound to `NoteTabsPresenter`.
- [x] Wire `SummaryGenerating` to the existing `SummarizationService`/`OpenRouterClient`
      (key from `KeychainStore`, settings from `SummarizationSettingsStore`), persisting the
      result into the session's `session.json` and re-rendering `note.md` as today. Wire
      transcript input from the session's `transcriptSegments`.
- [x] App-target tests: presenter wiring with a fake `SummaryGenerating`; transcript mapping
      from a fixture `MeetingSession` into display segments; tab switch flushes editor.
- [x] Validate: Kit loop + push + `gh run watch` green. Commit.

### Task 10: SwitcherViewModel — Timeline Lite (Kit)

- [x] In NoteTakrKit, add `SwitcherViewModel` (injected: note list provider, upcoming-events
      provider via a Kit-local `UpcomingEvent` struct, `now()`): merges notes + events into
      day groups (Upcoming/Tomorrow first, then Today, Yesterday, weekday names, then dates)
      in timeline order (future ascending, past descending); per-item dot state
      `upcoming | current | past`; events already linked to a note are not duplicated.
- [x] Search: case- and diacritic-insensitive over title + participant names ("muller"
      matches "Müller"). Keyboard model: up/down moves selection across groups (skipping
      headers) with wrap; `open()` returns the selected note id; `createNote(from: event)`
      builds a note with title/date/end/calendar_event/participants prefilled and general
      defaults materialized (defaults provider injected; until Task 12 use a stub protocol).
- [x] Tests: grouping/order fixtures; ghost de-duplication; search matrix incl. diacritics;
      selection wrap; create-from-event frontmatter exact-match and the new note appearing
      as `current`.
- [x] Validate (Kit loop), commit, push.

### Task 11: ⌘K switcher overlay (App — CI-validated)

- [x] In the panel, ⌘K toggles `SwitcherOverlayView`: a frost layer (ultraThinMaterial +
      dark scrim) over the editor, search field on top, day-grouped rows with the 1px
      timeline rail (fading at both ends via mask) and node dots per state, dashed ghost
      rows with "+ Create note", kbd hint footer ("↩ Open · ⌘N New · esc"), per
      `final-switcher.html`.
- [x] Keys: ⌘K toggle, esc closes and returns focus to the editor, ↩ opens selection,
      ⌘N creates a blank note. Events provider bridges `EventKitCalendarAdapter` results
      into Kit's `UpcomingEvent`.
- [x] App-target tests: ⌘K toggles overlay state; esc restores editor focus; selecting a
      ghost event calls `createNote(from:)` and the panel switches to the new note.
- [x] Validate: Kit loop + push + `gh run watch` green. Commit.

### Task 12: AppSettingsStore and effective settings (Kit)

- [x] In NoteTakrKit, add `AppSettingsStore` (JSON file `settings.json` in the injected
      root): `transcribeByDefault` (default true), `defaultLanguage` (`auto` |
      fixed ISO code, default auto), `inPersonByDefault` (false), `appearance`
      (`glass|dark|light`, default glass), `hotkey` (string combo, default "⌃⌥⌘N"),
      `launchAtLogin` (false), `notesFolderPath` (optional override).
- [x] Add `EffectiveMeetingSettings.resolve(note:defaults:)` — note frontmatter values win
      when present. Warning rule: `languageWarning == (defaultLanguage != .auto)` with the
      exact copy "Meetings in any other language will be transcribed incorrectly.
      Auto-detect is recommended." Per-meeting vocabulary merge: note `vocabulary` +
      enabled global entries, deduped case-insensitively.
- [x] Replace Task 10's defaults stub so `createNote(from:)` materializes these defaults.
- [x] Tests: store round-trip + defaults when file missing/corrupt; resolution matrix;
      warning rule both ways; new-note inheritance; vocabulary merge dedupe.
- [x] Validate (Kit loop), commit, push.

### Task 13: Settings sheet UI (App — CI-validated)

- [x] Hovering the panel shows a gear top-right; clicking opens `SettingsSheetView`: bottom
      sheet ~85% height over the dimmed note, NO grabber, icon tabs `This Meeting · General ·
      Recording · Vocabulary · Permissions`, footer row with quiet "Close" + `esc` kbd pill,
      per `final-settings.html`.
- [x] This Meeting tab: purple scope banner ("<title> — these settings apply only to this
      note"), Transcribe-this-meeting toggle (live ● timer while recording), language picker,
      In-person toggle, linked event row + Unlink, per-meeting vocabulary editor — all
      writing to the note's frontmatter via Kit presenters.
- [x] General tab: "Defaults for new meetings" section (transcribe toggle, language picker
      defaulting to Auto-detect with the warning from Kit's rule when fixed, in-person
      toggle) + "App" section (hotkey field — display-only until Task 15, launch at login,
      Appearance segmented control — display-only until Task 15, notes folder + Change…).
      Recording/Vocabulary/Permissions tabs: rehost the existing SettingsView sections
      (`TranscriptionModelSettings` picker, `VocabularyViewModel` list,
      `AudioPermissionManager` rows).
- [x] App-target tests: sheet view model — banner only on This Meeting; This-Meeting edits
      write frontmatter (spy) and never touch `settings.json`; General edits write
      `settings.json` and never touch the open note; warning visibility matches Kit rule.
- [x] Validate: Kit loop + push + `gh run watch` green. Commit.

### Task 14: Theme tokens and HotkeyCombo (Kit)

- [x] In NoteTakrKit, add `Theme` token table for `glass|dark|light`: background, elevated
      fill, primary/secondary text, hairline, accent, destructive — as platform-neutral RGBA
      values matching the final mockups (dark `#151417`, purple `#8B5CF6`/`#A78BFA`, warm
      paper light). Exhaustive: every token defined for every mode (enum-driven, compiler +
      test enforced).
- [x] Add `HotkeyCombo`: parse/format symbols ("⌃⌥⌘N" ⇄ modifiers + key), reject combos
      without a modifier or with unknown keys; Codable as the display string (used by
      `AppSettingsStore.hotkey`).
- [x] Tests: token completeness across modes; combo round-trip for all modifier subsets;
      invalid inputs ("N", "⌘", "⌃⌥⌘♞") rejected; lowercase/uppercase normalization.
- [x] Validate (Kit loop), commit, push.

### Task 15: Appearance system and global hotkey (App — CI-validated)

- [x] Apply Kit `Theme` tokens through SwiftUI environment: Glass = NSVisualEffectView
      behind the content (`.hudWindow`-style material) + subtle grain overlay; Dark/Light =
      solid token backgrounds. The Appearance control in General re-skins the open panel
      live; persists via `AppSettingsStore`.
- [x] Global hotkey: `HotkeyRegistering` protocol + Carbon `RegisterEventHotKey`
      implementation; register from `AppSettingsStore.hotkey` at launch, re-register on
      change via the (now editable) recorder field in General. Hotkey toggles the panel:
      hidden → show + focus editor; visible → hide (flushing pending saves). Keep the panel
      toggle logic in a plain `PanelToggleCoordinator` class for testability.
- [x] App-target tests: `PanelToggleCoordinator` state machine with a fake registrar
      (toggle/show/hide/flush-called); appearance change applies exactly one re-skin;
      hotkey re-registration on settings change.
- [x] Validate: Kit loop + push + `gh run watch` green. Commit.

### Task 16: RecordingNoteBridge (Kit)

- [x] In NoteTakrKit, add `RecordingNoteBridge`: connects a recording lifecycle (injected
      protocol: start/stop events + elapsed) to note state — start marks the note live
      (drives the REC chip), stop clears live state and requests transcription ONLY when
      `EffectiveMeetingSettings.transcribe` is true, passing the resolved language and the
      merged vocabulary to an injected `TranscriptionRequesting` protocol; completion flips
      the Transcript tab state via `NoteTabsPresenter`.
- [x] Tests: full transition fixture (idle → recording → transcribing → ready); failure
      path surfaces and is retryable; `transcribe:false` short-circuits (spy never called);
      fixed language and merged vocabulary are passed through verbatim; elapsed string
      matches the chip formatting from Task 6.
- [x] Validate (Kit loop), commit, push.

### Task 17: Recording wiring and legacy cutover (App — CI-validated)

- [x] Wire `RecordingNoteBridge` to the real pipeline: `RecordingManager`/
      `NativeAudioRecorder` events in, `TranscriptionService` (FluidAudio) as the
      `TranscriptionRequesting` impl, honoring per-meeting settings. REC chip ticks live;
      stopping populates the Transcript tab; auto-summary respects
      `SummarizationSettings.autoSummarize` as today.
- [x] Cutover: delete `MainWindowView`, `SessionsView` split, `SessionDetailPane`,
      `SessionDetailView`, `TodayView`, and the `Window` scene — the panel is the only UI.
      Slim the menu bar to: Toggle Note Panel, Start/Stop Recording, Open Notes Folder,
      Settings…, Quit. First-launch permission prompts route to the sheet's Permissions tab.
      Update or delete app tests referencing removed views; keep `AppModel` only as the
      shrunken pipeline owner.
- [x] App-target integration test with fakes: launch → exactly one panel, no legacy window;
      mock-recorder full cycle ends with a populated Transcript tab and an updated `note.md`.
- [x] Update `README`/docs references to the removed UI; move this plan's learnings into
      `docs/DESIGN.md` if any principle changed.
- [x] Validate: Kit loop + push + `gh run watch` green (all three CI jobs). Commit.

## Success Criteria

All 17 tasks complete with green CI on `main`'s workflow (ubuntu kit-tests + macOS package
tests + macOS Xcode build-and-test). The app presents a single floating panel matching
`design/mockups/final-*.html` in structure and behavior; notes round-trip through
frontmatter; the legacy window code is gone. Human visual review on a Mac is the final gate
for styling fidelity (not part of this plan's automated criteria).
