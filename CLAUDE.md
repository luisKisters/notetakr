# NoteTakr Development Notes

## Architecture

- `NoteTakrKit` is Foundation-only app logic: note/frontmatter models, presenters, people directory, settings stores, Obsidian template/export logic, and pure UI state machines. Keep logic here when it does not need AppKit, AVFoundation, or Convex SDKs.
- `Sources/NoteTakrCore` owns recording, transcription, summarization, calendar models, and session storage. It may depend on `NoteTakrKit`.
- `Sources/NoteTakrSync` owns sync payloads, outbox persistence, backend protocols, Convex backend adapters, file-spool e2e backend, and CRM people cache. Clerk/Convex SDK symbols stay hidden behind this target.
- `NoteTakrApp` wires app services, SwiftUI/AppKit views, settings, and bridges. AppModel owns the sync service, account state, CRM connection state, and dirty hooks.
- `convex/` contains Convex schema, meeting upserts, OpenRouter summary action, people mirror, CRM push, and CRM provider adapters.

## Sync and CRM Rules

- Signed out must not open sync network streams or push outbox payloads.
- `local_only` meetings never enqueue for sync; toggling a note local-only also clears pending outbox payloads for that local ID.
- Mac owns meeting content: title, date, participants, note body, transcript, and sync opt-out flags.
- Convex owns server `summary`, `summaryStatus`, CRM `pushStatus`, unmatched participants, and people mirror data.
- Summary updates from Convex can be `ready` or `failed`; failed updates must set a failed Summary tab state and resume any waiters by throwing.
- CRM connection state in the app means server-verified configuration, not just local text fields or Keychain values.
- CRM API keys are read from the local Keychain on the Mac and stored encrypted in Convex as `encryptedApiKey`; Convex needs `CRM_SECRET_ENCRYPTION_KEY`.
- CRM providers are selected by `userSettings.crm.provider`; Twenty and Attio use the shared provider interface.

## People Sources

- Picker priority is Contacts, CRM cache, then past meetings.
- CRM-backed `Person.sourceRefs` use provider `crm`; selecting or auto-matching one stores the remote person ID in `Participant.crm`.
- The unmatched CRM banner should ignore participants whose email matches a CRM-backed person, even if the note participant did not already store `crm`.

## Test Commands

- Kit logic: `cd NoteTakrKit && swift test`
- Sync/Core target builds: `swift build --target NoteTakrSyncTests` and `swift build --target NoteTakrCoreTests`
- Convex unit/integration-gated tests: `cd convex && npm test`
- Convex typecheck: `cd convex && npm run typecheck`
- Opt-in real-vault export smoke test:
  `NOTETAKR_OBSIDIAN_E2E_ROOT=/path/to/meeting-notes swift test --package-path NoteTakrKit --filter testOptInRealVaultRoundTrip`
- Full macOS app/UI tests require Xcode on macOS:
  `xcodebuild test -project Notetakr.xcodeproj -scheme NoteTakr -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`

On Linux, root `swift test` is blocked by FluidAudio's macOS-only `mach/mach.h`
dependency, and `xcodebuild` is unavailable.

## E2E Environment Seams

- `NOTETAKR_E2E_USE_MOCK_RECORDER=1` uses the mock recorder.
- `NOTETAKR_E2E_MOCK_SYNC_BACKEND=1` uses `FileSpoolSyncBackend`.
- `NOTETAKR_E2E_SYNC_SPOOL_ROOT` overrides the file-spool root.
- `NOTETAKR_E2E_MOCK_CRM_CONNECTED=1` forces CRM-connected UI state in DEBUG builds.
- `NOTETAKR_E2E_APP_SUPPORT_ROOT` isolates app support files for tests.
