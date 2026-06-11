# Plan: Theme consistency, ⌘K palette, recording control & UI bug-fixes

## Overview

Fix the inconsistencies and bugs that shipped with the v5 redesign, and lock in the **final**
recording control and the **final** ⌘K command palette. Two interactive HTML mockups are the
**visual source of truth** and are committed alongside this plan — open them and reproduce them
exactly (layout, spacing, states, interactions, copy):

- `design/mockups/v5/recording-final.html` — the FINAL recording control (split badge).
- `design/mockups/v5/switcher-final.html` — the FINAL ⌘K command palette.

(`design/mockups/v5/recording-controls.html` and `switcher-versions.html` are the exploration
that led here — **ignore them**; only the two `-final` files are binding.) `design/mockups/v5/kit.css`
holds the shared design tokens.

This plan **supersedes** the recording-control and ⌘K-switcher portions of
`docs/plans/completed/20260611-redesign-implementation.md` wherever they conflict — the `-final`
mockups win. Everything else from that plan stays as-is; do not remove working behavior.

Each task is a vertical slice: build the UI **and** the logic **and** Linux-testable unit tests.
Keep the visual language consistent with `kit.css`. Do not add new dependencies, cloud services,
login flows, Electron, or Tauri.

### The big rules (apply on EVERY screen)
- **No purple TINT on any surface.** Backgrounds are neutral: **Glass** = real translucent macOS
  glass (no purple, no heavy dark overlay), **Dark** = neutral near-black (`#0D0D0F`), **Light** =
  clean near-white (`#F7F7F8`). Purple (`#A78BFA` / light `#8B5CF6`) is used **only as an accent**:
  selected/active states and certain icons.
- **Hover is subtle neutral gray by default.** Purple hover is allowed ONLY where it makes sense
  **and** the element does **not** already have a purple *selected* state — never stack a purple
  hover on top of a purple selection (that reads confusing/ugly). When in doubt, gray hover.
- **Glass blur must JUST blur what's behind it — it must NOT lighten/whiten.** Use a material that
  blurs the content behind without adding a white/light tint or a scrim overlay. The blur strength
  is identical across the window body, the ⌘K palette, settings, and menus.

## Autonomy & Environment (unattended — READ FIRST)

Executed UNATTENDED by ralphex in a Linux Docker container (Debian 12, non-root; Node, git, gh;
a live Swift toolchain at `/usr/local/bin/swift`). Rules:
- **Work fully autonomously**; never pause for input; use non-interactive flags everywhere.
- **Keep `scripts/local-validate.sh` Linux-safe**: run only the Linux-runnable subset; skip
  macOS-only steps (AppKit, SwiftUI rendering, EventKit, ScreenCaptureKit, FluidAudio, Sparkle)
  gracefully — the **macOS GitHub Actions runner is the source of truth** for native build/tests.
- **Pull pure logic out of the views** so it is unit-testable on Linux: theme token resolution,
  the record-pill state machine, switcher filtering/grouping/selection, tab-presenter states,
  calendar→frontmatter mapping, key-command routing. Views stay thin.
- **Never block on macOS-only steps**: keep them behind the existing protocols/adapters, mark them
  "verified only on the macOS CI runner / physical Mac", and keep going.
- **Match the mockups precisely.** When unsure about a measurement/behavior, read the relevant
  `.html` + `kit.css` rather than inventing. Reproduce spacing, the three themes, hover/selected
  states, menu directions, empty states, and the exact copy/labels.
- **Commit and push after each task.** Use `- [ ]` bullets; tasks numbered from Task 1.

Do not proceed to the next task until:
1. local Linux-compatible tests pass (`bash scripts/local-validate.sh`);
2. the current branch is pushed to GitHub;
3. the macOS GitHub Actions workflow passes (`bash scripts/ci-gate.sh`);
4. any CI failures are investigated and repaired.

## Validation Commands
- `bash scripts/local-validate.sh`
- `bash scripts/ci-gate.sh`

---

