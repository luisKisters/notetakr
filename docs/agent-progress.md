# Agent Completion Report

## Project: Local-First macOS Meeting Notes MVP

### Summary

The meeting-notes-mvp branch is complete. All eight planned tasks were implemented and verified.

### What was built

- Native SwiftUI macOS menu-bar app (NoteTakrApp target, Swift 5.9, macOS 14+)
- Local JSON session storage with deterministic folder names and interrupted-session recovery
- EventKit calendar adapter (behind a protocol) with Google Meet / Zoom / Teams URL matching and keyword fallback
- AudioRecorder protocol with a mock recorder for CI and a NativeAudioRecorder (AVAudioRecorder + ScreenCaptureKit) for real hardware
- Permission handling screen for microphone and screen-recording access
- TranscriptionEngine protocol with a mock engine and FluidAudio adapter support for local Parakeet inference
- Vocabulary editor (phrases, aliases, boost weights, enabled toggle) with persistence
- Markdown note generation from session metadata, personal notes, and transcript segments
- macOS UserNotifications for pre-meeting reminders with a Start Recording action
- Accessibility identifiers on all important controls

### Verification status

- Linux-compatible test suite: 98 tests, 0 failures (all tasks)
- macOS GitHub Actions CI: passed on every task commit (see run history on meeting-notes-mvp branch)
- Real audio capture (NativeAudioRecorder / SystemAudioCapturer): NOT verified — requires a physical Mac; see docs/manual-smoke-test.md
- Local Parakeet transcription (FluidAudioAdapter): NOT verified — model download and inference are disabled in CI; requires a physical Mac with the model present

### No prohibited dependencies

No cloud service, login flow, browser extension, Electron dependency, or Tauri dependency was added. All data remains local.

### Remaining manual steps

1. Follow docs/manual-smoke-test.md on a physical Mac running macOS 14 or later.
2. Grant Calendar, Microphone, and Screen Recording permissions when prompted.
3. Confirm audible microphone and browser-audio recording produce separate local files.
4. Confirm note generation and session persistence after relaunch.
5. If all checks pass, merge meeting-notes-mvp into main.

---

## Project: Next Product Phase

### Summary

The next-product-phase branch is complete. All six planned tasks were implemented and verified. This phase transformed the working audio-capture foundation into a more production-ready meeting notes tool with stable builds, real transcription architecture, richer recording status, and polished permission UX.

### What was built

**Task 1 — Stabilize macOS Build and Signing**
- `scripts/build-macos-app.sh`: repeatable build script using `xcodebuild`, always outputs to `build/NoteTakr.app`, with `--install` flag for copying to `/Applications/` and `--config` flag for release builds
- Bundle identifier `com.notetakr.app` enforced consistently; TCC permissions survive rebuilds
- `docs/manual-smoke-test.md` updated with Xcode installation guide and build-script instructions

**Task 2 — Polish Permission UX**
- Settings opens as a standard foreground SwiftUI window (replaced custom floating NSWindow)
- Screen Recording now shows three distinct states: "Not Set", "Restart Required" (orange badge + explanation), "Granted" (green)
- "Restart App" button appears before "Open Settings" when restart is required
- `EKEventStore` made lazy so Calendar is never initialized on status checks at launch
- 10 new vocabulary tests and calendar-refresh test added

**Task 3 — Add Recording Source Status**
- `AudioSourceStatus` and `AudioSourceType` types added to `NoteTakrCore`
- `AudioCaptureReporter` protocol lets recorders expose why a source was not captured
- `MeetingSession.audioSourceStatuses` field with backward-compatible JSON decoding
- `RecordingManager.stopRecording()` derives per-source file size and missing reasons
- `SessionDetailView` "Audio Sources" section shows present/missing state, file size, duration, and missing-reason messaging
- 15 new tests added

