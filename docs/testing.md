# Testing and release gates

## What runs in CI

`macOS CI` runs on every push and pull request:

| Job | Boundary covered |
| --- | --- |
| Workflow lint | Parses and statically checks every GitHub Actions workflow with a checksum-pinned `actionlint` binary |
| Kit Tests | Foundation-only note models, frontmatter, templates, Obsidian rendering, settings, and presenter state |
| Swift Package Tests | Recording/session orchestration, synthetic WAV fixtures, transcription seams, sync outbox, file-spool backend, and the meeting lifecycle integration test |
| Convex Tests | Meeting mutations, summaries, CRM matching/push logic, provider contracts, and TypeScript typechecking |
| Live CRM tests | Real Twenty or Attio HTTP calls that create a uniquely tagged fake contact/note, verify it, update it, and clean it up |
| Xcode Build & Test | The real macOS app target and app-level unit/integration tests; GUI tests are excluded here to keep failures attributable |
| Hosted GUI E2E | On `main` pushes and manual CI runs, launches the app with isolated storage and deterministic mock boundaries |

Canonical-repository pushes require at least one live test CRM. Pull requests and
forks do not receive repository secrets, so they run the deterministic CRM
provider tests without touching an external account.

## What “E2E” means here

There are several useful boundaries; they should not be conflated:

- `MeetingLifecycleE2ETests` is an in-process lifecycle integration test. It
  creates distinct, valid 16 kHz mono PCM mic/system files, verifies that the
  transcription seam reads them, persists a multi-speaker session, writes an
  Obsidian file, and serializes the cloud payload. Its transcription engine and
  cloud backend are deterministic fakes.
- `NoteTakrUITests` is application E2E with controlled boundaries. It launches
  the actual app, clicks controls, reads persisted files, exercises mock
  recording and file-spool sync, and verifies automatic Obsidian output. It does
  not use real TCC prompts, microphone hardware, ScreenCaptureKit, FluidAudio,
  Clerk, or deployed Convex.
- The Twenty and Attio integration suites are real network tests at the CRM
  provider boundary. They do not start from the Mac UI or pass through a
  deployed Convex action.
- `testOptInRealVaultRoundTrip` writes to an explicitly supplied real Obsidian
  folder, verifies the Markdown, and deletes its uniquely identified fake note.
  It tests filesystem compatibility, not the app UI.

No normal CI test uses private meeting notes or a real person’s recorded voice.

## Release gate

`Release DMG` is triggered by a completed `macOS CI` run on `main`, not directly
by a push. It resolves and checks out the exact tested commit. Failed or
cancelled CI prevents the archive job from starting. Manual releases query
GitHub Actions and fail unless the selected commit already has a successful
`macOS CI` run.

After building, CI verifies the DMG before artifact upload:

1. Verify and mount the disk image.
2. Confirm the packaged app exists.
3. Confirm bundle identifier and marketing version.
4. Verify the app’s deep code signature.
5. Confirm the executable exists.

Only then can GitHub Release, Homebrew, and Sparkle publication steps run.

## Highest-value fixture improvements

1. Add a nightly real-ASR fixture. Generate privacy-safe spoken sentences with
   macOS voices, download a pinned FluidAudio model, and assert transcript
   keywords plus timestamps. Keep this out of per-push CI until model caching
   and runtime are reliable.
2. Add a staging cloud E2E. Start from a real client upload, use a dedicated
   Clerk test identity and Convex staging deployment, wait for summary/CRM
   status, then remove the meeting and CRM fixtures.
3. Add failure-path lifecycle scenarios: offline outbox retry, duplicate sync,
   app restart between recording and transcription, partial mic/system capture,
   unwritable Obsidian folders, and CRM cleanup failure diagnostics.
4. Add fixture manifests with stable IDs, expected participant/source mappings,
   expected output hashes, and explicit schema versions. This makes fixture
   migrations reviewable instead of silently changing expectations.
5. Add packaged-app launch validation on a clean, pre-authorized physical Mac.
   Hosted runners cannot faithfully test TCC prompts or real system audio.

External test accounts must be dedicated test tenants. Every created record
should carry the run ID and `[nt-test]` prefix, and cleanup should run in
`finally` blocks plus a scheduled stale-fixture sweeper.
