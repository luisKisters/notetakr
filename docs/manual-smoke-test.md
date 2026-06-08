# NoteTakr Physical Mac Smoke Test

This document guides you through manually verifying NoteTakr on a physical Mac.
Run these steps after every significant change to audio capture or transcription.

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 15 or later installed
- A calendar account configured in System Settings > Internet Accounts
- A browser open with a tab that plays audio (e.g. YouTube)

## Local Xcode Launch Steps

1. Clone or pull the `meeting-notes-mvp` branch:
   ```
   git clone https://github.com/<org>/notetakr.git
   cd notetakr
   git checkout meeting-notes-mvp
   ```

2. Open the project in Xcode:
   ```
   open Notetakr.xcodeproj
   ```

3. Select the `NoteTakr` scheme and `My Mac` as the destination in the toolbar.

4. Press Cmd+R (or Product > Run) to build and launch the app.

5. The NoteTakr microphone icon appears in the macOS menu bar. If it does not
   appear, check the Xcode console for launch errors.

6. To run the automated test suite before manual testing:
   ```
   swift test
   ```
   And the Xcode test suite:
   ```
   xcodebuild test \
     -project Notetakr.xcodeproj \
     -scheme NoteTakr \
     -destination 'platform=macOS' \
     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
   ```

## Permission Checks

### Calendar Permission

- [ ] Click the menu-bar icon. Under "Next Meeting" the app should show a
      loading indicator briefly, then "Grant Calendar Access in Settings" when
      access has not been granted.
- [ ] Open the menu bar > Settings… (or press Cmd+,).
- [ ] Click "Grant Access" in the Calendar row. macOS prompts for Calendar
      access. Grant it.
- [ ] If access was previously denied: open System Settings > Privacy &
      Security > Calendars, find NoteTakr, and enable access. Click
      "Refresh Status" in Settings.
- [ ] After granting access, the next calendar meeting (if any in the next
      24 hours) should appear in the menu and the Today window.

### Microphone Permission

- [ ] Open the menu bar > Settings… (or press Cmd+,).
- [ ] The Microphone row should show "Not Set" on first launch.
- [ ] Click "Grant Access". macOS prompts for microphone access. Grant it.
- [ ] The Microphone row should now show "Granted" (green).
- [ ] If it shows "Denied": open System Settings > Privacy & Security >
      Microphone, enable NoteTakr, then click "Refresh Status" in Settings.

### System Audio Permission

- [ ] In Settings, the System Audio row should show "Not Set" on first launch.
- [ ] Click "Grant Access". macOS prompts for Screen Recording access
      (required by ScreenCaptureKit). Grant it.
- [ ] The System Audio row should now show "Granted" (green).
- [ ] If it shows "Denied": open System Settings > Privacy & Security >
      Screen Recording, enable NoteTakr, then click "Refresh Status".
- [ ] If the Screen Recording list contains `/Applications/NoteTakr.app` but
      you are running from Xcode, grant the Xcode-built app instead. Find it
      with:
      ```
      find ~/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Debug/NoteTakr.app' -type d -print
      ```
- [ ] If macOS keeps a stale Screen Recording entry, reset it, restart NoteTakr,
      and grant again from Settings:
      ```
      tccutil reset ScreenCapture com.notetakr.app
      ```

## Recording Checks

### Audible Microphone Recording

- [ ] Start a recording: click the menu-bar icon > "Start Recording"
      (or "Quick Recording" for an unscheduled call).
- [ ] The menu-bar icon turns red and the menu item reads "Stop Recording".
- [ ] Speak a sentence clearly into the microphone for at least 5 seconds.
- [ ] Click "Stop Recording".
- [ ] Open the recordings folder: menu-bar icon > "Open Recordings Folder".
- [ ] Navigate into the session folder. Confirm `microphone.m4a` exists and
      is non-empty (> 0 bytes).
- [ ] Open `microphone.m4a` in QuickTime. Confirm your voice is audible.

### Audible Browser Audio Recording

- [ ] Play audio in a browser tab (e.g. a YouTube video) — keep it playing.
- [ ] Start a new recording via "Start Recording".
- [ ] Let it record for at least 10 seconds while browser audio plays.
- [ ] Click "Stop Recording".
- [ ] Open the session folder in Finder. Confirm `system-audio.m4a` exists and
      is non-empty.
- [ ] Open `system-audio.m4a` in QuickTime. Confirm the browser audio is
      audible.
- [ ] If `system-audio.m4a` is missing: confirm Screen Recording permission is
      granted (see above). System audio capture is gracefully skipped when
      permission is absent — this is expected behaviour, not a crash.

### Separate Audio Files

- [ ] After a completed recording, open the session folder in Finder.
- [ ] Confirm both `microphone.m4a` and `system-audio.m4a` are present as
      separate files when both permissions are granted.
- [ ] Confirm that when only microphone permission is granted, only
      `microphone.m4a` is present (system audio is silently skipped).

## Note Generation

- [ ] Open Sessions: menu-bar icon > "Sessions…".
- [ ] Click a completed session row to open the detail view.
- [ ] Click "Generate Note". The note should open in the default Markdown
      viewer or text editor.
- [ ] Confirm the generated `note.md` contains the session title, date,
      personal notes section, and (if transcription was run) timestamped
      transcript segments.
- [ ] Alternatively use "Open Latest Note" from the menu bar to open the most
      recently generated note directly.

## Persistence After Relaunch

- [ ] With at least one completed session stored, quit the app (menu-bar icon >
      "Quit NoteTakr").
- [ ] Relaunch via Xcode (Cmd+R) or by double-clicking the built product.
- [ ] Open "Sessions…". Confirm previous sessions are listed with correct
      titles and statuses.
- [ ] Confirm that any session that was recording at quit time has been
      recovered as "stopped" (interrupted-session recovery).

## Notification Check

- [ ] Ensure a calendar meeting is scheduled within the next 10 minutes, or
      temporarily modify `MeetingNotificationScheduler` to fire sooner.
- [ ] Confirm a macOS notification banner appears with the meeting title and a
      "Start Recording" action button.
- [ ] Tap "Start Recording" in the notification. Confirm a new recording
      session starts and the Sessions window opens.

## Features Verified Automatically (CI)

The following are covered by automated tests that run on every push:

- Session model creation, status transitions, and JSON serialisation
- Session store: save, load, reload, folder sanitisation
- Interrupted-session recovery logic
- Calendar URL detection (Google Meet, Zoom, Teams) and keyword scoring
- Meeting detector sorting and empty-calendar edge cases
- RecordingManager start / stop / failure / interruption state machine
- End-to-end recording flow with MockAudioRecorder
- Vocabulary persistence, filtering, and Markdown note rendering
- Mock transcription engine output and segment parsing
- AudioPermissionManager state reporting (mock)
- Xcode build of NativeAudioRecorder, AudioPermissionManager,
  EventKitCalendarAdapter, FluidAudioAdapter, and all SwiftUI views
- UI automation: open Settings, add vocabulary, start mock recording, stop it,
  open generated note, open recordings folder

## Features Requiring Physical Mac Verification

The following cannot be verified in automated CI and require this smoke test:

- Audible microphone capture (`NativeAudioRecorder` + `AVAudioRecorder`)
- Audible system-audio capture (`SystemAudioCapturer` + `ScreenCaptureKit`)
- Separate `microphone.m4a` / `system-audio.m4a` files written to disk
- macOS permission prompts (Calendar, Microphone, Screen Recording)
- Meeting notification banner and "Start Recording" action
- Note opening in the system default app via `NSWorkspace`
- FluidAudio / Parakeet local transcription (model download disabled in CI)