**Task 4 — Implement Local Transcription**
- `TranscriptionState` enum: idle / transcribing / completed / modelUnavailable / failed
- `TranscriptionService` in `NoteTakrCore` orchestrates engine + session-store, persists segments to `session.json`
- `TranscriptionCoordinator` (ObservableObject) drives reactive UI state in session detail view
- `SessionDetailView` shows spinner while transcribing, orange model-unavailable warning with path hint, error message on failure
- `FluidAudioAdapter` fixed to throw `modelUnavailable` instead of silently returning empty segments
- `StatusBarController` wired to `TranscriptionService`; mock fallback removed from production path
- 9 new tests added; docs updated with physical-Mac transcription verification steps

**Task 5 — Improve Notes Generation**
- `MarkdownNoteRenderer` renders audio source statuses (present/missing with duration, size, reason) in a new "Audio Sources" section; date is human-readable
- `TranscriptionService` auto-generates `note.md` immediately after transcription completes
- `SessionDetailView` gained `onOpenNote` callback with a prominent "Open Note" button
- `StatusBarController` wires `onOpenNote` to open existing `note.md` or generate-and-open if absent
- 8 new tests added

**Task 6 — Final E2E Smoke Test**
- All automated tests pass (139 tests, 0 failures)
- Manual physical-Mac checks documented in `docs/manual-smoke-test.md` and deferred to human tester

### Verification status

- Linux-compatible test suite: 139 tests, 0 failures (all six tasks)
- macOS GitHub Actions CI: configured to build the app target with `xcodebuild`
- Automated tests cover: session model, session store, recording state machine, vocabulary, transcription service, note rendering, audio source status, and UI automation
- Physical Mac verification deferred: audible audio capture, Screen Recording permission flow, Calendar persistence across restart, FluidAudio/Parakeet transcription with real model

### No prohibited dependencies

No cloud service, login flow, browser extension, Electron dependency, Tauri dependency, or new cloud transcription service was added. All data remains local.

### Remaining manual steps

1. Follow docs/manual-smoke-test.md on a physical Mac running macOS 14+ with Xcode 16+.
2. Build with `bash scripts/build-macos-app.sh --install` and launch from `/Applications/NoteTakr.app`.
3. Grant Calendar, Microphone, and Screen Recording permissions as prompted.
4. Confirm per-source recording status appears after stopping a recording.
5. Confirm Screen Recording shows "Restart Required" and the restart explanation.
6. Configure a FluidAudio model folder or automatic download in Settings, then test local transcription.
7. Confirm `note.md` is auto-generated after transcription and "Open Note" opens it.
8. If all checks pass, merge next-product-phase into main.

---

## Project: NoteTakr v5 Redesign (redesign-implementation branch)

### Summary

The redesign-implementation branch is complete. All ten planned tasks were implemented and verified. This phase implemented the full v5 UI redesign matching the interactive HTML mockups in `design/mockups/v5/`.

### Screen-by-screen implementation mapping

**Editor screen** (`design/mockups/v5/editor.html` → `NoteTakrApp/Views/EditorView.swift`, `MarkdownBodyView.swift`)
- Title H1, then compact metastrip preview row (record pill first, divider, time chip, expand chevron)
- Whole preview row is the hit target for expand/collapse; record pill intercepts its own taps
- Rendered markdown body: headings, bullets/numbered, task checkboxes, inline code, code blocks, blockquotes, hr, bold/italic
- No copy button — select-all + copy yields raw markdown source; copy hint ("⌘A ⌘C → raw markdown") visible at bottom of notes pane
- Footer tabs: Notes · Summary · Transcript (active = purple, animated)

**Frontmatter panel** (`design/mockups/v5/frontmatter.html` → `PropertyPanelView.swift`, `ChipsRowView.swift`)
- Expandable props rows (animate in/out on expand): Event chip, Date & time, People circles, Location, Meeting link, In-person, Transcript
- Fields show editable state on hover/click
- People as initials circles (overflow-safe); hover swaps for ✕ with name/email tooltip; menu offers Remove
- In-person toggle with "?" explainer popover (mic-only explanation)
- Transcript row shows record pill; after recording done shows seekable audio player

