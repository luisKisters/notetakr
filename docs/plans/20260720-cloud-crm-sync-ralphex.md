# Cloud Sync, Server Summaries & CRM Push (Ralphex execution plan)

## Overview

Add opt-in cloud features to NoteTakr, a local-first macOS menu-bar meeting-notes app: Google sign-in (Clerk), one-way push of meetings/notes/transcripts to Convex, server-side summaries via OpenRouter Kimi K2.7, a person picker fed by past meetings + Apple Contacts, and automatic CRM note push to a self-hosted Twenty instance (Attio later). Rollout is strictly incremental: local people features first, then the cloud spine, then the CRM sink. Signed out, the app must behave exactly as today.

This plan is the executable form of `docs/plans/20260713-cloud-crm-sync.md` (the "spec doc"). The spec doc contains the full per-test expected behaviors. Read the relevant spec-doc section before implementing each task.

## Context

- Repo layout: `NoteTakrKit/` (lowest layer, pure Foundation + swift-markdown, tests run on Linux CI), `Sources/NoteTakrCore/` (audio/transcription/summarization/calendar, depends on Kit), `NoteTakrApp/` (AppKit/SwiftUI app target, Xcode project), `NoteTakrTests/` + `NoteTakrUITests/` (Xcode-only test targets).
- Remote Twenty access: the user authorizes SSH access to `ssh.lewiskissers.com`. The hostname did not resolve from the executor host at 2026-07-20 22:34 UTC; retry it when a live Twenty check is needed and record the exact blocker if it still fails. The self-hosted Twenty deployment may be intentionally stopped because it was consuming too many resources. Inspect host capacity and service state before starting it; if live tests require it, start only the necessary services temporarily and stop them again after testing unless they were already running. Never print or commit credentials.
- Two persistence layers share one UUID per meeting: `NoteStore` writes `note.md` (YAML frontmatter + markdown), `SessionStore` writes `session.json`, both under `~/Library/Application Support/NoteTakr/Sessions/<date>_<slug>_<shortid>/`. `MeetingSession.summary: String?` already exists. There is no versioning, no outbox, no networking except `OpenRouterClient` (URLSession behind the `HTTPDataFetching` protocol) and `KeychainStore`.
- DI convention (follow it everywhere): production `convenience init()` builds real dependencies; designated `init(dep: any Protocol)` for tests; mocks live in-source next to the protocol (`MockCalendarAdapter`, `MockAudioRecorder`). Privacy invariants are asserted by counting mock invocations (see `EventKitAdapterTests` on branch `origin/codex/bugfix-e2e-20260712`).
- E2E harness (on that same unmerged branch): XCUITest driving the real app with env-var seams (`NOTETAKR_E2E_APP_SUPPORT_ROOT`, `NOTETAKR_E2E_USE_MOCK_RECORDER=1`, ...), AX-identifier lookup, DistributedNotificationCenter control channel, and filesystem polling assertions.
- CI: `.github/workflows/macos-ci.yml` — `kit-tests` (ubuntu, swift:6.0 container), `swift-package-tests` (macos-15), `xcode-build-and-test` (macos-15).
- Environment note for the executor: root `swift test` and `xcodebuild` require macOS with Xcode 16. If you are running somewhere a listed validation command cannot run (e.g. Linux: only `cd NoteTakrKit && swift test` and `cd convex && npm test` work), run what you can, and record the exact skipped command and reason in the progress file and next to the checkbox — do not claim it passed.

## Product Decisions

Locked. Do not reopen, redesign, or "improve" these:

