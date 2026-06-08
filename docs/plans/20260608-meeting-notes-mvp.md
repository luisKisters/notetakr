# Plan: Build Local-First macOS Meeting Notes MVP

## Overview

Build a native SwiftUI macOS menu-bar app that records system audio and microphone audio locally, prepares meeting notes, and supports local transcription through a replaceable adapter.

The implementation agent runs inside a Linux Docker container.

A GitHub Actions macOS runner is the source of truth for native compilation and automated macOS tests.

Every task represents one vertical product phase. Each task must include UI, underlying logic, and tests where applicable.

Do not proceed to the next task until:

1. local Linux-compatible tests pass;
2. the current branch is pushed to GitHub;
3. the macOS GitHub Actions workflow passes;
4. any CI failures have been investigated and repaired.

## Autonomy & Environment (unattended execution — READ FIRST)

This plan is executed UNATTENDED by ralphex inside a Linux Docker container
(Debian 12, non-root user; Node, git, and gh are available, but there is NO
Swift / Xcode / clang preinstalled). Follow these rules at all times:

- **Work fully autonomously.** Never pause to ask for confirmation or human
  input — make a reasonable decision and proceed. Use non-interactive flags
  everywhere; never leave a command waiting on an interactive prompt.
- **Install everything that is missing, yourself.** You run as a non-root user
  with no sudo/apt. Install the Swift-for-Linux toolchain into your home
  directory: prefer `swiftly`, or download the official Swift Linux tarball from
  swift.org into `$HOME` and add it to `PATH`. `scripts/local-validate.sh` must
  bootstrap the toolchain idempotently (install it only if missing) before
  running tests, so it works from a clean container on every run.
- **Never block on macOS-only or root-only steps.** If something genuinely
  requires macOS or root and cannot be done in the container, implement it
  behind the existing protocol/adapter, mark it clearly as "verified only on the
  macOS CI runner / physical Mac", and keep going. The macOS GitHub Actions
  runner is the source of truth for native compilation and tests.
- **Keep the local gate Linux-safe.** `scripts/local-validate.sh` runs only the
  Linux-runnable subset and must skip macOS-only steps gracefully — do not fail
  the gate merely because Swift/macOS APIs are unavailable locally; let CI cover
  those.
- **Commit and push after each task.**

## Validation Commands

* `bash scripts/local-validate.sh`
* `bash scripts/ci-gate.sh`

### Task 0: Bootstrap the repository and CI feedback loop

* [x] Create the Swift package and macOS SwiftUI application structure.
* [x] Create a minimal native macOS menu-bar app that launches and displays a placeholder Start Recording button.
* [x] Add `scripts/local-validate.sh` to run all tests available in Linux Docker.
* [x] Add `scripts/ci-gate.sh`.
* [x] Make `scripts/ci-gate.sh` commit dirty files, push the current branch, wait for the matching GitHub Actions run, print failed logs, and exit non-zero when CI fails.
* [x] Add `.github/workflows/macos-ci.yml`.
* [x] Configure the macOS workflow to run on every branch push.
* [x] Configure the workflow to run Swift package tests and build the macOS app with `xcodebuild`.
* [x] Add a basic macOS XCTest that confirms the app target launches.
* [x] Run the local validation and CI gate until both pass.

### Task 1: Add meeting sessions and local note storage

* [x] Add a Today view showing the next meeting placeholder and recent recording sessions.
* [x] Add a session detail view with title, date, recording status, transcript placeholder, and editable personal notes.
* [x] Add core models for meeting sessions, status transitions, transcript segments, and saved note metadata.
* [x] Store sessions as local JSON files in deterministic folders.
* [x] Add Linux-compatible unit tests for session creation, storage, folder sanitization, reload behavior, and interrupted sessions.
* [x] Add macOS tests confirming the native views compile and fixture sessions load.
* [x] Run the local validation and CI gate until both pass.

### Task 2: Add calendar-aware meeting preparation

