# Plan: Implement the NoteTakr v5 Redesign (full UI + behaviors)

## Overview

Implement the locked **v5 redesign** in the real SwiftUI app, matching the interactive HTML
mockups in `design/mockups/v5/` **exactly** (layout, spacing, states, interactions, copy).
Those mockups are the **visual source of truth** — open each one and replicate it.

> **The mockups are committed alongside this plan.** For every screen, open the matching file
> in `design/mockups/v5/` and reproduce it pixel-for-behavior. `kit.css` defines the shared
> design tokens (monochrome + purple `#8B5CF6`/`#A78BFA`, three appearance themes Glass/Dark/
> Light, SF-style 1.5px stroke icons, radii, the record pill, people circles, the timeline,
> etc.). `index.html` is the overview.

Files and what they specify:
- `design/mockups/v5/editor.html` — the note editor (Solid/Glass Twin)
- `design/mockups/v5/frontmatter.html` — the editable meeting metadata panel
- `design/mockups/v5/switcher.html` — the ⌘K switcher (4 variations: rows/timeline × overlay/window)
- `design/mockups/v5/transcript.html` — transcript & summary (document layout)
- `design/mockups/v5/recording.html` — the record control (placement A, in the front-meta)
- `design/mockups/v5/settings.html` — settings (tabs, vocabulary, updates, models)
- `design/mockups/v5/kit.css` — shared design tokens & components

This plan **supersedes/extends** `docs/plans/completed?/20260611-ui-bugfixes.md` where they
overlap (markdown rendering, transcript merging, vocabulary-add, Sparkle, shortcuts): if a
behavior is already implemented, verify it still matches the mockup and move on; do not remove it.

Each task is a vertical slice: build the UI **and** the logic **and** tests. Keep the visual
language consistent with `kit.css`. Do not introduce new dependencies, cloud services, login
flows, Electron, or Tauri.

Do not proceed to the next task until:
1. local Linux-compatible tests pass (`bash scripts/local-validate.sh`);
2. the current branch is pushed to GitHub;
3. the macOS GitHub Actions workflow passes (`bash scripts/ci-gate.sh`);
4. any CI failures are investigated and repaired.

## Autonomy & Environment (unattended — READ FIRST)

Executed UNATTENDED by ralphex in a Linux Docker container (Debian 12, non-root; Node, git, gh;
a live Swift toolchain at `/usr/local/bin/swift`). Rules:
- **Work fully autonomously**; never pause for input; use non-interactive flags everywhere.
- **Keep `scripts/local-validate.sh` Linux-safe**: run only the Linux-runnable subset; skip
  macOS-only steps (AppKit, SwiftUI rendering, EventKit, ScreenCaptureKit, FluidAudio, Sparkle)
  gracefully — the **macOS GitHub Actions runner is the source of truth** for native build/tests.
- **Pull pure logic out of the views** so it is unit-testable on Linux: markdown rendering,
  transcript merging/diarization, calendar→frontmatter mapping, prompt construction, key-command
  routing, vocabulary persistence, settings models. Views stay thin.
- **Never block on macOS-only steps**: put them behind the existing protocols/adapters, mark
  them "verified only on the macOS CI runner / physical Mac", keep going.
- **Match the mockups precisely.** When unsure about a measurement/behavior, read the relevant
  `.html` + `kit.css` rather than inventing. Reproduce: spacing, the three themes, hover/active
  states, menu directions, empty states, and the exact copy/labels.
- **Commit and push after each task.** Use `- [ ]` bullets; tasks numbered from Task 1.

## Validation Commands
- `bash scripts/local-validate.sh`
- `bash scripts/ci-gate.sh`

## Global acceptance (every screen)
- One floating panel, compact portrait ~**420×620**, corner radius **16**.
- Three appearance themes — **Glass** (blur+saturate, hairline highlight), **Dark** (solid
  `#151417`), **Light** (warm paper `#FAF8F4`) — driven by the Appearance setting; the toggle in
  the mockups is a demo affordance, in-app it follows the setting.