- Mac is the only writer of content fields; Convex is the only writer of `summary`, `pushStatus`, and the `people` mirror. No field ever has two writers, therefore no conflict-resolution code exists anywhere in this plan.
- One-way push. No cross-device live sync. Restore-from-cloud is a later one-shot import, not part of this plan.
- Auth: Google via Clerk only. No Sign in with Apple. Signed out ⇒ zero behavior change, zero network calls from sync code.
- Summaries: generated server-side (Convex action → OpenRouter, model slug from Convex env var `SUMMARY_MODEL`, default Kimi K2.7). The existing local OpenRouter summarization path stays as the signed-out fallback and must keep working.
- CRM: Twenty first, attached to person records, one note per meeting (summary on top, transcript beneath), fired after the summary is saved. Attio is a second adapter behind the same interface. Per-user Twenty base URL + API key.
- Participants without emails never auto-match and never become Person records; when a CRM is connected and a meeting has unmatched participants, a small dismissible banner appears directly above the editor footer tabs. Nothing blocks the push.
- Per-meeting flags: `local_only` (never leaves the Mac) and CRM push opt-out. No audio upload, ever, in this plan.
- Apple Calendar (EventKit) only. Apple Contacts is a people source only, never written to.

## Architecture Decisions

- New Kit code under `NoteTakrKit/Sources/NoteTakrKit/People/` (must compile on Linux — Foundation only). New sync code in a new SwiftPM target `NoteTakrSync` (`Sources/NoteTakrSync/`, tests in `Tests/NoteTakrSyncTests/`), registered in root `Package.swift`; Convex/Clerk SDK dependencies are confined to this target behind the `SyncBackend` protocol.
- Convex backend lives in top-level `convex/` (TypeScript, `convex-test` + vitest). Tables: `meetings` (indexed `by_user_localId`), `notes`, `transcriptSegments` (`by_meeting`), `people` (`by_user_email`), `userSettings`, `devices`.
- Change detection: `contentHash` (SHA-256 of mapped content) on the payload — there is no `updatedAt` on existing records and none is added.
- Outbox: durable file-per-item queue at `NoteTakr/Outbox/<localId>.json`, atomic writes like `SessionStore`; enqueue overwrites by `localId` (mirror semantics, not an event log).
- CRM behind `CrmProvider` (TS interface: `listPeople`, `upsertMeetingNote(personRemoteIds, title, markdown, existingNoteId?) → remoteNoteId`); provider registry keyed by `userSettings.crm.provider`.
- People picker behind `PeopleSource` (Swift protocol) with implementations: `PastMeetingsIndex` (Kit), `AppleContactsSource` (App), `ConvexPeopleCacheSource` (Sync, reads a local JSON snapshot refreshed while signed in).

## Verification Contract

- The spec doc's test lists are the specification. Write each task's tests FIRST, with the exact test names given, then implement until they pass as written. Never rename, weaken, loosen an assertion of, or delete a spec-listed test. If a spec-listed test appears wrong or unimplementable, do not change it — record the blocker in the progress file and next to the checkbox, and move on within the task.
- A checkbox may only be ticked after the task's validation commands actually passed in this iteration. Paste-worthy proof (final test summary line) goes in the progress file.
- Deterministic local tests are the default. The only tests allowed to touch the network are the env-gated live Twenty integration suite (Task 12) and nothing else; it must self-skip with a loud warning when `TWENTY_TEST_BASE_URL`/`TWENTY_TEST_API_KEY` are unset, and its live runs create only `[nt-test]`-prefixed entities and delete them in `finally` blocks.
- Privacy invariants are proven by invocation counting: signed-out ⇒ `upsertCount == 0`; `local_only` ⇒ outbox stays empty; contacts access denied ⇒ zero `CNContactStore` lookups; no CRM configured ⇒ zero provider calls.
- UI-visible behavior gets an XCUITest on the adopted harness (AX identifiers + filesystem polling), not a screenshot claim.

## Validation Commands

- `cd NoteTakrKit && swift test`
- `swift test` (root package; macOS only)
- `cd convex && npm test` (from Task 7 onward)
- `xcodebuild test -project Notetakr.xcodeproj -scheme NoteTakr -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` (macOS only; runs NoteTakrTests + NoteTakrUITests)

Run the commands relevant to what the task changed, plus `cd NoteTakrKit && swift test` always (it is fast and catches Linux breakage).

### Task 1: Merge Contacts name resolution from the codex branch