### Task 1: Theme tokens + unified glass surface (no purple tint, blur-not-whiten)
- [x] Neutralize the three themes in `NoteTakrKit/Sources/NoteTakrKit/Theme.swift`: Glass
      `background` → ~transparent (the material provides the glass, a faint neutral white@~0.015
      lift only), Dark `background` `#151417`→`#0D0D0F`, Light `background` `#FAF8F4`→`#F7F7F8`.
      Recolor the purple-leaning Light ink `(30,27,36)`→neutral `#161618`, Light `hoverFill`
      `(40,30,50,.05)`→black@0.05, and `avatarRing`s to match. Keep `accent` purple (the only purple).
- [x] Add ONE reusable themed surface (e.g. `NoteTakrApp/Views/ThemedSurface.swift`) wrapping
      `VisualEffectView` for Glass and a solid `themeColors.background` fill for Dark/Light. Reuse it
      for the window body, the ⌘K palette, settings, and any menu/popover so the blur is identical
      everywhere. The glass material must **blur WITHOUT whitening** — pick a material/blending that
      does not add a white/light tint or scrim.
- [x] Wire the window body (`EditorView.swift` `panelBackground`, ~110-123) to the shared surface;
      drop the inline `Color.white.opacity(0.02)` lift and the per-theme solid-color branches.
- [x] Encode the purple/hover rules as shared style helpers: a `selected` style (purple tint +
      hairline) and a `hover` style (neutral gray by default). Purple hover only for elements with
      NO purple selected state.
- [x] Linux tests: each theme resolves the expected neutral tokens; `accent` is purple; the
      Appearance setting persists and reloads.
- [x] Run the local validation and CI gate until both pass.

### Task 2: ⌘K command palette — final (floating rows over a pure blur)
Reproduce `design/mockups/v5/switcher-final.html` exactly. `NoteTakrApp/Views/SwitcherOverlayView.swift`
(rendered as a ZStack sibling in `EditorView.swift`).
- [x] Replace the full-bounds frosted rectangle + dark overlay with a **pure backdrop blur, NO
      scrim/tint overlay** — it only blurs the note behind and does NOT lighten it. Because the blur
      spans the whole window, the top bar/navbar is blurred by the same surface (no separate
      top-bar treatment, no "lighter" palette blur).
- [x] Search = a **rounded field with NO magnifying-glass icon**, positioned **on the heading line**
      (dropped down from the very top, not pinned under the traffic lights).
