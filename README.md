# NoteTakr

A native, local-first macOS menu-bar app that records meeting audio and
generates structured notes. Local recording and local summaries require no
account; optional Google sign-in enables Convex sync, server summaries, and CRM
push.

## What it does

- Sits in the macOS menu bar and detects upcoming calendar meetings
  (Google Meet, Zoom, Microsoft Teams, and generic meeting events).
- Sends a notification shortly before each detected meeting with a
  one-tap "Start Recording" action.
- Records microphone audio and system audio as separate local files.
- Generates a Markdown note with metadata, personal notes, and (optionally)
  timestamped transcript segments.
- Offers optional cloud sync through Convex: finished meetings can be uploaded
  without audio, summarized server-side, and mirrored back into the Summary tab.
- Suggests people from Apple Contacts, CRM cache, calendar attendees, and past
  meetings; CRM-backed people keep their remote ID for automatic matching.
- Pushes the generated summary and transcript to matched Twenty CRM people when
  CRM is connected, with a per-meeting opt-out and unmatched-participant banner.
- Keeps privacy controls local-first: `local_only` meetings never enqueue for
  sync, and CRM push can be disabled per meeting.
- Stores everything as plain JSON and audio files under
  `~/Library/Application Support/NoteTakr/`.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later for local app builds, previews, archives, and XCTest
- Swift 5.9 or later
- Node.js LTS and npm for Convex function tests and typechecking

## Install

### Homebrew (recommended)

```
brew tap luiskisters/notetakr https://github.com/luisKisters/notetakr
brew install --cask notetakr
```

Homebrew strips the download quarantine attribute on install, so the app launches
**without any Gatekeeper prompt** — even though the current builds are only
ad-hoc signed (see below). Update later with `brew upgrade --cask notetakr`.

If you have `HOMEBREW_REQUIRE_TAP_TRUST` set, Homebrew refuses to load the cask
from this third-party tap until you trust it once:
`brew trust --cask luiskisters/notetakr/notetakr`. Most setups don't set that
variable and can skip this step.

### Direct download (.dmg)