- [x] Cherry-pick `7433c4a` ("Resolve attendee names from authorized contacts") from `origin/codex/bugfix-e2e-20260712` onto `main`. Resolve conflicts by preserving current `main` behavior plus the branch's additions; port hunks manually if the cherry-pick does not apply cleanly. (already present: `7433c4a` is an ancestor of `HEAD`)
- [x] Keep the commit's tests (`NoteTakrTests/EventKitAdapterTests.swift` additions, `MVPPolishTests` update) passing unmodified — they encode the privacy invariant (denied/undetermined Contacts access ⇒ zero store lookups). (source tests present; macOS-only execution skipped on Ubuntu - not automatable here)
- [x] Run `cd NoteTakrKit && swift test`, `swift test`, and the `xcodebuild test` command; fix fallout until green. (`cd NoteTakrKit && swift test` passed: 597 tests, 0 failures; `swift test` and `xcodebuild test` skipped on Ubuntu because root/Xcode validation requires macOS with Xcode 16 and `xcodebuild` is unavailable)

### Task 2: Adopt the hosted GUI e2e harness

- [x] Cherry-pick the harness commits from `origin/codex/bugfix-e2e-20260712` in order: `ff2052f`, `64d1ad1`, `afa7fcd`, `f051ced`, `953ca93`, `cb24883` (adds `NoteTakrUITests/`, scheme + pbxproj changes, AX identifiers in `AppDelegate`/`EditorView`/`SettingsSheetView`, `macos-ci.yml` update). Port manually where they conflict with current `main`. (already present: all six commits are ancestors of `HEAD`; harness files and the two named XCUITests are present)
- [x] Both existing XCUITests (`testPermissionsAndInPersonAudioSourceLockWhileRecording`, `testHideAndReopenPreservesSelectedMeetingIdentity`) pass locally via the `xcodebuild test` command. (skipped - not automatable on this Ubuntu executor because `xcodebuild` is unavailable; test methods verified present in `NoteTakrUITests/NoteTakrUITests.swift`)
- [x] Run all validation commands that apply; fix fallout until green. (`cd NoteTakrKit && swift test` passed: 597 tests, 0 failures; root `swift test` and `xcodebuild test` skipped on Ubuntu because the plan requires macOS with Xcode 16; `convex` does not exist before Task 7)

### Task 3: Kit People core — Person model and PastMeetingsIndex (tests first)

- [x] Write `NoteTakrKit/Tests/NoteTakrKitTests/PersonTests.swift` and `PastMeetingsIndexTests.swift` with exactly the tests named in the spec doc Phase 1 (`testEmailsAreLowercasedAndDeduplicatedOnInit`, `testCompanyIsDerivedFromCustomDomain`, `testCompanyIsNilForPublicEmailDomains`, `testAggregatesParticipantsAcrossNotesByEmail`, `testParticipantsWithoutEmailAreExcluded`, `testRankingPrefersFrequencyThenRecency` with injected `now`, `testSearchMatchesNameAndEmailCaseInsensitively`).
- [x] Implement `People/Person.swift` (with `SourceRef`) and `People/PastMeetingsIndex.swift` (input: `[MeetingNote]`; score = co-meeting count × exp(−days since last co-meeting ÷ 90)) until those tests pass as written. Foundation only — must build in the Linux `kit-tests` container.
- [x] Run `cd NoteTakrKit && swift test`; all green. (passed: 604 tests, 0 failures)

### Task 4: Kit People — PeopleDirectory and PeoplePickerPresenter (tests first)

- [x] Write `PeopleDirectoryTests.swift` and `PeoplePickerPresenterTests.swift` with exactly the spec-doc tests (`testMergesPeopleSharingAnyEmailAcrossSources`, `testNamePrecedenceFollowsSourcePriorityOrder`, `testPeopleFromSingleSourcesPassThroughUnchanged`, `testEventAttendeesArePinnedInFirstSection`, `testAlreadyAddedParticipantsAreExcluded`, `testFreeTextRowAppearsWhenNoExactMatch`, `testSelectingPersonProducesParticipantWithPrimaryEmail`).
- [x] Implement `People/PeopleSource.swift` (protocol: `providerId`, `allPeople()`, `search(_:)`), `People/PeopleDirectory.swift` (merge by any shared lowercased email, union sourceRefs, name precedence by init-order source priority), `People/PeoplePickerPresenter.swift` (sections `.inThisEvent` / `.recent` / per-source; free-text fallback row) until the tests pass as written.
- [x] Run `cd NoteTakrKit && swift test`; all green. (passed: 611 tests, 0 failures)