**Record control** (`design/mockups/v5/recording.html` → `RecordPillView.swift`, `RecordPillStateMachine.swift`)
- Monochrome pill, fixed width; indicator dot only: gray (idle), red (recording), amber breathing (paused)
- State machine: idle → recording (mm:ss) → paused → menu (Resume / Stop & Transcribe / Stop & Summarize)
- Menu opens below pill with spring animation; Stop & Summarize triggers summary generation
- Audio player appears in transcript row after recording finishes
- ⌘N global new-note shortcut registered

**⌘K Switcher** (`design/mockups/v5/switcher.html` → `SwitcherOverlayView.swift`, `SwitcherViewModel.swift`)
- Frost overlay over dimmed/blurred note; full-window mode available via toggle
- Two-line rows: monochrome deterministic icons, title + subtitle, right-aligned time
- Soft hover with hairline border; "now" pill (purple) only on current meeting
- Agenda timeline mode: continuous vertical fading line, dots (current filled, upcoming ring, past faint)
- Typeable search filters live; ↑/↓ navigation; Enter opens; Esc closes; ⌘K toggles
- "settings" / "new" surface Open Settings (⌘,) and New note (⌘N) command rows
- Grouped by recency: Upcoming / Today / Yesterday / Earlier

**Transcript & Summary** (`design/mockups/v5/transcript.html` → `TranscriptView.swift`, `SummaryView.swift`, `TranscriptMerger.swift`)
- Speaker as bold lead-in, paragraphs, Collapse all / Expand all toolbar
- Same-speaker consecutive segments merged into one turn
- Mic + system-audio transcripts merged chronologically by start time
- Speaker naming: mic → local user, system audio → calendar participant or "Speaker 2"; uncertain → "Speaker · most likely <name>"
- In-person: mic-only diarization
- Copy yields markdown (`**Speaker:** text`)
- Summary tab: empty state → Generate button (sparkle icon) → spinner → rendered markdown

**Settings** (`design/mockups/v5/settings.html` → `SettingsSheetView.swift`, `SettingsSheetViewModel.swift`)
- Sheet over blurred note; icon tabs: This Meeting · General · Recording · Vocabulary · Updates · Permissions
- Whole row is hit target; Esc closes; footer "Close + esc pill"
- This Meeting: scope banner (purple), transcribe toggle + timer, in-person, language, linked event, per-meeting vocabulary
- General: defaults, Models section (transcription + summary model), hotkey, ⌘N, launch at login, Notes folder, Appearance
- Recording: mic + system-audio sources, speaker naming, your name
- Vocabulary: global custom-vocabulary editor — add/remove terms, persists, passed to transcription adapter
- Updates: Check for Updates + auto-check toggle wired to Sparkle (macOS only; no-op stub on Linux)
- Permissions: Microphone, Screen & system audio, Calendar with granted/ask states

**Three appearance themes** (`design/mockups/v5/kit.css` → `Theme.swift`, `ThemeEnvironment.swift`)
- Glass: blur + saturate + hairline highlight via VisualEffectView
- Dark: solid #151417 background
- Light: warm paper #FAF8F4 background
- All views read ThemeColors via environment; accent #8B5CF6/#A78BFA; red only for REC dot; amber for paused

**Animations and polish** (Tasks 9 cross-cutting)
- Panel expand/collapse: easeInOut 0.2s
- Record menu: spring scale+opacity transition
- Switcher open/close: easeInOut 0.15s opacity
- Summary spinner: continuous rotation
- Tab switching: easeInOut 0.15s
- Traffic lights: dimmed until hover, color on hover

### Dependency audit

No cloud service, login flow, browser extension, Electron, or Tauri dependency was added. Dependencies:
- `FluidAudio` — local on-device transcription (no cloud calls)
- `NoteTakrKit` — local pure-Swift logic package
- `Sparkle` — macOS app updater (local binary; no cloud data collection)
- `AppKit`, `AVFoundation`, `ScreenCaptureKit`, `EventKit` — macOS system frameworks (all behind `#if canImport(...)` guards)

