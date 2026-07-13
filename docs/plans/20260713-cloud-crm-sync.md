# Cloud Sync, Server Summaries & CRM Push — Solidified Implementation Plan

Date: 2026-07-13 · Status: **ready to implement** · Condensed visual version: `20260713-cloud-crm-sync.html`

Stack: Swift/macOS (this repo) · Clerk (Google OAuth) · Convex (backend, TypeScript in new top-level `convex/`) · OpenRouter **Kimi K2.7** (summaries, server-side) · Twenty CRM first (self-hosted, publicly reachable), Attio second.

---

## 0. Locked decisions

| Decision | Detail |
|---|---|
| Write ownership is partitioned | Mac owns content (title, body, participants, transcript). Convex owns `summary`, `pushStatus`, `people` mirror. No field has two writers → **no conflict resolution anywhere**. |
| One-way push + narrow pull | Mac pushes content up. The only downstream data: server-generated `summary` and `pushStatus`/people cache. Cross-device sync: deliberately out of scope. |
| Auth | Google via Clerk (`clerk-convex-swift`). Signed out ⇒ app behaves exactly as today ("no cloud, no account" stays true). No Sign in with Apple (no paid Apple Developer membership needed for any phase). |
| Summaries | Server-side Convex action → OpenRouter, model **Kimi K2.7** (slug in a Convex env var, e.g. `moonshotai/kimi-k2.7` — confirm exact slug at implementation time). Existing local `SummarizationService` path (`Sources/NoteTakrCore/Summarization/`) is kept as the signed-out fallback; when signed in, generation moves server-side and the Summary tab reflects `waiting → generating → ready`. |
| CRM | Twenty first (per-user base URL + API key, instance is publicly reachable so Convex actions can call it; no relevant note-body limit). Attio is a second adapter behind the same interface. Notes attach to **person** records. CRM push fires after the summary is saved. |
| Calendar | Apple Calendar (EventKit) only — already the case. |
| Missing attendee emails | Accepted as-is. When a CRM is connected and a meeting has unmatched participants, show a small quiet warning banner directly above the editor footer tab bar. Nothing blocks the push. |
| Contacts | Apple Contacts is a **PeopleSource only** (never written to) — the easy first source that proves the abstraction before the CRM mirror lands. |
| Privacy flags | Per-meeting `local_only` (never leaves the Mac) and `crm_push` opt-out (syncs, but no CRM note). No audio upload in any phase. |
| Methodology | **TDD.** Each phase lists its unit tests up front — file, test name, exact expected behavior. Tests are the spec: implement until the listed tests pass **as written**; do not rename, weaken, or delete them. Each phase ends with an e2e gate before the next phase starts. |

### Testing ground rules (apply to every phase)

- XCTest only (repo has zero swift-testing). Naming: `final class XxxTests: XCTestCase`, `func testCamelCaseBehavior()`.
- DI convention (the `ContactNameResolver` pattern from `7433c4a`): production `convenience init()` builds real dependencies; designated `init(dep: any Protocol)` for tests. Mocks live in-source next to the protocol (like `MockCalendarAdapter`).
- Pure logic goes in **NoteTakrKit** (runs on Linux CI, `kit-tests` job) whenever it doesn't need Core types. Networking/store logic goes in the new **NoteTakrSync** target with macOS `swift test`. App-glue tests go in `NoteTakrTests` (xcodebuild).
- Convex functions are unit-tested with `convex-test` + vitest in `convex/` (new `npm test` step; add a `convex-tests` job to `.github/workflows/macos-ci.yml` running on ubuntu).
- Privacy invariants are tested by **counting mock invocations** (the `lookupCount == 0` style from `EventKitAdapterTests`): signed-out ⇒ zero network calls; `local_only` ⇒ zero enqueues; CRM disconnected ⇒ zero CRM calls.
- **Live integration tests** (real Twenty instance, real API key) complement the mocked unit tests wherever an external API is adapted. They live in `*.integration.test.ts`, are gated on `TWENTY_TEST_BASE_URL` + `TWENTY_TEST_API_KEY` env vars (suite self-skips with a loud console warning when unset), run via `npm run test:integration`, and in CI via repo secrets. Every entity they create is prefixed `[nt-test]` and deleted in `finally` blocks. **A phase whose scope includes a live API does not pass its exit gate until its integration suite has run green against the real instance** — mocked-green alone is not done.
- E2E gates use the XCUITest harness (env-var seams `NOTETAKR_E2E_*`, AX identifiers, filesystem assertions) adopted in Phase 0, plus new rows in `docs/manual-smoke-test.md` for what CI genuinely cannot verify.

