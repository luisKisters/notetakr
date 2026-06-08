# PRD: NoteTakr Next Product Phase

## Overview

NoteTakr now has a working native macOS permission flow and can create separate
microphone and system-audio recordings on a physical Mac. The next product
phase turns that working capture foundation into a reliable end-to-end meeting
notes tool: stable builds/signing, real local transcription, clearer recording
status, and a polished permissions/setup experience.

This PRD is written for unattended execution by ralphex.

## Ralphex Execution Rules

- Work fully autonomously. Do not pause for confirmation; make reasonable
  product and engineering decisions and continue.
- Commit and push after each completed task.
- Keep Linux-compatible tests runnable locally. macOS-only behavior must be
  isolated behind adapters/protocols and verified on macOS CI or a physical Mac.
- Do not introduce cloud transcription, Electron, Tauri, browser extensions, or
  external login flows.
- Prefer local-first behavior. Recordings, transcripts, vocabulary, and notes
  remain local files unless a later PRD explicitly changes that.
- Do not claim hardware-dependent capture or transcription works until it is
  verified on a physical Mac and documented in `docs/manual-smoke-test.md`.

## Problem

The app can record, but it is not yet production-ready:

- Rebuilds currently rely on manual/ad-hoc signing during local testing, which
  makes macOS TCC permissions fragile.
- Real transcription is not implemented; the FluidAudio adapter is a skeleton.
- Recording output exists, but the UI does not clearly prove whether microphone
  and system audio were captured successfully.
- Permission UX works but needs polish, especially around Screen Recording
  requiring app restart.
- Vocabulary boosting storage exists, but its value is blocked until real
  transcription is wired up.

## Goals

1. Provide a stable macOS build/signing workflow that preserves permissions
   across normal app updates.
2. Implement local transcription for recorded audio using the existing
   `TranscriptionEngine` boundary.
3. Make recording completion self-explanatory by showing captured file status,
   duration, and audio-source availability.
4. Improve first-run and permission UX so users know exactly what to grant,
   what requires restart, and what is already working.
5. Keep the product local-first and testable through existing CI gates.

## Non-Goals

- No cloud transcription service.
- No account system.
- No meeting bot joining calls.
- No app distribution/notarization requirement beyond a local signed build path,
  unless needed to stabilize permissions.
- No redesign into a web or Electron app.

## User Stories

- As a user, I can install or run NoteTakr and grant permissions once without
  being forced through repeated prompts after every restart.
- As a user, I can record a meeting and immediately see whether microphone and
  system audio were captured.
- As a user, I can transcribe a completed recording locally.
- As a user, I can add custom vocabulary and see it affect transcription input.
- As a user, I can open a generated note with transcript, timestamps, personal
  notes, and session metadata.

## Functional Requirements

### Build and Signing

- Provide a repeatable local macOS build command or script for creating
  `/Applications/NoteTakr.app`.
- Use a consistent bundle identifier: `com.notetakr.app`.
- Avoid unnecessary TCC resets during normal rebuilds.
- Document how to select/install Xcode if `xcodebuild` is unavailable.
- Preserve the existing Linux-safe validation path.

### Permissions

- The app must not request Calendar, Microphone, Screen Recording, or
  Notifications on launch.
- Permission prompts must happen only from explicit user actions.
- Calendar status must show `Granted` after restart when macOS has already
  granted it.
- Screen Recording must clearly show that restart is required after the user
  enables it in System Settings.
- `Refresh Status` must not imply that Screen Recording can always be applied
  without restart.

### Recording

- Continue saving separate local files:
  - `microphone.m4a`
  - `system-audio.m4a`
- After stopping a recording, show per-source status:
  - present/missing
  - duration
  - approximate file size
- If system audio is missing, show a concise reason when available:
  - permission not granted
  - ScreenCaptureKit unavailable
  - capture start failure
  - no samples received
- Keep recording behavior isolated behind `AudioRecorder`.

### Transcription