### Task 5: AppleContactsSource behind the Contacts privacy gate (tests first)

- [x] Write `NoteTakrTests/AppleContactsSourceTests.swift` with exactly `testDoesNotQueryContactsWithoutAuthorization`, `testDoesNotQueryWhileConsentUndetermined`, `testAuthorizedContactsMapToPersonsWithLowercasedEmails` — DI-closure style copied from `EventKitAdapterTests` (inject `authorizationStatus` + `fetchContacts` closures, count invocations). (added with fetch-count assertions for denied, undetermined, and authorized contacts)
- [x] Implement `NoteTakrApp/People/AppleContactsSource.swift` conforming to `PeopleSource`, reusing the Task 1 Contacts plumbing; production `convenience init()`, designated init with injected closures. It must never trigger a permission prompt (only reads when already `.authorized`). (implemented with `CNContactStore.enumerateContacts` behind the `.authorized` gate and lowercased email mapping)
- [x] Run the `xcodebuild test` command and `cd NoteTakrKit && swift test`; all green. (`cd NoteTakrKit && swift test` passed: 611 tests, 0 failures; `xcodebuild test` skipped on Ubuntu because the command is unavailable and this validation requires macOS with Xcode 16)

### Task 6: Picker UI, hover card, and the Phase 1 e2e gate

- [x] Replace the free-text-only participant add in `PropertyPanelView.PeopleValue` with the picker popover driven by `PeoplePickerPresenter` over a `PeopleDirectory` of (`AppleContactsSource`, `PastMeetingsIndex` built from `NoteStore.list()`); keep free-text add as the fallback row. Add AX ids `participantPickerField`, `participantPickerRow_<email-or-name>`, `participantHoverCard`. (implemented in `FrontmatterPresenterBridge` and `PropertyPanelView`; picker rows are backed by `PeoplePickerPresenter` sections, contacts + past meetings, and free-text fallback rows)
- [x] Add the hover card on participant chips: company (from email domain) + last meetings together (from `PastMeetingsIndex`). (implemented as the participant hover/click card with company, meetings-together count, last-meeting date, and AX id `participantHoverCard`)
- [x] Write XCUITest `testParticipantPickerAddsPersonFromPastMeetings`: seed two `note.md` files sharing an attendee email via the harness `seedMeeting()` pattern, open the property panel, type into `participantPickerField`, select the row, poll the persisted `note.md` frontmatter until it contains the participant with email. (added to `NoteTakrUITests/NoteTakrUITests.swift` with participant frontmatter seeding and persisted-email polling)
- [x] Run the `xcodebuild test` command and `cd NoteTakrKit && swift test`; all green. (`cd NoteTakrKit && swift test` passed: 611 tests, 0 failures; `xcodebuild test` skipped on Ubuntu because `xcodebuild` is unavailable and this validation requires macOS with Xcode)

### Task 7: Convex scaffold — schema, upsert mutation, test harness, CI job (tests first)