---

## Phase 0 — Groundwork: merge the unmerged branch work

Cherry-pick from `origin/codex/bugfix-e2e-20260712` onto `main`:

1. `7433c4a` — Contacts attendee-name resolution (`ContactNameResolving`, permission rows, Info.plist/entitlements) **including its tests** (`EventKitAdapterTests` additions, `MVPPolishTests` update).
2. The hosted GUI e2e harness (`ff2052f`, `64d1ad1`, `afa7fcd`, `f051ced`, `953ca93`, `cb24883`): `NoteTakrUITests/`, scheme + pbxproj changes, `AppDelegate`/`EditorView`/`SettingsSheetView` AX identifiers, `macos-ci.yml` update.

**Exit gate:** existing CI (kit-tests, swift-package-tests, xcode-build-and-test incl. the two adopted XCUITests) green on main. No new tests to write — this phase *is* adopting tests.

---

## Phase 1 — People: local directory + picker (no cloud, no account)

### New code

- `NoteTakrKit/Sources/NoteTakrKit/People/Person.swift` — `struct Person: Equatable, Sendable { name, emails: [String] (lowercased), company: String?, sourceRefs: [SourceRef] }`; `SourceRef = { provider: String, remoteId: String }`. `company` derived from first email's domain (strip common public domains → nil).
- `People/PeopleSource.swift` — `protocol PeopleSource { var providerId: String { get }; func allPeople() -> [Person]; func search(_ query: String) -> [Person] }`.
- `People/PastMeetingsIndex.swift` — `PeopleSource` built from `[MeetingNote]` (injected, not from disk): aggregates participants with email; score = co-meeting count × exp(-days since last meeting / 90).
- `People/PeopleDirectory.swift` — merges N sources, dedupes by any shared lowercased email, unions `sourceRefs`, name precedence by source priority order given at init (contacts > pastMeetings > derived-from-email).
- `People/PeoplePickerPresenter.swift` — drives the picker UI: sections `[.inThisEvent, .recent, .contacts]`, event attendees pinned first, query filtering (name/email prefix, case/diacritic-insensitive), final free-text row when query matches nothing exactly.
- App: `NoteTakrApp/People/AppleContactsSource.swift` — `PeopleSource` over `CNContactStore`, gated exactly like `ContactNameResolver` (never queries unless `.authorized`; designated init takes `authorizationStatus` + `fetchContacts` closures). Grows out of, and reuses, the `7433c4a` plumbing.
- App UI: picker popover replacing the free-text `TextField` flow in `PropertyPanelView.PeopleValue` (keeps free-text as the fallback row); hover card (company + last N meetings from `PastMeetingsIndex`). New AX ids: `participantPickerField`, `participantPickerRow_<email-or-name>`, `participantHoverCard`.

### Tests (write first; these are the spec)

`NoteTakrKit/Tests/NoteTakrKitTests/PersonTests.swift`
- `testEmailsAreLowercasedAndDeduplicatedOnInit` — init with `["A@x.com", "a@x.com"]` → `emails == ["a@x.com"]`.
- `testCompanyIsDerivedFromCustomDomain` — `sarah@acme.com` → `company == "Acme"` (capitalized second-level label).
- `testCompanyIsNilForPublicEmailDomains` — `gmail.com`, `icloud.com`, `outlook.com` → `company == nil`.

`PastMeetingsIndexTests.swift`
- `testAggregatesParticipantsAcrossNotesByEmail` — 3 notes, `a@x.com` in 2 of them (once as "Ada", once as "Ada L.") → one Person, 2 co-meetings counted.
- `testParticipantsWithoutEmailAreExcluded` — note with `Participant(name: "Tom", email: nil)` → `allPeople()` contains no "Tom" (free-text never becomes a Person).
- `testRankingPrefersFrequencyThenRecency` — fixed `now` injected; A: 3 meetings 60 days ago, B: 1 meeting yesterday, C: 3 meetings yesterday → order C, A, B.
- `testSearchMatchesNameAndEmailCaseInsensitively` — query `"ada"` matches "Ada Lovelace" and `ada@x.com`; query `"ADA"` identical result.