### macOS-only paths (not verified on Linux)

The following require a physical Mac for smoke testing; each is guarded with `#if canImport(...)` or clearly marked:

| Path | Guard | Status |
|------|-------|--------|
| `NativeAudioRecorder.swift` | `#if canImport(AVFoundation)` | "Verified only on macOS runner / physical Mac" comment |
| `SystemAudioCapturer.swift` | `#if canImport(ScreenCaptureKit)` | "Verified only on macOS runner / physical Mac" comment |
| `EventKitCalendarAdapter.swift` | `#if canImport(EventKit)` | All EventKit calls inside guard |
| `AudioPlayerView.swift` | AppKit/AVFoundation path | "Verified only on macOS runner" comment |
| `MarkdownBodyView.swift` | `#if canImport(AppKit)` | NSPasteboard copy only on macOS |
| `AppDelegate.swift` — Sparkle | macOS-only binary | Guarded by `hasSparkleConfiguration` check; no-op if not configured |
| `SettingsSheetView.swift` — Sparkle check | Runtime guard | "Sparkle check is macOS-only; on Linux / simulator this is a no-op UI stub" comment |

### Test coverage (Linux-runnable, 449 tests, 0 failures)

- `AppSettingsStoreTests` / `AppSettingsStoreTask8Tests` — settings persistence, model selection, Sparkle toggles
- `FrontmatterPresenterTests` / `FrontmatterSerializerTests` — calendar→frontmatter mapping, in-person, add/remove participants
- `MarkdownBodyParserTests` — all block types render and copy returns raw source
- `NoteEditorViewModelTests` — title/body edits, flush
- `NoteStoreTests` — CRUD persistence
- `NoteTabsPresenterTests` — tab selection persistence, flush
- `RecordPillStateMachineTests` — all transitions, timer, summarize intent
- `RecordingNoteBridgeTests` — recording→note wiring
- `SettingsTask8Tests` — vocabulary add/remove/persist (global + per-meeting), model selection
- `SummarizationPromptBuilderTests` — prompt contains speaker-inference instruction + participant context
- `SwitcherViewModelTests` — query filtering, command surfacing, keyboard nav, deterministic icons, group by recency
- `Task9PolishTests` — theme hex spot-checks, accent/amber/rec-red constants, raw markdown copy preservation
- `ThemeTests` — all three themes resolve expected palette
- `TranscriptMergerTests` — same-speaker merge, two-stream interleave, overlap, naming, in-person, rename propagation, copy-as-markdown

### Physical Mac smoke test checklist

The following require a real Mac and are outside the automated test scope:

- [ ] Window appears as compact ~420×620 floating panel with corner radius 16
- [ ] Traffic lights dim until hover; gear button top-right opens Settings; ⌘, also opens Settings
- [ ] All three themes (Glass/Dark/Light) render correctly on every screen
- [ ] Record pill: idle → click → recording (mm:ss ticking) → click → paused (amber breathing) → click → menu
- [ ] Stop & Transcribe produces a transcript; Stop & Summarize switches to Summary tab and generates
- [ ] Audio player appears in frontmatter Transcript row after recording ends; scrubbing works
- [ ] ⌘N opens a new note from any app (global hotkey)
- [ ] ⌘K opens/closes switcher; typing filters; ↑/↓/Enter/Esc all work
- [ ] Calendar events appear in switcher after granting Calendar permission
- [ ] Frontmatter panel expands/collapses; event chip switches and updates all fields
- [ ] Vocabulary terms added in Settings → Vocabulary are passed to transcription
- [ ] Updates tab: Check for Updates contacts Sparkle; auto-check toggle persists
- [ ] All permissions (Microphone, Screen & System Audio, Calendar) show correct state after granting

---

## Project: NoteTakr UI Bug Fixes (redesign-implementation branch, ui-bugfixes plan)

### Summary

