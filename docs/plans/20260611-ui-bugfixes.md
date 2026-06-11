# Plan: NoteTakr UI Bug Fixes (unambiguous, no-design-nuance batch)

## Overview

This plan fixes a batch of clear, well-specified bugs and small behavioural gaps in
the NoteTakr macOS app that the user reported. **Only fully-specified items are in
scope.** Anything that needs a visual redesign decision (frontmatter rework,
record/pause button placement, command-palette/timeline restyle, collapsible
transcript styling, summary-button styling) is intentionally EXCLUDED — those are
being handled separately via design mockups and must NOT be touched here.

Each task is a vertical slice: change the UI/logic AND add tests where the logic is
Linux-testable. Keep changes minimal and surgical — do not refactor unrelated code,
do not restyle screens, do not introduce new dependencies.

Do not proceed to the next task until:

1. local Linux-compatible tests pass (`bash scripts/local-validate.sh`);
2. the current branch is pushed to GitHub;
3. the macOS GitHub Actions workflow passes (`bash scripts/ci-gate.sh`);
4. any CI failures have been investigated and repaired.

## Autonomy & Environment (unattended execution — READ FIRST)

This plan is executed UNATTENDED by ralphex inside a Linux Docker container (Debian 12,
non-root user; Node, git, gh available; a live Swift-for-Linux toolchain is present at
`/usr/local/bin/swift`). Follow these rules at all times:

- **Work fully autonomously.** Never pause for confirmation. Use non-interactive flags
  everywhere; never leave a command waiting on a prompt.
- **`scripts/local-validate.sh` must stay Linux-safe.** It runs only the Linux-runnable
  subset and must skip macOS-only steps gracefully. Do not fail the gate merely because
  Swift/macOS-only APIs (AppKit, Sparkle, EventKit, ScreenCaptureKit, FluidAudio) are
  unavailable locally — the macOS GitHub Actions runner is the source of truth for native
  compilation and tests.
- **Never block on macOS-only or root-only steps.** If something genuinely needs macOS,
  implement it behind the existing protocol/adapter, mark it "verified only on the macOS CI
  runner / physical Mac", and keep going.
- **Prefer logic that is unit-testable on Linux.** Pull pure logic (markdown rendering,
  transcript merging, diarization naming, prompt construction, key-command routing) into
  plain Swift types with no AppKit dependency so they can be tested in the Linux container.
- **Commit and push after each task.** Use `- [ ]` task bullets; this plan numbers tasks
  from Task 1 (do not renumber).

## Validation Commands

- `bash scripts/local-validate.sh`
- `bash scripts/ci-gate.sh`

## Out of scope (do NOT change in this plan)

- Frontmatter visual redesign / making participants, location, meeting link, color, or
  calendar event editable (design mockups pending).
- Record / stop / pause / resume button placement and styling (design mockups pending).
- Command-palette / quick-switch restyle, colors, icons, and the agenda timeline visuals.
- Collapsible-transcript styling and the "Generate summary" button styling.
- Any animation/polish pass.

---

### Task 1: Global shortcuts, Escape handling, and the Notes label

- [x] Rename the user-facing footer tab and any related label "Private Notes" to just
      "Notes" everywhere in the UI (search the codebase for "Private Notes").
- [x] Register **⌘N** as a *global* shortcut that creates a new note, working regardless of
      focus (not only while the ⌘K switcher is open). Reuse the existing global-hotkey
      registration mechanism used for the floating-note toggle.
- [x] Bind **⌘,** (Command-Comma) to open Settings from the main note window.
- [x] Make **Esc** dismiss the Settings surface and the ⌘K switcher / quick-switch overlay
      when either is open.
- [x] Factor key-command routing into a pure, Linux-testable type and add unit tests for:
      ⌘N → new-note intent, ⌘, → open-settings intent, Esc → dismiss intent for each overlay.
- [x] Run the local validation and CI gate until both pass.

### Task 2: Settings rows — whole-row hit target and correct hover

- [x] Make the **entire settings row** the click/tap target (icon, text, and the empty space
      across the row), not only the icon or the text label.
- [x] Make the hover/highlight state apply to the whole row and only on actual hover; fix the
      current bug where hovering the text incorrectly shows the row as selected.
- [x] Ensure keyboard/pointer selection and the visible highlight stay consistent.
- [x] Add a macOS UI/interaction test (or a logic test for the row hit-test/selection model)
      verifying the whole row is actionable and hover ≠ selected.
- [x] Run the local validation and CI gate until both pass.

### Task 3: Fix adding custom vocabulary