- Chrome: dimmed traffic lights **top-left**; a **gear top-right** that opens Settings and is
  bound to **⌘,**. Monochrome + purple accent; **red is used only for the REC indicator dot**.
- Inline **SF-style stroke icons** (1.5px), no emojis, no multi-color glyphs.

---

### Task 1: Design-system foundation (window shell, themes, tokens, chrome)
- [x] Add a shared design-tokens source (colors, text levels, hairlines, accent, radii, fonts)
      mirroring `kit.css` `:root` + the `.window.t-glass/.t-dark/.t-light` scoped vars.
- [x] Implement the three appearance themes (Glass / Dark / Light) as an app-wide Appearance
      setting; the whole window restyles to match `kit.css` for each theme.
- [x] Build the window chrome: traffic lights top-left (dimmed until hover), a gear top-right
      that opens Settings, bound to **⌘,**.
- [x] Add reusable building blocks used across screens: the chip/`metastrip` preview row, the
      `props` panel rows (key + right-aligned value), toggles, `kbd` pills, the SF icon set.
- [x] Add Linux-testable theme/token unit tests (e.g. each theme resolves the expected palette;
      Appearance setting persists and reloads).
- [x] Run the local validation and CI gate until both pass.

### Task 2: The record control (monochrome pill + state machine + ⌘N)
- [x] Build the record pill exactly per `kit.css` `.recpill` + `recording.html`: a fixed,
      monochrome pill where **only the indicator dot is colored** (gray idle, red recording,
      amber breathing when paused). Width stays constant; it never wraps.
- [x] State machine: **idle → click → recording** (ticking mm:ss) **→ click → paused**
      (breathing) **→ click → menu**. The menu (borderless, soft shadow) has **Resume**,
      **Stop & Transcribe**, **Stop & Summarize**. Resume → recording; the Stop items end the
      recording. The menu opens **below** the pill, staying on-screen (left-anchored when the
      pill is on the left, right-anchored when on the right — see `.ralign`).
- [x] **Stop & Summarize** switches to the Summary tab and triggers summary generation.
- [x] When a recording finishes (transcript ready), the front-meta Transcript row swaps the pill
      for a **seekable audio player** (play/pause + scrubbable progress + `mm:ss / mm:ss`) — see
      `frontmatter.html` `.player`.
- [x] Register **⌘N** as a *global* new-note shortcut (reuse the floating-note hotkey mechanism).
- [x] Extract the state machine into a pure, Linux-testable type; unit-test every transition
      (idle→rec→paused→resume→rec→stop), the timer pause/resume, and that Summarize signals the
      Summary+generate intent.
- [x] Run the local validation and CI gate until both pass.

### Task 3: Editor screen
- [x] Reproduce `editor.html`: title H1, then one quiet **preview line** = **record (first) ·
      time** only, with a clear (bordered) expand control on the right.
- [x] The **whole preview line** is the hit target — hovering highlights the entire strip and
      clicking expands the frontmatter panel (the record pill keeps its own click).
- [x] Render the note body as **formatted markdown** (headings, bullet/numbered lists, task
      checkboxes, inline code, code blocks, blockquotes, hr, bold/italic, links). Use the `.md`
      styling from `kit.css`.
- [x] **No copy button**: selecting text and copying yields the **raw markdown source** (not the
      rendered output). Verify a round-trip: select-all → copy → clipboard equals the source.
- [x] Footer = three bare tabs **Notes · Summary · Transcript** (active = purple). Tab switching
      swaps the body pane.
- [x] Summary tab **empty state**: a "Generate summary" button (sparkle icon) → spinner →
      rendered markdown summary.
- [x] Put markdown→view conversion and copy-source extraction in Linux-testable types; unit-test
      each construct renders and that copy returns the exact raw source.
- [x] Run the local validation and CI gate until both pass.

### Task 4: Frontmatter panel (editable, calendar-driven)
- [x] Reproduce `frontmatter.html`: the expandable panel with right-aligned values. Nothing
      looks editable until **hover**; **click a field to edit** (date, time, location, link).