- [x] Result rows **float as cards** directly on the blur (no single bordered container panel);
      roomier padding/spacing than today (see the mockup's `.krow`).
- [x] The list **fades at the top & bottom** while scrolling (mask gradient) and **cannot overscroll**
      past the last meeting.
- [x] Hover = subtle gray; **purple ONLY marks the selected row** (no purple hover over the purple
      selection).
- [x] Click-outside dismisses; ESC dismisses; ⌘K toggles; ↑/↓ move selection; Enter opens.
- [x] Thread `themeColors` through so rows render correctly in all three themes (no hardcoded
      white).
- [x] Linux tests: query filtering, keyboard-nav wrap, grouping/selection.
- [x] Run the local validation and CI gate until both pass.

### Task 3: Window chrome — one real close button, no fake dots, gear top-right
`NoteTakrApp/Views/WindowChromeView.swift` + `NoteTakrApp/NotePanelController.swift`.
- [ ] Delete the three FAKE traffic-light circles in `WindowChromeView.swift`.
- [ ] Keep ONLY the real native close button (top-left); ensure it's visible and hittable
      (`p.standardWindowButton(.closeButton)?.isHidden = false`); zoom/miniaturize stay hidden; keep
      that corner free of overlapping tappable SwiftUI views.
- [ ] Gear stays top-right and opens Settings (⌘,); fall back to bottom-right only if it clashes.
- [ ] No separate `.background()` on the chrome — the top-bar blur is identical to the body (shared
      surface).
- [ ] Run the local validation and CI gate until both pass.

### Task 4: Settings follows the theme (no purple panel, no full-row grey hover)
`NoteTakrApp/Views/SettingsSheetView.swift`.
- [ ] Make Settings adopt the ACTIVE theme (glass/dark/light) via the shared surface + a theme
      source (`viewModel.currentAppearance` / `@Environment(\.themeColors)`); remove the hardcoded
      dark-purple panel background and purple accent constants.
- [ ] **Remove the full-row grey hover** — hovering a setting must NOT fill the entire row grey (it
      "looks like shit"). Keep hover minimal/subtle and only on actually-clickable rows; never purple
      where a purple selection exists.
- [ ] Fix the hit target: the whole row triggers its action (nested Toggles/Pickers must not be the
      only tappable area).
- [ ] Theme-aware icon/text colors (no hardcoded `Color.white.opacity`), so Light theme is readable.
- [ ] ESC closes Settings reliably.
- [ ] Linux tests: the settings-row hit-target/selection model; appearance-driven colors resolve
      per theme.
- [ ] Run the local validation and CI gate until both pass.

### Task 5: Note editor — typing, copy, remove markdown hint
`NoteTakrApp/Views/EditorView.swift`, `NoteTakrApp/Views/MarkdownBodyView.swift`,
`NoteTakrApp/Views/TranscriptView.swift`.
- [ ] Make the note body reliably editable: clicking into it focuses an editable field and you can
      type; the tap→focus handoff must be reliable (keep the editable field mounted or set/retain
      focus on tap and when the tab becomes active). Cmd+A / Cmd+C work (select-all + copy yields the
      raw markdown source).
- [ ] Remove the "→ raw markdown" / "Select & copy → markdown" hint text (the `copyHint` in
      `MarkdownBodyView.swift` and the equivalent in `TranscriptView.swift`).
- [ ] Linux tests: copy returns the exact raw markdown source (round-trip on the pure type).
- [ ] Run the local validation and CI gate until both pass.

### Task 6: Recording control — final split badge (state machine + view)
Reproduce `design/mockups/v5/recording-final.html` exactly. `NoteTakrApp/Views/RecordPillView.swift`
+ `NoteTakrKit/Sources/NoteTakrKit/RecordPillStateMachine.swift` + `NoteTakrApp/NotePanelController.swift`.
- [ ] States: `idle · recording · paused · transcribing · summarizing · done(summarized) ·
      doneTranscript(stop-only)`. ONE neutral pill, **white text in every state, ONLY the dot is
      colored** (red recording / amber paused / green transcribing+summarizing / green done). No
      colored background or ring per state.
- [ ] **Main tap = Stop & summarize** while recording (auto: transcribe → summarize, no manual
      step); paused tap = Resume; done tap = open the Summary tab; transcribed-only tap = open the
      Transcript tab. Transcribing/summarizing are NOT tappable.
- [ ] **Caret menu only while recording/paused:** recording → Pause · Stop without summarizing ·
      Restart recording · Discard; paused → Stop & summarize · Stop without summarizing · Restart
      recording · Discard.
- [ ] **No caret on the done states** — they show "Summarized →" / "Transcribed →" with a small
      right arrow and the whole badge is the tap target.
- [ ] Wire the pipeline so a stop ACTUALLY runs transcription then summarization (the old
      `.transcribe` intent is currently dropped in `NotePanelController.swift` — only `.summarize` is
      handled; fix it).
- [ ] Linux tests: every transition; the main-tap action per state; auto transcribe→summarize; the
      stop-only path → doneTranscript; menu contents per state.
- [ ] Run the local validation and CI gate until both pass.

### Task 7: Recording frontmatter bugs (hover bleed, chip jump, menu, people)
`NoteTakrApp/Views/RecordPillView.swift`, `NoteTakrApp/Views/PropertyPanelView.swift`,
`NoteTakrApp/Views/ChipsRowView.swift`.
- [ ] Hovering the record badge must NOT restyle the time/clock chip — decouple `RecordPillView`'s
      hover from `ChipsRowView`'s row hover.
- [ ] Chips (location, meeting link) must NOT jump left when clicked to edit — give the display and
      edit states the same trailing alignment/width so entering edit doesn't reflow the row.
- [ ] The record menu (and any frontmatter popover) must dismiss on click-outside + ESC, render over
      the shared (non-whitening) blurred surface, and NOT change the row height / stretch the
      frontmatter separator / grow the pill.
- [ ] Normalize the people/participants input layout in the same alignment pass.
- [ ] Run the local validation and CI gate until both pass.

### Task 8: Transcript & Summary tabs — centered Generate buttons + states
`NoteTakrApp/Views/SummaryView.swift`, `NoteTakrApp/Views/TranscriptView.swift`,
`NoteTakrApp/NoteTabsBridge.swift`, `NoteTakrKit/Sources/NoteTakrKit/NoteTabsPresenter.swift`.
- [ ] Each tab's empty state is a **single centered button** ("Generate summary" / "Generate
      transcript"), nothing else cluttering it; a centered spinner while generating.
- [ ] Add a real **Generate transcript** action + a `.generating` state to the Transcript tab,
      mirroring the existing Summary generate flow.
- [ ] Summary tab with **no transcript**: a clear centered CTA that conveys you must transcribe
      first (e.g. "Transcribe & summarize"), not an empty/confusing state.
- [ ] Reflect an in-progress transcription in the recording badge (green "Transcribing…/Summarizing…")
      per Task 6.
- [ ] Linux tests: tab-presenter states (empty / generating / ready) for both transcript and summary.
- [ ] Run the local validation and CI gate until both pass.

### Task 9: Calendar — show real upcoming events
`NoteTakrApp/AppModel.swift`, `NoteTakrApp/NotePanelController.swift`,
`NoteTakrApp/FrontmatterPresenterBridge.swift`, `NoteTakrApp/Calendar/EventKitCalendarAdapter.swift`.
- [ ] Load upcoming events on launch / panel-show and SYNC `AppModel.upcomingEvents` →
      `FrontmatterPresenterBridge.availableEvents` (call the existing-but-never-called
      `refreshCalendarEvents()`), so the event picker is actually populated (today it always shows
      "No upcoming events").
- [ ] Accept macOS 14+ **limited** calendar access (don't require full access) so granted calendars
      still return events.
- [ ] Linux tests: AppModel→bridge event mapping/sync given a mock calendar adapter.
- [ ] Run the local validation and CI gate until both pass.

### Task 10: Escape handling
`NoteTakrKit/Sources/NoteTakrKit/KeyCommandRouter.swift`, `NoteTakrApp/Views/SettingsSheetView.swift`,
`NoteTakrApp/NotePanelController.swift`.
- [ ] Centralize ESC precedence: **settings → switcher → inline edit → (only then) hide the panel.**
      ESC dismisses the topmost overlay first and never closes the whole window while an
      overlay/settings is open. ESC in Settings always just closes Settings.
- [ ] Linux tests: KeyCommandRouter precedence for each context (settings/switcher/editor).
- [ ] Run the local validation and CI gate until both pass.

### Task 11: Final review & sign-off
- [ ] Walk every changed screen against `recording-final.html` / `switcher-final.html` / `kit.css`
      and the big rules; fix mismatches in layout, spacing, states, copy, and the three themes.
- [ ] Confirm: no purple TINT on any surface; purple only on selected states + icons; no purple
      hover stacked on a purple selection; hovers are subtle gray; the glass blur blurs WITHOUT
      whitening and is consistent across body/palette/settings/menus.
- [ ] Run all Linux-compatible tests and the full macOS workflow; fix every build failure, test
      failure, and actionable warning; confirm GitHub Actions is green.
- [ ] Write a concise completion report in `docs/agent-progress.md` mapping each fix to its mockup /
      rule and listing anything still needing a physical-Mac smoke test.
- [ ] Run the local validation and CI gate until both pass.