Seven targeted bug-fix and behavioural-gap tasks were completed on the redesign-implementation branch.
All 498 Linux-compatible tests pass. No out-of-scope UI redesign work was touched. No new
cloud services, login flows, browser extensions, Electron, or Tauri dependencies were added.

### What was fixed

**Task 1 — Global shortcuts, Escape handling, and the Notes label**
- "Private Notes" label renamed to "Notes" everywhere in the UI
- ⌘N registered as a global shortcut (new note, works regardless of focus)
- ⌘, bound to open Settings from the main note window
- Esc dismisses Settings sheet and the ⌘K switcher/quick-switch overlay
- KeyCommandRouter pure Swift type added; 9 unit tests covering all three intents

**Task 2 — Settings rows: whole-row hit target and correct hover**
- Entire settings row (icon + text + empty space) is now the click/tap target
- Hover/highlight applies to the whole row only on actual hover; fixed bug where
  hovering the text showed the row as selected
- SettingsRowModel pure type added with 10 unit tests for hit-test / selection model

**Task 3 — Fix adding custom vocabulary**
- Fixed bug preventing new vocabulary entries from being added in Settings
- Added entries persist across relaunch and are passed to the transcription adapter
- 20 unit tests: add, persist/reload, duplicate handling, enabled entries reach adapter

**Task 4 — Render markdown in note body; copy yields raw markdown**
- Note body renders formatted markdown (headings, bullets, task checkboxes, code,
  blockquotes, hr, bold/italic, links)
- Copy action copies the raw markdown source, not the rendered output
- MarkdownBodyParser pure type; 14 unit tests covering every block type and raw copy

**Task 5 — Merge transcripts: same-speaker turns and two audio streams**
- Consecutive segments from the same speaker are merged into a single turn
- Microphone and system-audio transcripts merged chronologically by start time
- Single-speaker-per-stream naming: mic → local user, system audio → calendar
  participant or "Speaker 2"; in-person mode skips system-audio entirely
- TranscriptMerger; 22 unit tests covering merging, interleave, overlap, naming

**Task 6 — Speaker inference in the summary/note generation prompt**
- LLM prompt updated to instruct inference of speaker identity from participant
  context; uncertain attribution uses "Speaker N · most likely <name>" form