Download the latest `.dmg` from the [Releases page](https://github.com/luisKisters/notetakr/releases),
open it, and drag **NoteTakr** into Applications.

Because the build is ad-hoc signed and **not notarized** (Apple notarization
requires a paid Apple Developer Program membership), macOS blocks the first
launch with a message like *"Apple could not verify NoteTakr is free of malware."*
To allow it — **only needed for direct downloads, not for Homebrew installs:**

1. Double-click the app once; macOS blocks it.
2. Open **System Settings → Privacy & Security** and scroll to the Security section.
3. Click **Open Anyway** next to the NoteTakr message, then confirm **Open Anyway** again.

This is a one-time step per installed version.

## GitHub release DMG

The canonical app bundle and DMG are built by GitHub Actions on macOS runners.
Every push to `main` runs the `Release DMG` workflow, builds the DMG, publishes
it to a GitHub Release, and updates the Homebrew cask. When the signing secrets
below are present it signs with a Developer ID certificate, notarizes the DMG,
and publishes the in-app Sparkle update feed; when they are absent it falls back
to an **ad-hoc signature** (no notarization, no Sparkle feed) so the build still
succeeds and remains installable via Homebrew. Adding the secrets later flips the
same workflow to the full signed-and-notarized path with no other changes.

The signed-and-notarized release path requires these repository secrets (a paid
Apple Developer Program membership and a Developer ID Application certificate are
needed to produce them):

| Secret | Purpose |
|--------|---------|
| `BUILD_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application `.p12` certificate |
| `P12_PASSWORD` | Password for the exported `.p12` certificate |
| `KEYCHAIN_PASSWORD` | Temporary CI keychain password |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for the Apple ID |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `SPARKLE_PRIVATE_ED_KEY` | Private EdDSA key used by Sparkle's `generate_appcast` tool |
| `SPARKLE_PUBLIC_ED_KEY` | Public EdDSA key embedded in the app for Sparkle update verification |
| `APPLE_DEVELOPER_ID_APPLICATION` | Optional exact signing identity name, e.g. `Developer ID Application: Name (TEAMID)` |

The DMG does not bundle FluidAudio model files. Configure the model in Settings
after installing the app.

In-app Sparkle automatic updates turn on only when the signing secrets are
present (the public key must be embedded at build time and the appcast must be
EdDSA-signed). Until then, update through Homebrew. When enabled, each published
release generates a signed `appcast.xml` that points at the GitHub Release DMG,
then publishes that feed to:

```
https://raw.githubusercontent.com/luiskisters/notetakr/gh-pages/appcast.xml
```

Generate the Sparkle key pair once with Sparkle's `generate_keys` tool, store
the private key in `SPARKLE_PRIVATE_ED_KEY`, and store the matching public key
in `SPARKLE_PUBLIC_ED_KEY`. Local builds without a public key skip starting the
updater so development launches still work.

GitHub-hosted macOS runners consume Actions minutes. Public repositories are
generally free for standard GitHub-hosted runners; private repositories use the
included quota for your plan and then bill for extra minutes, with macOS minutes
charged at a higher multiplier than Linux minutes. If frequent `main` pushes
become expensive, keep the test workflow on all branches and reserve signed DMG
releases for tags or manual dispatch.

## Building from source

```
git clone https://github.com/<org>/notetakr.git
cd notetakr
open Notetakr.xcodeproj
```

Select the `NoteTakr` scheme, choose `My Mac` as the destination, and press
Cmd+R. The app appears in the menu bar as a microphone icon.

Local SwiftPM work does not require full Xcode:

```
swift build --target NoteTakrCore
swift build --target NoteTakrTranscriptionProbe
```

Convex work uses the top-level `convex/` package:

```
cd convex
npm ci
npm test
npm run typecheck
```

Probe a local FluidAudio model folder:

```
swift run NoteTakrTranscriptionProbe \
  --audio /path/to/audio.wav \
  --model-folder /path/to/parakeet-tdt-0.6b-v3-coreml \
  --version v3
```

Probe FluidAudio automatic cache download:

```
swift run NoteTakrTranscriptionProbe \
  --audio /path/to/audio.wav \
  --auto-download \
  --version tdtCtc110m
```

## Running automated checks

SwiftPM build checks:

```
swift build --target NoteTakrCore
swift build --target NoteTakrTranscriptionProbe
```

Swift package tests require an XCTest-capable local toolchain:

```
swift test
```

Convex checks:

```
cd convex
npm test
npm run typecheck
```

Full macOS test suite (requires Xcode):
```
xcodebuild test \
  -project Notetakr.xcodeproj \
  -scheme NoteTakr \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

CI runs Swift and Convex suites automatically on every push via
`.github/workflows/macos-ci.yml`.

## Cloud sync, summaries, and CRM

Cloud features are optional. Without the following configuration, the app stays
signed out and local behavior remains available.

App launch/build configuration:

| Variable | Purpose |
|----------|---------|
| `NOTETAKR_CONVEX_DEPLOYMENT_URL`, `CONVEX_DEPLOYMENT_URL`, or `CONVEX_URL` | Convex deployment URL used by the Mac app |
| `NOTETAKR_CLERK_PUBLISHABLE_KEY` or `CLERK_PUBLISHABLE_KEY` | Clerk publishable key for Google sign-in |
| `NOTETAKR_CLERK_CALLBACK_SCHEME` | Optional OAuth callback URL scheme; defaults to the bundle identifier |

Convex environment:

| Variable | Purpose |
|----------|---------|
| `OPENROUTER_API_KEY` | Required for server-side summaries |
| `SUMMARY_MODEL` | Optional OpenRouter model override; defaults to `moonshotai/kimi-k2.7-code` |
| `CRM_SECRET_ENCRYPTION_KEY` | Required before saving CRM API keys; used to encrypt per-user CRM credentials in Convex |

Live CRM integration tests are skipped unless these variables or CI secrets are
present:

| Variable | Purpose |
|----------|---------|
| `TWENTY_TEST_BASE_URL` | Live Twenty instance base URL |
| `TWENTY_TEST_API_KEY` | Live Twenty API key |
| `ATTIO_TEST_API_KEY` | Live Attio API key |

CRM API keys entered in the Mac settings are stored in the local Keychain and,
after a successful connection test, saved encrypted in Convex for background
mirror/push actions.

## First-launch permissions

On first launch, NoteTakr shows permission status but does not ask for protected
resource access. Open menu bar > Settings… > Permissions and click the grant
button for each permission you want to enable:

| Permission | Required for |
|------------|--------------|
| Calendars | Detecting upcoming meetings |
| Contacts | People suggestions and attendee name enrichment |
| Microphone | Recording your voice |
| Screen Recording | Capturing system audio via ScreenCaptureKit |

You can also review and grant permissions at any time from
menu bar > Settings… > Permissions.

## Transcription model setup

Open menu bar > Settings… > Transcription Model and choose one model source:

- `Select Model Folder...` for an existing FluidAudio Parakeet CoreML repo folder.
- `Use Automatic Download` to let FluidAudio download and load from its cache.
- `Clear` to return to the not-configured state.

The selected source and model version are stored in
`~/Library/Application Support/NoteTakr/transcription-settings.json`.

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

- **Local transcription needs model setup.** `FluidAudioAdapter` links the
  FluidAudio package and can load a selected model folder or use FluidAudio's
  automatic cache download. Normal CI and DMG builds do not download Parakeet
  models, so real transcription quality still needs physical-Mac validation.

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
  Outbox/
    <localId>.json        — pending sync payloads
  PeopleCache.json        — cached CRM people snapshot for the picker
  settings.json           — app defaults, CRM base URL, and meeting defaults
  summary-templates.json
  summarization-settings.json
  vocabulary.json         — custom vocabulary entries for transcription boosting
  transcription-settings.json
                          — FluidAudio model source and version selection
```

`note.md` frontmatter includes the meeting metadata plus sync/CRM keys when
set:

- `local_only` — true means the meeting is never uploaded.
- `crm_push_opt_out` — true means the meeting may sync but will not push to CRM.
- `crm_push_status` — server-reported CRM push state: `pending`, `pushed`,
  `failed`, or `skipped`.
- participant `crm` fields — remote CRM person IDs used for exact CRM matching.

## Documentation

- `docs/manual-smoke-test.md` — step-by-step physical Mac verification guide
- `docs/plans/20260608-meeting-notes-mvp.md` — original implementation plan