* [x] Add an EventKit calendar adapter behind a protocol.
* [x] Add a mock calendar adapter for Linux-compatible tests.
* [x] Detect likely Google Meet, Zoom, and Microsoft Teams events from calendar URLs.
* [x] Add keyword fallback matching for generic meetings such as sync, call, meeting, standup, and interview.
* [x] Display the next likely meeting in the menu-bar interface.
* [x] Add a manual Quick Recording action for unscheduled calls.
* [x] Add unit tests for URL matching, keyword scoring, sorting, and empty-calendar behavior.
* [x] Add a macOS compile test for the EventKit adapter.
* [x] Run the local validation and CI gate until both pass.

### Task 3: Add the recording lifecycle with mock audio

* [x] Add an AudioRecorder protocol.
* [x] Add a mock recorder that creates fixture microphone and system-audio files.
* [x] Connect Start Recording and Stop Recording actions to the session state machine.
* [x] Make active recording state obvious in the menu-bar UI and session detail view.
* [x] Preserve incomplete sessions after relaunch.
* [x] Add tests for start, stop, failure, interruption, and recovery behavior.
* [x] Add an end-to-end test using the mock recorder.
* [x] Run the local validation and CI gate until both pass.

### Task 4: Add real macOS audio capture adapter

* [ ] Add a native macOS audio recorder adapter.
* [ ] Capture microphone audio as a separate local file.
* [ ] Add system-audio capture using the appropriate macOS audio API.
* [ ] Keep the real adapter isolated behind the existing AudioRecorder protocol.
* [ ] Add permission-state handling for microphone and system-audio access.
* [ ] Add a settings screen showing permission status.
* [ ] Add compile-time macOS tests and mock-driven behavior tests.
* [ ] Do not claim that real audio capture works until manually tested on a physical Mac.
* [ ] Run the local validation and CI gate until both pass.

### Task 5: Add local transcription architecture and vocabulary boosting

* [ ] Add a TranscriptionEngine protocol.
* [ ] Add a mock transcription engine using fixture transcript JSON.
* [ ] Add a FluidAudio adapter skeleton for local Parakeet transcription.
* [ ] Keep model downloading and expensive inference disabled in automated CI.
* [ ] Add a native vocabulary editor in Settings.
* [ ] Support phrases, aliases, enabled state, and boosting weights.
* [ ] Pass enabled vocabulary entries into the transcription adapter.
* [ ] Render transcript segments into the session detail view.
* [ ] Generate a Markdown note containing metadata, personal notes, and transcript timestamps.
* [ ] Add Linux-compatible tests for vocabulary persistence, filtering, Markdown rendering, and mock transcription.
* [ ] Add macOS compilation tests for the FluidAudio adapter boundary.
* [ ] Run the local validation and CI gate until both pass.

### Task 6: Add meeting-time notifications and MVP polish

* [ ] Add macOS notifications shortly before likely calendar meetings.
* [ ] Include a Start Recording action.
* [ ] Add native empty states, errors, loading states, and recording-state indicators.
* [ ] Add an Open Recordings Folder action.
* [ ] Add an Open Latest Note action.
* [ ] Add accessibility identifiers to important controls.
* [ ] Add UI automation tests for opening Settings, adding vocabulary, starting a mock recording, stopping it, and opening a generated note.
* [ ] Run the local validation and CI gate until both pass.

### Task 7: Document the physical Mac smoke test

* [ ] Create `docs/manual-smoke-test.md`.
* [ ] Document the exact local Xcode launch steps.
* [ ] Include checks for calendar permission, microphone permission, system-audio permission, audible microphone recording, audible browser audio recording, separate audio files, note generation, and persistence after relaunch.
* [ ] Clearly list which features were verified automatically and which still require a physical Mac.
* [ ] Update the README with setup instructions and the current limitations.
* [ ] Run the local validation and CI gate until both pass.

### Task 8: Final review and cleanup

* [ ] Run all Linux-compatible tests.
* [ ] Push the branch and wait for the complete macOS workflow.
* [ ] Fix every build failure, test failure, and actionable warning.
* [ ] Confirm that no cloud service, login flow, browser extension, Electron dependency, or Tauri dependency was added.
* [ ] Confirm that unverified real-world audio capture claims are clearly marked as requiring the physical Mac smoke test.
* [ ] Write a concise completion report in `docs/agent-progress.md`.
