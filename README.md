# NoteTakr

A native, local-first macOS menu-bar app that records meeting audio and
generates structured notes — no cloud, no account required.

## What it does

- Sits in the macOS menu bar and detects upcoming calendar meetings
  (Google Meet, Zoom, Microsoft Teams, and generic meeting events).
- Sends a notification shortly before each detected meeting with a
  one-tap "Start Recording" action.
- Records microphone audio and system audio as separate local files.
- Generates a Markdown note with metadata, personal notes, and (optionally)
  timestamped transcript segments.
- Stores everything as plain JSON and audio files under
  `~/Library/Application Support/NoteTakr/`.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later (for building from source)
- Swift 5.9 or later

## Building from source

```
git clone https://github.com/<org>/notetakr.git
cd notetakr
open Notetakr.xcodeproj
```

Select the `NoteTakr` scheme, choose `My Mac` as the destination, and press
Cmd+R. The app appears in the menu bar as a microphone icon.

## Running automated tests

Linux-compatible Swift package tests:
```
bash scripts/local-validate.sh
```

Full macOS test suite (requires Xcode):
```
xcodebuild test \
  -project Notetakr.xcodeproj \
  -scheme NoteTakr \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

CI runs both suites automatically on every push via
`.github/workflows/macos-ci.yml`.

## First-launch permissions

On first launch, NoteTakr shows permission status but does not ask for protected
resource access. Open menu bar > Settings… > Permissions and click the grant
button for each permission you want to enable:

| Permission | Required for |
|------------|--------------|
| Calendars | Detecting upcoming meetings |
| Microphone | Recording your voice |
| Screen Recording | Capturing system audio via ScreenCaptureKit |

You can also review and grant permissions at any time from
menu bar > Settings… > Permissions.

### Screen Recording troubleshooting

macOS Screen Recording permission is tied to the exact app bundle that is
running. If you granted `/Applications/NoteTakr.app` but are launching the app
from Xcode, grant the Xcode-built app instead. Find the debug app with:

```sh
find ~/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Debug/NoteTakr.app' -type d -print
```

Reveal the app you are actually testing, then drag that app into System Settings
> Privacy & Security > Screen Recording:

```sh
open -R "/path/to/NoteTakr.app"
```

If macOS has a stale permission entry, reset it and grant again from NoteTakr
Settings:

```sh
tccutil reset ScreenCapture com.notetakr.app
```

## Current limitations

- **Real audio capture requires a physical Mac.** The automated CI suite uses a
  mock audio recorder. `NativeAudioRecorder` (microphone via `AVAudioRecorder`)
  and `SystemAudioCapturer` (system audio via `ScreenCaptureKit`) have not been
  verified on real hardware yet. See `docs/manual-smoke-test.md` for the
  verification checklist.

- **Local transcription is not enabled by default.** The `FluidAudioAdapter`
  skeleton is wired up but model downloading and inference are disabled in
  automated CI. Transcription currently uses a mock engine that returns fixture
  data. Real Parakeet / FluidAudio integration requires a physical Mac with the
  model downloaded.

- **Calendar detection is heuristic.** The app scores events by URL patterns
  and keywords. Events without recognisable video-call URLs or meeting keywords
  are not flagged as likely meetings.

- **System audio capture may be absent on some hardware.** If Screen Recording
  permission is not granted, or ScreenCaptureKit is unavailable, system audio
  capture is silently skipped. Only `microphone.m4a` is saved in that case.

## File layout

```
~/Library/Application Support/NoteTakr/
  Sessions/
    YYYY-MM-DD_<title>/
      session.json        — session metadata and status
      microphone.m4a      — microphone recording
      system-audio.m4a    — system audio recording (when available)
      note.md             — generated Markdown note
  vocabulary.json         — custom vocabulary entries for transcription boosting
```

## Documentation

- `docs/manual-smoke-test.md` — step-by-step physical Mac verification guide
- `docs/plans/20260608-meeting-notes-mvp.md` — original implementation plan