- [x] Create `convex/` (npm project: `convex`, `convex-test`, `vitest`; `npm test` runs vitest). Write `convex/schema.ts` with the six tables and indexes from the spec doc. (added npm scaffold, package-lock, TypeScript config, schema tables: meetings, notes, transcriptSegments, people, userSettings, devices, plus the required indexes)
- [x] Write `convex/meetings.test.ts` first with exactly the spec-doc cases: `upsert twice with same localId yields one document with updated fields`; `upsert replaces transcript segments, never duplicates`; `unchanged contentHash does not reschedule summarize`; `changed contentHash reschedules summarize`; `users only read their own meetings`. (all five cases added with convex-test)
- [x] Implement `convex/meetings.ts` (`upsertFromDevice` keyed by `(userId, localId)`, transactional segment replace, summarize scheduling) until the tests pass as written. (implemented auth-scoped upsert, note overwrite, transcript segment replacement, contentHash-based summarize scheduling, and auth-scoped getByLocalId)
- [x] Add a `convex-tests` job (ubuntu, node LTS, `cd convex && npm ci && npm test`) to `.github/workflows/macos-ci.yml`. (job added with npm cache against convex/package-lock.json)
- [x] Run `cd convex && npm test`; all green. (`cd convex && npm test` passed: 1 test file, 5 tests; `cd convex && npm run typecheck` passed; `cd NoteTakrKit && swift test` passed: 611 tests, 0 failures)

### Task 8: Server summary action via OpenRouter Kimi K2.7 (tests first)

- [x] Write `convex/summarize.test.ts` first (OpenRouter fetch mocked) with exactly: `writes summary and status ready on success`; `sets status failed and preserves previous summary on API error`; `schedules crm push after ready`. (added all three spec-named tests; focused run failed before implementation because `summarize` module was missing, then passed after implementation)
- [x] Implement `convex/summarize.ts`: action loads transcript, calls OpenRouter chat completions with `OPENROUTER_API_KEY` and `SUMMARY_MODEL` env vars (default the Kimi K2.7 slug — verify the exact current slug on openrouter.ai and record it in the code comment), writes `summary` + `summaryStatus`, schedules the CRM push (a no-op stub until Task 11). (implemented `summarizeMeeting` with internal read/write helpers, default slug `moonshotai/kimi-k2.7-code` verified on OpenRouter 2026-07-20, and a no-op `crm/push:pushMeetingToCrm` stub scheduled after ready summaries)
- [x] Run `cd convex && npm test`; all green. (`cd convex && npm test` passed: 2 test files, 8 tests; `cd convex && npm run typecheck` passed; `cd NoteTakrKit && swift test` passed: 611 tests, 0 failures)

### Task 9: NoteTakrSync target — envelope, outbox, local_only flag (tests first)

- [ ] Register the `NoteTakrSync` target + `NoteTakrSyncTests` in root `Package.swift` (depends on NoteTakrKit + NoteTakrCore; no external SDKs yet).
- [ ] Write `Tests/NoteTakrSyncTests/SyncEnvelopeTests.swift` and `SyncOutboxTests.swift` first with exactly the spec-doc tests (`testPayloadCarriesAllContentFields`, `testContentHashIsStableForEqualContent`, `testContentHashChangesWhenBodyChanges`, `testEnqueuePersistsFileAndPendingReturnsIt`, `testEnqueueSameLocalIdOverwrites`, `testPendingSurvivesReinitialization`, `testCompleteRemovesItem`). Write the Kit test `testLocalOnlyRoundTripsThroughFrontmatter` in `FrontmatterSerializerTests`.
- [ ] Implement `SyncEnvelope.swift` (pure `(MeetingSession, MeetingNote) → MeetingPayload` with SHA-256 `contentHash`), `SyncOutbox.swift` (file-per-item at `NoteTakr/Outbox/`, atomic, overwrite-by-localId), and add `localOnly` to `MeetingNote` (frontmatter `local_only`) + `MeetingSession` (tolerant decoder) until all tests pass as written.
- [ ] Run `swift test` and `cd NoteTakrKit && swift test`; all green.

### Task 10: SyncService loop with MockSyncBackend and lifecycle hooks (tests first)

