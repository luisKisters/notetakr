# NoteTakr — Design & Engineering Principles

NoteTakr is "Raycast Notes, but built for meetings": one floating macOS panel for markdown
meeting notes with structured frontmatter, live transcription, AI summaries, and a ⌘K
timeline switcher. This document is the canonical statement of principles. The locked visual
design lives in `design/mockups/final-*.html` (spec summary in `design/mockups/IDEAS.md`);
the execution plan lives in `docs/plans/`.

## 1. Product principles

1. **One window.** The entire app is a single floating panel (~420×620). No main window, no
   dock-centric UI. The menu bar item and a global hotkey (default ⌃⌥⌘N) toggle it.
2. **Meetings are the unit.** Every note is a meeting note. Metadata (time, participants,
   location, calendar link, transcription settings) is structured frontmatter, not prose.
3. **Markdown is the source of truth.** Notes are plain `note.md` files with YAML
   frontmatter — portable, Obsidian-compatible, greppable. Machine data (transcript segments,
   audio statuses, summaries) stays in `session.json` next to it, joined by `id`.
4. **Keyboard-first.** ⌘K switches meetings, esc closes layers, tabs are reachable without
   the mouse. Mouse affordances (gear, chips) may hide until hover.
5. **Calm by default, depth on demand.** The default surface is title + notes. Frontmatter
   expands on click; transcript and summary live behind footer tabs; settings behind a sheet.
6. **Local-first.** Transcription is local (FluidAudio/Parakeet). Only summarization calls
   out (OpenRouter, key in Keychain). People data never leaves the machine.

## 2. Visual system (locked — see final mockups)

- **Window**: compact portrait ~420×620, radius 16, floating NSPanel, dimmed traffic lights,
  no chrome title, gear top-right visible on hover only.
- **Identity**: monochrome + one accent — purple `#8B5CF6` (light variant `#A78BFA`). The
  only other colors: a red dot for live recording, green/orange dots in permission rows.
  No emojis; SF Symbols at ~1.5pt stroke weight. No badges, no word counts. Subtle film grain
  on glass. Explicitly NOT a Raycast clone.
- **Appearance (user setting, 3-way)**: **Glass** (translucent blur material, hairline top
  highlight) · **Dark** (solid purple-tinted `#151417`) · **Light** (warm paper).
- **Editor**: H1 title, then a frontmatter chips row (time, location, participant avatar
  initials, REC timer) that click-expands into a hairline property panel (Date, Calendar
  event, Participants, Location, In-person toggle, Transcript). Markdown body below. Footer
  contains ONLY three bare text tabs — `Private Notes · Summary · Transcript` — active =
  purple, inactive ≈45% opacity, no separators.
- **⌘K switcher ("Timeline Lite")**: frost layer over the blurred note; search on top;
  day-grouped rows (icon + title + right-aligned time) threaded by a 1px vertical line that
  fades at both ends; node dots on every row (hollow purple = upcoming, filled purple glow =
  current, faint neutral = past); dashed ghost rows for upcoming calendar events with
  "+ Create note"; kbd hints in the footer.
- **Settings**: bottom sheet (~85% height, no grabber) over the dimmed note. Icon tabs:
  `This Meeting · General · Recording · Vocabulary · Permissions`. This Meeting shows a
  purple-tinted scope banner ("…applies only to this note") and per-meeting controls.
  General = defaults for new meetings (transcribe ON, language auto-detect — selecting a
  fixed language reveals a warning — in-person default) + app settings (hotkey, launch at
  login, Appearance trio, notes folder). Footer: quiet "Close" + `esc` kbd pill.

## 3. Architecture principles

### Three layers

| Layer | Target | Platform | May import | Tested by |
|---|---|---|---|---|
| **Kit** | `NoteTakrKit` (separate local SPM package, `NoteTakrKit/`) | any (Linux + macOS) | Foundation only — no AppKit, no Combine, no FluidAudio, no EventKit | `swift test` anywhere, incl. Linux |
| **Core** | `NoteTakrCore` (root package) | macOS | Kit + FluidAudio + AVFoundation | `swift test` on macOS (CI runner) |
| **App** | `NoteTakrApp` (Xcode target) | macOS | Kit + Core + AppKit/SwiftUI/EventKit | `xcodebuild test` on macOS (CI runner) |