`PeopleDirectoryTests.swift`
- `testMergesPeopleSharingAnyEmailAcrossSources` — contacts source has `{Ada, [a@x.com]}`, pastMeetings has `{Ada L., [a@x.com, ada@y.com]}` → one Person with both emails and both sourceRefs.
- `testNamePrecedenceFollowsSourcePriorityOrder` — same person in contacts ("Ada Lovelace") and pastMeetings ("a@x.com"-derived) → name is "Ada Lovelace".
- `testPeopleFromSingleSourcesPassThroughUnchanged` — disjoint people from two sources → both present, untouched.

`PeoplePickerPresenterTests.swift`
- `testEventAttendeesArePinnedInFirstSection` — attendees of the linked event appear under `.inThisEvent` regardless of ranking.
- `testAlreadyAddedParticipantsAreExcluded` — a person already on the note never appears in results.
- `testFreeTextRowAppearsWhenNoExactMatch` — query "Zzz" → last row is `.freeText("Zzz")`; selecting it produces `Participant(name: "Zzz", email: nil)`.
- `testSelectingPersonProducesParticipantWithPrimaryEmail` — picking merged Ada → `Participant(name: "Ada Lovelace", email: "a@x.com")`.

`NoteTakrTests/AppleContactsSourceTests.swift` (macOS, DI closures — mirror `EventKitAdapterTests`)
- `testDoesNotQueryContactsWithoutAuthorization` — status `.denied` → `fetchCount == 0`, `allPeople() == []`.
- `testDoesNotQueryWhileConsentUndetermined` — `.notDetermined` → `fetchCount == 0`.
- `testAuthorizedContactsMapToPersonsWithLowercasedEmails` — one CNContact fixture ("Grace Hopper", `Grace@Navy.mil`) → `Person(name: "Grace Hopper", emails: ["grace@navy.mil"])`, `fetchCount == 1`.

### Exit gate (e2e)

- All tests above green in CI (Kit tests on the Linux job).
- New XCUITest `testParticipantPickerAddsPersonFromPastMeetings`: seed two `note.md` files sharing an attendee email (`seedMeeting()` helper), open the second note's property panel, type the attendee's first name in `participantPickerField`, assert `participantPickerRow_*` appears, select it, then assert the persisted `note.md` frontmatter gains the participant **with email** (filesystem poll, like `waitForPersistedInPersonFrontmatter`).
- Manual smoke addition: grant Contacts permission → picker shows a real contact under "Contacts".

---

## Phase 2 — Sync spine: Clerk + Convex + outbox + server summaries

### New code — Swift