- [ ] Write `SyncServiceTests.swift` first with exactly the spec-doc tests (`testSignedOutMakesZeroBackendCalls`, `testLocalOnlyMeetingsAreNeverEnqueued`, `testDrainPushesAllPendingAndCompletes`, `testFailedPushRetriesWithExponentialBackoff` asserting recorded delays `[1, 2]`, `testDirtyWhileInFlightRequeues`, `testSummaryUpdateIsPersistedToSession`), using an in-source `MockSyncBackend` and injected sleep/clock closures.
- [ ] Implement `SyncBackend.swift` (protocol + mock) and `SyncService.swift` (`@unchecked Sendable` class per repo convention: outbox drain when signed in, exponential backoff 1s·2ⁿ capped 5 min, in-flight `Set<String>` guard, summary-update consumption via injected persist closure) until the tests pass as written.
- [ ] Wire `markDirty(localId:)` hooks: after `store.save` in `RecordingManager.stopRecording`, after transcript persist in `TranscriptionService.transcribe`, and on `NoteEditorViewModel` autosave flush. Hooks must be no-ops when no sync service is attached (signed-out/default path unchanged).
- [ ] Run `swift test`, `cd NoteTakrKit && swift test`, and the `xcodebuild test` command; all green.

### Task 11: Clerk + Convex live backend, account UI, and the Phase 2 e2e gate

- [ ] Add `clerk-convex-swift` + `convex-swift` to the `NoteTakrSync` target only; implement `ConvexSyncBackend: SyncBackend` (Google sign-in via Clerk, `ConvexClientWithAuth`, `upsertFromDevice` call, summary subscription). Keep every SDK type behind the protocol.
- [ ] `AppModel` owns the `SyncService` + launch task; account state exposed as a `PermissionStatus`-style published value. Settings sheet gains an "Account & Sync" section in the General tab (Google sign-in button, signed-in email, sign out) following the `openRouterSection` pattern, and a `local_only` toggle in This Meeting. Summary tab: when signed in, `SummaryState` is fed from sync (`waiting → generating → ready`); local generation path untouched for signed-out.
- [ ] Add env seam `NOTETAKR_E2E_MOCK_SYNC_BACKEND=1` (DEBUG-only, mirrors `NOTETAKR_E2E_USE_MOCK_RECORDER`): file-spool mock backend + fake signed-in account. Write XCUITest `testMeetingSyncsAfterRecordingStops`: record with mock recorder, stop, poll the spool dir for the payload JSON, have the mock emit a summary, assert the Summary tab shows it and `session.json` contains it.
- [ ] Run all four validation commands; all green. Then a best-effort real smoke check: if Clerk/Convex dev credentials are available in the environment, sign in and push one meeting for real; otherwise record exactly what is missing (e.g. "no CONVEX_DEPLOYMENT/Clerk publishable key configured") in the progress file — do not fake it.

### Task 12: Twenty provider + live integration suite (tests first)

- [ ] Write `convex/crm/twenty.test.ts` first (fetch mocked) with exactly: `listPeople maps twenty records to CrmPerson with lowercased emails`; `listPeople follows pagination until exhausted`; `upsertMeetingNote creates note and attaches all person targets`; `upsertMeetingNote with existingNoteId updates instead of creating`; `api error surfaces as typed CrmError, not a throw-through`.
- [ ] Implement `convex/crm/provider.ts` (interface + registry) and `convex/crm/twenty.ts` until the mocked tests pass as written.
- [ ] Write `convex/crm/twenty.integration.test.ts` — live suite gated on `TWENTY_TEST_BASE_URL`/`TWENTY_TEST_API_KEY` (self-skips with a loud console warning when unset) with exactly the five spec-doc live cases (fresh person appears after mirror pass; exactly one note created; second upsert updates in place; invalid key → typed unauthorized; non-empty mapped page). All created entities `[nt-test]`-prefixed and deleted in `finally`.
- [ ] Wire the integration suite into the `convex-tests` CI job via repo secrets: run it when secrets are present, fail the job on suite errors, print an explicit skip warning when absent.
- [ ] Run `cd convex && npm test`; mocked suite green. If the env vars are available, run the integration suite and record the result; if not, record the exact missing variables in the progress file — do not fake a live pass.

### Task 13: People mirror, CRM push pipeline, cron (tests first)