- Known participant names (including user's own) passed into prompt context
- SummarizationPromptBuilder; tests assert prompt contains both instruction and context

**Task 7 — Expose Sparkle update checking in Settings**
- "Check for Updates..." action and "Automatically check for updates" toggle added
  to Settings → Updates tab; toggle persists and reflects current state on launch
- Sparkle calls guarded with compile-time and runtime macOS checks; Linux no-ops cleanly
- SparkleSettingsTask7Tests: 9 tests for toggle persistence and Sparkle wiring stubs

### Verification status

- Linux-compatible test suite: 498 tests, 0 failures (all seven tasks)
- macOS GitHub Actions CI: each task commit pushed; CI gate requires macOS runner
- Out-of-scope items confirmed untouched: frontmatter visual redesign, record-button
  placement/styling, command-palette/timeline restyle, transcript-collapse styling,
  summary-button styling, animation/polish pass — none were modified

### macOS-only paths (not verified on Linux)

| Path | Guard | Status |
|------|-------|--------|
| Global hotkey registration (CarbonHotkeyRegistrar) | macOS Carbon framework | Verified only on macOS runner / physical Mac |
| Sparkle "Check for Updates" trigger | `#if canImport(AppKit)` + runtime guard | Verified only on macOS runner / physical Mac |
| Sparkle auto-check toggle persistence | macOS UserDefaults + SPUUpdater | Verified only on macOS runner / physical Mac |
| NSPasteboard raw-markdown copy | `#if canImport(AppKit)` | Verified only on macOS runner / physical Mac |

### Remaining manual steps (physical Mac)

1. Open Settings with ⌘, and confirm it opens from the main note window.
2. Press Esc with Settings open; confirm it closes. Same for the ⌘K switcher.
3. Press ⌘N from another app; confirm a new note is created.
4. Add a vocabulary entry in Settings → Vocabulary; relaunch and confirm it persists.
5. Open a note with markdown content; confirm it renders (headings, bullets, code, etc.).
6. Use Copy on a note; confirm pasting elsewhere yields raw markdown.
7. Record a meeting; confirm same-speaker segments are merged in the transcript.
8. Settings → Updates: click "Check for Updates…" and confirm Sparkle opens the update UI.
9. Toggle "Automatically check for updates"; relaunch and confirm the toggle state persists.

---

## Project: Theme Consistency, ⌘K Palette, Recording Control & UI Bug-Fixes (theme-palette-recording-fixes branch)

### Summary

The theme-palette-recording-fixes branch is complete. All eleven planned tasks were implemented and verified. This phase locked in the final recording control and ⌘K command palette (matching the `-final` HTML mockups), neutralized the three themes to eliminate purple tint from all surfaces, and fixed a broad set of recording-control, frontmatter, transcript/summary, calendar, and ESC-handling bugs.

### Screen-by-screen fix mapping (per mockup / big rule)

**Theme tokens** (`kit.css` big rules → `Theme.swift`, `ThemedSurface.swift`)
- Glass background: near-transparent white@0.015 only — VisualEffectView provides the blur; no purple tint added.
- Dark background: #0D0D0F (was #151417 purple-leaning).
- Light background: #F7F7F8 neutral (was #FAF8F4 warm); ink neutralized to #161618 (was (30,27,36) purple-leaning); hover = black@0.05 (was purple-leaning black@0.05 with purple base).
- `accent` (#A78BFA glass/dark, #8B5CF6 light) is the ONLY purple — all surfaces are neutral.
- `ThemedSurface.swift` wraps `VisualEffectView` (Glass) / solid fill (Dark/Light); shared across window body, ⌘K palette, settings, menus — identical blur strength everywhere.

**⌘K command palette** (`switcher-final.html` → `SwitcherOverlayView.swift`)
- Pure backdrop blur only, no scrim or dark overlay on top of the note.
- Rounded search field, no magnifying-glass icon, dropped to heading position.
- Result rows float as cards over the blur; no single bordered container panel.
- List fades at top and bottom with a mask gradient; no overscroll.
- Hover = subtle gray; purple marks the selected row ONLY (no purple hover stacked on purple selection).
- Click-outside / ESC dismisses; ⌘K toggles; ↑/↓ navigates; Enter opens.
- All three themes respected via `themeColors` environment.

**Window chrome** (`WindowChromeView.swift`, `NotePanelController.swift`)
- Fake traffic-light dots removed; only the native macOS close button is present.
- Gear stays top-right, opens Settings (⌘,).
- Chrome uses shared `ThemedSurface` — blur is identical to the window body.

**Settings** (`SettingsSheetView.swift`)
- Adopts active theme via `ThemedSurface`; no hardcoded dark-purple panel background.
- Full-row grey hover removed — only subtle hover on actually-clickable rows.
- ESC closes Settings reliably; whole row is the hit target.
- Light-theme readable (no hardcoded `Color.white.opacity`).

**Note editor** (`EditorView.swift`, `MarkdownBodyView.swift`, `TranscriptView.swift`)
- Clicking the note body focuses the editable TextEditor; Cmd+A/Cmd+C work.
- "→ raw markdown" / "Select & copy → markdown" hint text removed.

**Recording control** (`recording-final.html` → `RecordPillView.swift`, `RecordPillStateMachine.swift`)
- Split badge: neutral pill, white text in every state, ONLY the dot is colored (red recording / amber paused / green transcribing+summarizing / green done).
- States: idle · recording · paused · transcribing · summarizing · done(summarized) · doneTranscript.
- Main tap = Stop & summarize while recording (auto: transcribe → summarize); paused tap = Resume; done taps open Summary/Transcript tab.
- Caret menu only while recording/paused; no caret on done states.
- Transcribe→summarize pipeline wired through `NotePanelController` (was dropped).

**Recording frontmatter bugs** (`RecordPillView.swift`, `PropertyPanelView.swift`, `ChipsRowView.swift`)
- Record badge hover no longer bleeds into the time/clock chip.
- Chips don't jump left when entering edit — display and edit states share the same alignment.
- Record menu dismisses on click-outside + ESC; uses shared blur surface; does not stretch the pill or change row height.
- People/participants input normalized to the same alignment pass.

**Transcript & Summary tabs** (`SummaryView.swift`, `TranscriptView.swift`, `NoteTabsBridge.swift`, `NoteTabsPresenter.swift`)
- Each tab's empty state is a single centered button with nothing else cluttering it.
- Generate transcript action + `.generating` state added to Transcript tab.
- Summary tab without transcript shows "Transcribe & summarize" CTA.
- In-progress transcription reflected in the recording badge (green "Transcribing…/Summarizing…").

**Calendar** (`AppModel.swift`, `EventKitCalendarAdapter.swift`, `FrontmatterPresenterBridge.swift`)
- Events loaded on launch/panel-show; `AppModel.upcomingEvents` → `FrontmatterPresenterBridge.availableEvents` synced.
- macOS 14+ limited calendar access accepted (not requiring full access).

**ESC handling** (`KeyCommandRouter.swift`, `SettingsSheetView.swift`, `NotePanelController.swift`)
- Centralized precedence: settings → switcher → inline edit → (only then) hide panel.
- ESC dismisses topmost overlay first; never closes the window while an overlay is open.

### Verification status

- Linux-compatible test suite: 551 tests, 0 failures (all eleven tasks)
- macOS GitHub Actions CI: passed on the theme-palette-recording-fixes branch

### macOS-only paths (not verified on Linux)

The following require a physical Mac for smoke testing:

| Path | Guard | Status |
|------|-------|--------|
| `VisualEffectView` / glass blur rendering | AppKit | Verified only on macOS runner / physical Mac |
| `RecordPillView` animation / breathing dot | SwiftUI rendering | Verified only on macOS runner / physical Mac |
| `NativeAudioRecorder.swift` | `#if canImport(AVFoundation)` | Verified only on macOS runner / physical Mac |
| `SystemAudioCapturer.swift` | `#if canImport(ScreenCaptureKit)` | Verified only on macOS runner / physical Mac |
| `EventKitCalendarAdapter.swift` | `#if canImport(EventKit)` | Verified only on macOS runner / physical Mac |
| NSPasteboard raw-markdown copy | `#if canImport(AppKit)` | Verified only on macOS runner / physical Mac |

### Physical Mac smoke test checklist (remaining manual steps)

- [ ] Glass blur: window body, ⌘K palette, settings, and menus all share identical blur strength and NO whitening/lightening of the content behind
- [ ] No purple tint on any background in Glass / Dark / Light themes; purple appears only on selected/active states and certain icons
- [ ] Hover on switcher rows is subtle gray; selected row is purple; hovering a selected row does NOT stack purple on purple
- [ ] Record pill: idle (gray dot) → tap → recording (red dot, ticking mm:ss) → tap → Stop & summarize triggers transcription then summary
- [ ] Caret menu while recording: Pause / Stop without summarizing / Restart recording / Discard
- [ ] Caret menu while paused: Stop & summarize / Stop without summarizing / Restart recording / Discard
- [ ] Done states show "Summarized →" / "Transcribed →" with right arrow; no caret; tap opens correct tab
- [ ] Hovering the record badge does NOT restyle the time/clock chip
- [ ] Chips (location, meeting link) do NOT jump left when entering edit mode
- [ ] ESC precedence: settings open → ESC closes settings; switcher open → ESC closes switcher; neither closes the window
- [ ] Calendar events appear in the event picker after granting Calendar permission
- [ ] Summary tab with no transcript shows "Transcribe & summarize" CTA, not an empty/confusing state
- [ ] Transcript tab: "Generate transcript" button works independently of recording