1. **All logic lives as low as possible.** Models, the frontmatter serializer, stores over
   plain files, presenters/view models, formatting, search/grouping, settings resolution,
   state machines → **Kit**. Audio/ML pipeline → **Core**. Views, panels, hotkeys, EventKit,
   Keychain → **App**.
2. **Presenters, not view code.** Every screen's behavior is a plain observable class in Kit
   with injected dependencies (clock, scheduler, store protocols, data fetchers). SwiftUI
   views are thin bindings. If a behavior can't be unit-tested in Kit on Linux, the seam is
   wrong.
3. **Dependencies are protocols.** Time (`now()`), persistence, HTTP, calendar, recording,
   and transcription enter presenters through protocols with fakes in tests. No new
   singletons; `AppModel` is legacy and shrinks every phase.
4. **No new third-party dependencies** without strong cause. The YAML frontmatter
   serializer is hand-rolled for our fixed schema (parse leniently, emit canonically).

### Storage

```
~/Library/Application Support/NoteTakr/Sessions/YYYY-MM-DD_title_shortid/
  note.md         ← human content: YAML frontmatter + private-notes markdown (Kit owns)
  session.json    ← machine data: transcript segments, audio statuses, summary (Core owns)
  microphone.m4a / system-audio.m4a
```

Frontmatter schema (all keys optional except `id`, `title`, `date`; unknown keys are
preserved on rewrite):

```yaml
---
id: 9F2C…
title: Weekly Sync — Acme GmbH
date: 2026-06-10T14:00:00+02:00
end: 2026-06-10T14:45:00+02:00
calendar_event: ABC123@1718020800
participants: [Luis Kisters <luis@example.com>, Sarah Chen]
location: zoom            # zoom | meet | teams | in-person | none
in_person: false
transcribe: true          # per-meeting override of the general default
language: auto            # auto | ISO 639-1 code
vocabulary: [Acme, Müller]
---
```

Per-meeting frontmatter values override `settings.json` general defaults
(`EffectiveMeetingSettings.resolve(note:defaults:)`); new notes are created with the
defaults materialized.

## 4. Execution & testing model (Linux dev loop + GitHub macOS runner)

Development (including agent/ralphex execution) happens in a **Linux environment with Swift
installed**. macOS is available **only via the GitHub Actions macOS runner** (`macos-15`,
workflow `.github/workflows/macos-ci.yml`, repo `luisKisters/notetakr`).

Consequences, in order of authority:

1. **Kit is the inner loop.** `cd NoteTakrKit && swift test` must pass on Linux. All new
   logic lands here first, with tests, before any UI work.
2. **macOS work is validated remotely.** Anything touching Core or App cannot be compiled
   locally on Linux. The loop is: edit → commit → push → `gh run watch <run-id>
   --exit-status` → read failures from logs (`gh run view <run-id> --log-failed`) → fix →
   push again. Never claim a Core/App task done without a green CI run for its commit.
3. **CI is layered to fail fast**: an `ubuntu-latest` job runs Kit tests (seconds) before
   the macOS jobs run package + Xcode tests. Linting/formatting, if added, runs on ubuntu.
4. **Never attempt on Linux**: launching the app, screenshots, xcodebuild, AppKit imports
   in Kit, simulator anything. Visual fidelity against the mockups is verified by a human
   on a Mac; CI verifies it builds and behaves.
5. **Tests are the acceptance criteria.** Every task ships unit tests in the layer it
   touches: Kit tests on Linux for logic; app-target tests (run by CI) for AppKit glue
   (panel lifecycle, hotkey registration, EventKit mapping). UI styling itself is not
   unit-tested.

## 5. Working conventions

- One plan task = one commit (or a small series), pushed; CI green before checking it off.
- Old UI (`MainWindowView` etc.) keeps working until the final cutover task — the app must
  never be left broken between tasks.
- Reuse the existing pipeline (dual-stream recording, FluidAudio transcription, OpenRouter
  summarization, EventKit adapter, vocabulary boosting) through its existing protocol seams;
  rewrites of working subsystems need explicit justification.
- Fixtures over mocks-of-mocks: store tests run against real temp directories
  (FileManager works on Linux); HTTP/calendar/transcription get protocol fakes.
- Match existing code style (Swift 5.9, async/await, `@MainActor` only in App layer).