- [x] **Event**: a small inline chip showing the linked calendar event; a menu switches the
      event and **auto-updates** title, date/time, location, link, and participants from it.
- [x] **People**: render participants as **initials circles** (single row, overflow-safe).
      Hovering a circle swaps the initials for a red **✕** and shows a tooltip with **name,
      email, and "Click to remove"**; clicking opens a menu with **Remove from note** /
      **Remove from calendar**. An "+" circle adds a person inline.
- [x] **Location** = the calendar's actual location (free text; empty shows "No location").
      **Meeting link** is its own editable field.
- [x] **In-person**: a toggle with a small **"?" explainer** ("In-person meetings are mic-only —
      NoteTakr skips system-audio capture"). No "system audio off" inline text.
- [x] **Transcript row**: shows the record pill; once a recording is done it becomes the seekable
      **player** (Task 2). No color picker anywhere.
- [x] Extract calendar-event → frontmatter mapping into a Linux-testable type; unit-test that
      selecting an event updates all fields, add/remove participant, location/link empty states,
      and that in-person disables the system-audio source.
- [x] Run the local validation and CI gate until both pass.

### Task 5: ⌘K Switcher (overlay + full-window; rows + timeline)
- [x] Reproduce `switcher.html`'s four directions, all sharing the **same row rendering**:
      (1) two-line rows as a **pop-up overlay over the dimmed/blurred note**, (2) two-line rows
      as a **full window**, (3) **agenda timeline** overlay, (4) **agenda timeline** full window.
      Ship the overlay-over-note as the primary; keep the full-window mode available.
- [x] Rows: monochrome **deterministic** icons (kind → fixed icon, all gray), title (+ subtitle
      on two-line), right-aligned time. **Soft hover with a hairline border.** Only the **current**
      meeting is flagged with a small "now" pill — **no scattered red dots**. Upcoming calendar
      events show a **small** dashed "+ Create" chip.
- [x] **Agenda timeline**: a single continuous vertical line that **fades at top & bottom**, with
      a **dot on every meeting** (current filled · upcoming ring · past faint). It must render
      cleanly (no broken line) in both overlay and full-window.
- [x] Typeable search filters rows live; **↑/↓** move the selection; **Enter** opens; **esc**
      closes the overlay; **⌘K** toggles it. Typing "settings"/"new" surfaces **Open Settings
      (⌘,)** and **New note (⌘N)** command rows; Open Settings opens Settings.
- [x] Group by recency (Upcoming / Today / Yesterday / Earlier); merge upcoming calendar events
      with existing notes chronologically.
- [x] Extract filtering/grouping/selection into Linux-testable logic; unit-test query filtering,
      command surfacing, keyboard navigation wrap, and deterministic icon mapping.
- [x] Run the local validation and CI gate until both pass.

### Task 6: Transcript & Summary + diarization
- [x] Reproduce `transcript.html` (document layout): speaker as a bold lead-in, paragraphs,
      quiet collapse. **Merge consecutive same-speaker segments into one turn.** Collapsible
      turns with **Collapse all / Expand all**; collapsed shows a one-line preview.
- [x] **Merge the microphone and system-audio transcripts** into one chronological transcript,
      ordered by each segment's **start time** (overlap → earlier start first).
- [x] **Speaker naming**: when exactly one speaker is detected per stream, name the **microphone**
      speaker as the local user and the **system-audio** speaker as the other participant (from
      the linked calendar event when available, else "Speaker 2"). When uncertain, show
      **"Speaker · most likely <name>"**; clicking a name lets you **rename** it (updates all of
      that speaker's turns).
- [x] **In-person** meetings: capture/diarize the **microphone only** (no system stream).
- [x] Select-and-copy yields a **markdown** rendering of the transcript (`**Speaker:** text`).
- [x] A finished recording is playable via the seekable **player** (Task 2) where shown.
- [x] Implement merging/diarization/naming as pure, Linux-testable logic; unit-test same-speaker
      merge, two-stream interleave ordering (incl. an overlap case), single-speaker-per-stream
      naming with/without calendar participants, the in-person mic-only path, rename propagation,
      and the copy-as-markdown output.
- [x] Run the local validation and CI gate until both pass.

### Task 7: Summary generation + speaker-inference prompt
- [x] Wire the **Generate summary** flow (empty state → generating → rendered markdown), using
      the configured **Summary model** (Task 8).
- [x] The summary/note prompt instructs the model to **infer who each speaker is** from the
      participants and context, and when unsure to label **"Speaker N · most likely <name>"**
      rather than guessing a definite name. Pass participant names + the user's own name into the
      prompt context.
- [x] Unit-test (Linux) that the constructed prompt contains the speaker-inference instruction
      and the participant context, and that the selected summary model is honored.
- [x] Run the local validation and CI gate until both pass.

### Task 8: Settings
- [x] Reproduce `settings.html`: a sheet over the (blurred) note with icon tabs **This Meeting ·
      General · Recording · Vocabulary · Updates · Permissions**. **The whole row is the hit
      target** (clickable + hover) — not just the icon/text; hover ≠ selected. **Esc closes** the
      sheet; a quiet "Close" + `esc` pill in the footer.
- [x] **This Meeting**: a purple scope banner ("applies only to this note"), then per-meeting
      Transcribe toggle (+ live timer), In-person, Language, Linked event, **and per-meeting
      "Word boosting · this meeting" custom vocabulary** (add/remove terms — must work).
- [x] **General**: defaults for new meetings (Transcribe, Language Auto-detect), a **Models**
      group (**Transcription model**, **Summary model**), and App settings (floating-note hotkey,
      global **New note ⌘N**, Launch at login, Notes folder, **Appearance** Glass/Dark/Light).
- [x] **Recording**: Microphone + System-audio sources (System off for in-person), speaker-naming
      ("Your name", infer-from-calendar).
- [x] **Vocabulary**: the global custom-vocabulary editor — **adding a term works** and persists
      and is passed to the transcription adapter (per the bug report).
- [x] **Updates**: a **"Check for Updates…"** action and an **"Automatically check for updates"**
      toggle wired to **Sparkle**; current version + channel. Guard so Linux validation still
      passes; verify on the macOS runner.
- [x] **Permissions**: Microphone, Screen & system audio, Calendar — with granted/ask states.
- [x] Unit-test (Linux) vocabulary add/remove/persist for **both** the global and per-meeting
      stores, the model selections persisting, and the whole-row hit-test/selection model.
- [x] Run the local validation and CI gate until both pass.

### Task 9: Motion, shortcuts & cross-screen polish
- [x] Add the animations the mockups imply: panel expand/collapse, record breathing while paused,
      menu/tooltip fades, summary spinner, switcher open/close. Keep them subtle and smooth.
- [x] Confirm the global/window shortcuts end-to-end: **⌘N** (new note, global), **⌘,** (Settings),
      **⌘K** (switcher toggle), **esc** (closes Settings and the switcher), tab switching.
- [x] Replace any remaining "Private Notes" label with **Notes**; ensure copy = raw markdown
      everywhere a note/transcript is copyable.
- [x] Verify all three themes look correct on every screen (spot-check against the mockups).
- [x] Run the local validation and CI gate until both pass.

### Task 10: Final review & sign-off
- [x] Walk every screen against its `design/mockups/v5/*.html` counterpart and fix mismatches in
      layout, spacing, states, copy, and interactions.
- [x] Run all Linux-compatible tests and the full macOS workflow; fix every build failure, test
      failure, and actionable warning.
- [x] Confirm no cloud service, login flow, browser extension, Electron, or Tauri dependency was
      added; confirm unverified real-audio/Sparkle/EventKit paths are marked "verified only on
      macOS / physical Mac".
- [x] Write a concise completion report in `docs/agent-progress.md` mapping each implemented
      screen/behavior to its mockup, and listing what still needs a physical-Mac smoke test.
- [x] Run the local validation and CI gate until both pass.