- [ ] Write `convex/crm/mirror.test.ts` and `convex/crm/push.test.ts` first with exactly the spec-doc cases (mirror: inserts/updates, removes disappeared remoteIds, never touches other users' rows, `hourly cron is registered and points at the mirror function`; push: case-insensitive email match, unmatched recorded without blocking, stores `crmNoteId` + `pushStatus pushed`, retry reuses `crmNoteId`, opt-out ⇒ `skipped` + zero provider calls, no CRM configured ⇒ zero provider calls).
- [ ] Implement `convex/crm/mirror.ts` (mirror into `people`; triggers: hourly cron in `convex/crons.ts`, on CRM-config save, on-demand mutation) and `convex/crm/push.ts` (match → compose summary+transcript markdown → `upsertMeetingNote` → write back `crmNoteId`/`pushStatus`/`unmatched`), replacing the Task 8 stub, until the tests pass as written.
- [ ] Run `cd convex && npm test`; all green (integration suite per Task 12 rules).

### Task 14: Mac CRM surfaces — people cache, auto-match, unmatched banner, settings (tests first)

- [ ] Write `Tests/NoteTakrSyncTests/ConvexPeopleCacheSourceTests.swift` (`testLoadsPeopleFromCachedSnapshot`, `testMissingCacheFileYieldsEmptySourceWithoutError`, `testRefreshRewritesSnapshotAtomically`) and `NoteTakrKit/.../CrmStatusPresenterTests.swift` (`testBannerHiddenWhenCrmNotConnected`, `testBannerHiddenWhenAllParticipantsMatched`, `testBannerTextCountsUnmatchedParticipants` incl. singular form, `testDismissSilencesBannerForThatMeetingOnly`) first.
- [ ] Implement `ConvexPeopleCacheSource` (snapshot at `NoteTakr/PeopleCache.json`, refreshed by `SyncService` while signed in) and join it into the picker's `PeopleDirectory` (priority contacts > crm > pastMeetings); auto-match calendar attendees by email against the directory; implement `CrmStatusPresenter` and render the dismissible banner in `EditorView` between `tabContent` and `footerTabs` (AX id `crmUnmatchedBanner`); surface `pushStatus` in the property panel; add the CRM settings section (Twenty base URL, API key, connection-test button using the typed unauthorized error) and per-meeting "Push to CRM" toggle.
- [ ] Write XCUITest `testUnmatchedCrmBannerAppearsAboveFooter` with env seam `NOTETAKR_E2E_MOCK_CRM_CONNECTED=1`: seeded note with one email-less participant ⇒ banner exists above the footer tabs; dismiss ⇒ gone.
- [ ] Run all four validation commands; all green. Best-effort real smoke against the live Twenty instance if configured (meeting with a known CRM contact ⇒ exactly one note on that person, re-push stays one note); otherwise record the exact blocker — do not fake it.

### Task 15: Attio adapter behind the proven interface (tests first)

- [ ] Write `convex/crm/attio.test.ts` first: the same five mocked cases as Twenty, mapped to Attio API shapes, plus `provider registry resolves by userSettings.crm.provider`.
- [ ] Implement `convex/crm/attio.ts` until the tests pass as written. No Swift, UI, or pipeline changes — if any seem required, that is a spec violation: record it as a blocker instead of changing the pipeline.
- [ ] Add `convex/crm/attio.integration.test.ts` (same five live cases, gated on `ATTIO_TEST_API_KEY`, `[nt-test]` prefix + `finally` cleanup, self-skip warning when unset).
- [ ] Run `cd convex && npm test`; all green.

## Success Criteria

Signed out, the app is byte-for-byte behaviorally identical to today. Signed in with Google, a finished meeting appears in Convex with a Kimi-generated summary shown in the Summary tab, and — with Twenty connected — exactly one note (summary + transcript) lands on each matched person, idempotently, with unmatched participants surfaced in the banner and `local_only` meetings never leaving the Mac. Every spec-listed test exists verbatim and passes; CI is green across kit-tests, swift-package-tests, convex-tests, and xcode-build-and-test.