- Implement a real local transcription path behind `TranscriptionEngine`.
- Keep `MockTranscriptionEngine` for tests.
- Keep expensive model download/inference disabled in CI.
- If the local model is missing, show a clear unavailable state instead of
  silently falling back in user-facing flows.
- Pass enabled vocabulary entries into the transcription engine.
- Save transcript segments into `session.json`.
- Generate/update `note.md` after transcription.

### Vocabulary

- Keep vocabulary entries local in `vocabulary.json`.
- The Add button should enable when the input contains non-whitespace text.
- Support phrase, enabled state, aliases, and boosting weight.
- Add tests for empty input, trimming, persistence, and enabled-entry filtering.

## Acceptance Criteria

- `swift build` passes locally.
- `bash scripts/local-validate.sh` passes in Linux-compatible environments.
- macOS CI builds the app target with `xcodebuild`.
- Manual smoke test confirms:
  - no permission prompt on launch;
  - Microphone grant works;
  - Calendar grant persists across restart;
  - Screen Recording grant works after restart;
  - microphone and system-audio files are created;
  - system-audio file contains audible system audio;
  - completed session shows per-source capture status;
  - transcription can be run locally when the model is available.

## Implementation Plan

### Task 1: Stabilize macOS Build and Signing

- [x] Add a `scripts/build-macos-app.sh` script.
- [x] Build the app into a deterministic local output path.
- [x] Install or copy the app into `/Applications/NoteTakr.app` only when
      explicitly requested by a flag.
- [x] Preserve bundle identifier and entitlements.
- [x] Document Xcode installation/selection requirements.
- [x] Update `docs/manual-smoke-test.md`.
- [x] Run validation and commit.

### Task 2: Polish Permission UX

- [ ] Keep Settings as a regular foreground window for local builds.
- [ ] Make Screen Recording state copy explicit: grant, restart required,
      granted.
- [ ] Add a visible explanation for why Screen Recording needs restart.
- [ ] Ensure Calendar status refreshes on launch without prompting.
- [ ] Add unit or UI tests where practical.
- [ ] Run validation and commit.

### Task 3: Add Recording Source Status

- [ ] Add a small audio-file metadata reader for duration and file size.
- [ ] Store capture status in session metadata or derive it from files.
- [ ] Show microphone/system-audio status in session detail.
- [ ] Add missing-source messaging.
- [ ] Add tests for present/missing file states.
- [ ] Run validation and commit.

### Task 4: Implement Local Transcription

- [ ] Choose and wire the local transcription dependency.
- [ ] Keep model lookup configurable and local.
- [ ] Add user-facing model missing state.
- [ ] Transcribe completed recordings and persist transcript segments.
- [ ] Preserve mock transcription tests.
- [ ] Document physical Mac verification requirements.
- [ ] Run validation and commit.

### Task 5: Improve Notes Generation

- [ ] Regenerate `note.md` after transcription completes.
- [ ] Include session title, date, audio sources, transcript, and personal notes.
- [ ] Add an obvious Open Note action in session detail.
- [ ] Add tests for rendered note content.
- [ ] Run validation and commit.

### Task 6: Final E2E Smoke Test

- [ ] Run the manual physical Mac smoke test.
- [ ] Confirm microphone and system audio are audible.
- [ ] Confirm Calendar permission persists across restart.
- [ ] Confirm Screen Recording applies after restart.
- [ ] Confirm transcription and note generation work locally.
- [ ] Update `docs/agent-progress.md`.
- [ ] Push final branch and verify CI.

## Risks

- macOS TCC behavior depends on signing identity, bundle identifier, and exact
  app bundle path.
- ScreenCaptureKit system audio behavior is hardware and macOS-version
  dependent.
- Local transcription dependencies may be large or unavailable on CI.
- Xcode is required for reliable native macOS app builds.

## Open Questions

- Which signing identity should be used for local and distribution builds?
- Which local transcription model should be the default?
- Should NoteTakr stay a regular foreground app, return to menu-bar-only, or
  support both modes?
- Should system audio and microphone be transcribed separately or mixed into a
  single transcription input?