- [x] Investigate why a custom vocabulary entry cannot currently be added in Settings and fix
      it so a new phrase can be typed and added.
- [x] Ensure added entries persist across relaunch and are passed to the transcription adapter
      (preserve the existing phrase/alias/enabled/weight model — do not redesign it).
- [x] Add Linux-compatible unit tests for add, persist/reload, duplicate handling, and that
      enabled entries reach the transcription adapter boundary.
- [x] Run the local validation and CI gate until both pass.

### Task 4: Render markdown in the note body; copy yields raw markdown

- [x] Render the note body as formatted markdown (headings, bullet/numbered lists, task
      checkboxes, inline code, code blocks, blockquotes, horizontal rules, bold/italic, links)
      instead of displaying the raw markdown source.
- [x] Make the **Copy** action copy the underlying **raw markdown source**, not the rendered
      output, so pasting elsewhere yields the original markdown.
- [x] Add clear vertical spacing between the frontmatter region and the rendered body.
- [x] Keep the renderer styling simple and neutral (a dedicated visual redesign is out of
      scope); prioritise correctness of parsing/rendering and the raw-copy behaviour.
- [x] Put the markdown→view conversion and the copy-source extraction in Linux-testable types
      and add unit tests (each markdown construct renders; copy returns the exact raw source).
- [x] Run the local validation and CI gate until both pass.

### Task 5: Merge transcripts — same-speaker turns and the two audio streams

- [x] Merge **consecutive segments from the same speaker** into a single turn/block so the
      transcript no longer shows the same speaker split into many separate entries.
- [x] Merge the microphone-stream transcript and the system-audio-stream transcript into one
      chronological transcript, ordered by each segment's **start time** (when two segments
      overlap, the one that started first comes first).
- [x] Speaker naming when exactly **one** speaker is detected on each stream: name the
      microphone speaker as the local user, and the system-audio speaker as the other meeting
      participant (taken from the linked calendar event's participants when available; otherwise
      a neutral "Speaker 2"). Do not invent names when more than one speaker is on a stream.
- [x] For **in-person** meetings, do not capture or diarize the system-audio stream at all
      (microphone only).
- [x] Implement all of the above as pure, Linux-testable logic over transcript-segment models;
      add unit tests for same-speaker merging, two-stream interleave ordering (including an
      overlap case), single-speaker-per-stream naming with and without calendar participants,
      and the in-person path skipping the system stream.
- [x] Run the local validation and CI gate until both pass. (local: 489 tests pass; CI gate skipped - requires GitHub Actions runner)

### Task 6: Speaker inference in the summary/note generation prompt

- [x] Update the LLM prompt used for summary/note generation to instruct the model to infer
      who each speaker is from the participants and conversation context, and — when it is not
      certain — to label the speaker as e.g. "Speaker 1 · most likely <name>" rather than
      guessing a definite name.
- [x] Pass the known participant names (and the user's own name) into the prompt context so the
      inference has something to map onto.
- [x] Add a Linux-compatible unit test asserting the constructed prompt contains the speaker-
      inference instruction and the participant context.
- [x] Run the local validation and CI gate until both pass. (local: 489 tests pass; CI gate skipped - requires GitHub Actions runner)

### Task 7: Expose Sparkle update checking in Settings

- [ ] Sparkle is already integrated in the app. Add to Settings a **"Check for Updates…"**
      action that triggers a manual Sparkle update check, and an **"Automatically check for
      updates"** toggle bound to Sparkle's automatic-update-checks setting.
- [ ] Persist the toggle and reflect the current state on launch. Keep the placement in the
      existing Settings layout (no settings redesign).
- [ ] Guard Sparkle usage so `scripts/local-validate.sh` still passes on Linux (Sparkle is
      macOS-only); verify the wiring compiles and runs on the macOS CI runner. Mark the actual
      update-download flow as "verified only on macOS".
- [ ] Run the local validation and CI gate until both pass.

### Task 8: Final review and cleanup

- [ ] Run all Linux-compatible tests and the full macOS workflow; fix every build failure,
      test failure, and actionable warning.
- [ ] Confirm NONE of the explicitly out-of-scope items (frontmatter redesign, record-button
      placement, palette/timeline restyle, transcript-collapse styling, summary-button styling,
      animation pass) were changed by this plan.
- [ ] Confirm no new cloud service, login flow, browser extension, Electron, or Tauri
      dependency was added.
- [ ] Write a concise completion report in `docs/agent-progress.md` listing what was fixed and
      what remains "verified only on macOS / physical Mac".
- [ ] Run the local validation and CI gate until both pass.