- New SwiftPM target **`NoteTakrSync`** (`Sources/NoteTakrSync/`, registered in root `Package.swift`, test target `Tests/NoteTakrSyncTests/`; depends on NoteTakrKit + NoteTakrCore). Convex/Clerk SDK dependencies live **only** here; everything the app touches goes through protocols so Kit/Core stay dependency-free.
  - `SyncEnvelope.swift` — pure mapping `(MeetingSession, MeetingNote) → MeetingPayload` (`localId` = session UUID string; title, startedAt, calendarEventId, participants `{name, email?}`, markdownBody, transcript segments `{seq, startMs, speaker?, text}`, `contentHash` = SHA-256 over the mapped content for change detection — replaces the missing `updatedAt`).
  - `SyncOutbox.swift` — durable file-per-item queue at `NoteTakr/Outbox/<localId>.json` (same atomic-write conventions as `SessionStore`). Enqueue overwrites by `localId` (latest state wins — it's a mirror, not an event log). `pending()` sorted by enqueue time; `complete(localId:)` deletes the file.
  - `SyncBackend.swift` — `protocol SyncBackend: Sendable { func upsertMeeting(_ p: MeetingPayload) async throws; func summaryUpdates() -> AsyncStream<SummaryUpdate>; var accountState: AccountState { get } }` + `MockSyncBackend` in-source. `ConvexSyncBackend` implements it with `ConvexClientWithAuth` + `ClerkConvexAuthProvider`.
  - `SyncService.swift` — `final class SyncService: @unchecked Sendable` (repo convention; no actors): owns the outbox, drains it when signed in, exponential backoff on failure (1s·2ⁿ capped 5min, injected `sleep` closure), in-flight guard `Set<String>` like `transcribingIDs`. Consumes `summaryUpdates()` and writes `session.summary` via an injected persist closure.
- Model additions: `MeetingNote.localOnly: Bool?` (frontmatter key `local_only`) + `MeetingSession.localOnly: Bool?` (tolerant decoder, same as existing optional fields). Sync trigger hooks: after `store.save` in `RecordingManager.stopRecording`, after transcription persist in `TranscriptionService.transcribe`, and on editor autosave flush (`NoteEditorViewModel` dirty-flush) — each just calls `syncService.markDirty(localId)`.
- App glue: `AppModel` owns `syncService` + a launch `Task` running its loop; account state exposed as a `PermissionStatus`-style published value; Settings gets an **Account & Sync** section in `SettingsSheetView.generalContent` (pattern: `openRouterSection`) — Google sign-in button (Clerk), signed-in email, "local only by default" toggle; **This Meeting** tab gets the `local_only` toggle. Summary tab states already exist (`SummaryState`); signed-in flow feeds `.generating`/`.ready` from sync instead of the local adapter.

### New code — Convex (`convex/`, TypeScript)

- `schema.ts` — tables exactly as in the HTML plan: `meetings` (indexed `by_user_localId`), `notes`, `transcriptSegments` (indexed `by_meeting`), `people` (indexed `by_user_email`), `userSettings` (OpenRouter key optional override, CRM config placeholder), `devices`.
- `meetings.ts` — `upsertFromDevice` mutation: upsert by `(userId, localId)`; replaces transcript segments transactionally; skips summary regeneration when `contentHash` unchanged; schedules `summarize` action when transcript present and summary missing/stale.
- `summarize.ts` — action: loads transcript, calls OpenRouter (`OPENROUTER_API_KEY` env, model env `SUMMARY_MODEL`, default Kimi K2.7 slug), writes `summary`, sets `summaryStatus: ready|failed`, then schedules the CRM push (Phase 3 no-ops until a CRM is configured).

### Tests (write first)

`Tests/NoteTakrSyncTests/SyncEnvelopeTests.swift`
- `testPayloadCarriesAllContentFields` — fixture session+note → payload field-by-field equality (one assert per field group).
- `testContentHashIsStableForEqualContent` — two identical fixture pairs → equal hashes.
- `testContentHashChangesWhenBodyChanges` — edit markdown body → hash differs.

`SyncOutboxTests.swift`
- `testEnqueuePersistsFileAndPendingReturnsIt` — enqueue → file exists at `Outbox/<localId>.json`; `pending()` count 1.
- `testEnqueueSameLocalIdOverwrites` — enqueue v1 then v2 → `pending()` has one item with v2's hash.
- `testPendingSurvivesReinitialization` — enqueue, recreate outbox on same temp dir → item still pending (crash recovery).
- `testCompleteRemovesItem` — complete → file gone, `pending()` empty.

`SyncServiceTests.swift` (all with `MockSyncBackend`, injected clock/sleep)
- `testSignedOutMakesZeroBackendCalls` — 3 dirty meetings, `accountState == .signedOut`, run loop tick → `backend.upsertCount == 0` (privacy invariant).
- `testLocalOnlyMeetingsAreNeverEnqueued` — `markDirty` on a `localOnly` meeting → outbox stays empty.
- `testDrainPushesAllPendingAndCompletes` — 2 pending, signed in → `upsertCount == 2`, outbox empty.
- `testFailedPushRetriesWithExponentialBackoff` — backend throws twice then succeeds → recorded sleep delays `[1, 2]`, final outbox empty.
- `testDirtyWhileInFlightRequeues` — markDirty during an in-flight push of the same id → after drain, one more push with the newer hash.
- `testSummaryUpdateIsPersistedToSession` — backend emits `SummaryUpdate(localId, text)` → persist closure called once with that text.

`NoteTakrKit` (frontmatter): extend `FrontmatterSerializerTests`
- `testLocalOnlyRoundTripsThroughFrontmatter` — `local_only: true` survives serialize→parse; absent key → `nil`.

`convex/` (vitest + convex-test) — `meetings.test.ts`
- `upsert twice with same localId yields one document with updated fields`
- `upsert replaces transcript segments, never duplicates` — push 3 segments, then 4 → exactly 4 rows.
- `unchanged contentHash does not reschedule summarize`
- `changed contentHash reschedules summarize`
- `users only read their own meetings` — identity A cannot query B's meeting (auth check).

`summarize.test.ts` (OpenRouter fetch mocked)
- `writes summary and status ready on success`
- `sets status failed and preserves previous summary on API error`
- `schedules crm push after ready`

### Exit gate (e2e)

- All above green; new CI jobs (`convex-tests` on ubuntu, NoteTakrSync in `swift-package-tests`) green.
- New XCUITest `testMeetingSyncsAfterRecordingStops` with `NOTETAKR_E2E_MOCK_SYNC_BACKEND=1` (env-var seam, mirrors `NOTETAKR_E2E_USE_MOCK_RECORDER`): seeded signed-in mock account, record with mock recorder, stop → poll the mock backend's spool directory for the upserted payload JSON; then mock emits a summary → assert Summary tab shows it (AX) and `session.json` contains it (filesystem).
- Manual smoke additions: real Google sign-in via Clerk; real meeting → summary appears in Convex dashboard & Summary tab; `local_only` meeting never appears in Convex; sign out → app identical to today.

---

## Phase 3 — Twenty sink: people mirror, auto-match, CRM push, unmatched banner

### New code — Convex

- `crm/provider.ts` — `interface CrmProvider { listPeople(cfg): Promise<CrmPerson[]>; upsertMeetingNote(cfg, personRemoteIds, title, markdown, existingNoteId?): Promise<string> }`; registry keyed by `userSettings.crm.provider`.
- `crm/twenty.ts` — `TwentyProvider` against the user's base URL + API key (both in `userSettings`, set from the Mac settings UI): people query with pagination; note create/update + noteTargets attaching all matched persons.
- `crm/mirror.ts` — mirrors CRM people into `people` (match by lowercased email; update name/company; remove rows whose remoteId disappeared). Triggered three ways: **hourly cron** (`crons.ts`), immediately after the user saves/changes CRM config, and on-demand from the Mac's "Refresh people" affordance. The Mac's picker cache refreshes from `people` on every sync-loop pass while signed in, so a contact added in Twenty shows up in the picker within the hour — or instantly via manual refresh.
- `crm/push.ts` — action scheduled by `summarize`: skip if `crmPushOptOut` or no CRM configured; match `participants[].email` against `people`; compose markdown (summary, then transcript); `upsertMeetingNote` with stored `crmNoteId` for idempotency; write back `crmNoteId`, `pushStatus`, `unmatched: [names]`.

### New code — Swift

- `ConvexPeopleCacheSource` (`NoteTakrSync`) — `PeopleSource` over a locally cached snapshot of `people` (JSON at `NoteTakr/PeopleCache.json`, refreshed by `SyncService` when signed in; works offline from the last snapshot). Joins `PeopleDirectory` with priority: contacts > crm > pastMeetings for names; picker gains a "CRM" section.
- Auto-match indicator: participants resolved against the directory get their CRM state; `FrontmatterPresenter` exposes per-participant `matchedInCrm: Bool`.
- **Unmatched-participants banner**: new Kit presenter `CrmStatusPresenter` → `bannerText: String?` (`nil` unless `crmConnected && !unmatched.isEmpty`), e.g. "2 participants not in CRM". Rendered in `EditorView` between `tabContent` and `footerTabs` (the identified slot, EditorView.swift:91-93), styled like a quiet single-line `scopeBanner`, AX id `crmUnmatchedBanner`, dismissible per meeting.
- Settings: **CRM** section (Twenty base URL, API key → stored via existing settings/keychain conventions and mirrored to `userSettings`), connection test button, per-meeting "Push to CRM" toggle in This Meeting.
- `pushStatus` from Convex surfaces as a quiet indicator in the property panel (`pending | pushed | failed | skipped`).

### Tests (write first)

`convex/crm/twenty.test.ts` (fetch mocked)
- `listPeople maps twenty records to CrmPerson with lowercased emails`
- `listPeople follows pagination until exhausted`
- `upsertMeetingNote creates note and attaches all person targets`
- `upsertMeetingNote with existingNoteId updates instead of creating`
- `api error surfaces as typed CrmError, not a throw-through`

`convex/crm/push.test.ts`
- `matches participants to people by case-insensitive email`
- `unmatched participants are recorded and do not block the push`
- `stores crmNoteId and sets pushStatus pushed`
- `retry after transient failure reuses crmNoteId (no duplicate note)`
- `crmPushOptOut yields pushStatus skipped and zero provider calls`
- `no crm configured yields zero provider calls` (Phase-2 meetings unaffected)

`convex/crm/mirror.test.ts`
- `mirror inserts new people and updates changed names`
- `mirror removes people whose remoteId disappeared from crm`
- `mirror never touches people rows of other users`
- `hourly cron is registered and points at the mirror function` (assert against `crons.ts` registration)

`convex/crm/twenty.integration.test.ts` — **live tests against the real Twenty instance** (env-gated per the testing ground rules; required green for this phase's exit gate)
- `live: listPeople returns a non-empty mapped page from the real instance` — asserts real records map to `CrmPerson` with lowercased emails; fails loudly on schema drift Twenty-side.
- `live: a person created via the API appears in the next mirror pass` — create disposable person `[nt-test] Mirror Probe <nt-test+<runId>@example.invalid>`, run the mirror logic against the live provider, assert the person lands in `people`; delete in `finally`.
- `live: upsertMeetingNote creates exactly one note attached to the test person` — create note with summary+transcript markdown, list the person's notes, assert count 1 and body intact; delete in `finally`.
- `live: second upsert with the returned crmNoteId updates in place` — call again with changed markdown + `existingNoteId`, assert still exactly one note and body is the new version (the idempotency guarantee, proven against the real API, not a mock).
- `live: invalid api key maps to typed CrmError.unauthorized` — call with a garbage key, assert the typed error (so the settings "test connection" button can show a precise message).

`Tests/NoteTakrSyncTests/ConvexPeopleCacheSourceTests.swift`
- `testLoadsPeopleFromCachedSnapshot` — fixture cache file → `allPeople()` matches.
- `testMissingCacheFileYieldsEmptySourceWithoutError`
- `testRefreshRewritesSnapshotAtomically` — refresh with new list → file content replaced, old entries gone.

`NoteTakrKit/Tests/NoteTakrKitTests/CrmStatusPresenterTests.swift`
- `testBannerHiddenWhenCrmNotConnected` — unmatched present, `crmConnected == false` → `bannerText == nil`.
- `testBannerHiddenWhenAllParticipantsMatched` — connected, unmatched empty → `nil`.
- `testBannerTextCountsUnmatchedParticipants` — connected, 2 unmatched → `"2 participants not in CRM"` (1 → singular form).
- `testDismissSilencesBannerForThatMeetingOnly` — dismiss on meeting A → A `nil`, meeting B unaffected.

### Exit gate (e2e)

- All above green in CI — **including `twenty.integration.test.ts` run against the real instance** (locally with env vars set, and in CI via `TWENTY_TEST_BASE_URL`/`TWENTY_TEST_API_KEY` repo secrets on the `convex-tests` job; the job fails if secrets are present but the suite errors, and prints a skipped-warning if absent so a missing key can't silently pass the gate).
- New XCUITest `testUnmatchedCrmBannerAppearsAboveFooter` — env seam `NOTETAKR_E2E_MOCK_CRM_CONNECTED=1`, seeded note with one email-less participant → `crmUnmatchedBanner` exists and sits above the footer tabs; dismiss → gone; relaunch on another seeded note → banner logic re-evaluates.
- Manual smoke additions (against your real Twenty instance): connect CRM in settings (test button green); finish a real meeting with a known CRM contact → note with summary+transcript appears on that person in Twenty; re-run push → still exactly one note; opt-out toggle → `pushStatus: skipped`.

---

## Phase 4 — Attio adapter (+ deferred backlog)

- `convex/crm/attio.ts` — second `CrmProvider`; **no Swift, UI, or pipeline changes** (that's the point of the interface). Tests: mirror of `twenty.test.ts` (same six cases against Attio API shapes) + `provider registry resolves by userSettings.crm.provider` + an `attio.integration.test.ts` with the same five live cases, gated on `ATTIO_TEST_API_KEY`.
- "Create in CRM" affordance for unmatched participants (from the banner / participant menu) → `CrmProvider.createPerson` added with its own small test set.
- Deferred deliberately: cross-device live sync (schema is ready: payload-based, hash-tracked), audio upload (R2, opt-in), sharing, HubSpot/Salesforce (only on customer demand), real-time co-editing.

---

## Build/CI summary of new surfaces

| Surface | Where | Runs on |
|---|---|---|
| Kit People/presenter tests | `NoteTakrKit/Tests` | Linux `kit-tests` job (fast gate) |
| NoteTakrSync tests | `Tests/NoteTakrSyncTests` | macOS `swift-package-tests` job |
| Convex tests | `convex/` vitest | new ubuntu `convex-tests` job |
| Live CRM integration tests | `convex/crm/*.integration.test.ts` | same job, env-gated on `TWENTY_TEST_*` repo secrets (required for P3/P4 gates) |
| App glue + XCUITest e2e | `NoteTakrTests` / `NoteTakrUITests` | macOS `xcode-build-and-test` job |
| Real-world checks | `docs/manual-smoke-test.md` (rows added per phase) | physical Mac |
