# iOS first-connect sync upload

The **push half** of sync: resumable bulk upload of dirty local member history to Supabase. Used as the PUSH phase of the full cycle after connect, and as a standalone harness for push-only tests.

Product connect does **not** push-only. After broker auth, connect runs retag (when adopted) then the full **PULL → MERGE → PUSH** cycle — see entry point below and [`docs/ios-sync-pull-merge-push.md`](ios-sync-pull-merge-push.md). This document covers push mechanics (`FirstConnectUploader`) shared by that cycle’s push phase.

## Local sync state

Optional `syncedAt: Date?` on:

- `UserIdentityModel` (member settings — staleness / sync bookkeeping)
- `SessionModel`
- `ExerciseEntryModel`
- `ModelSet`
- `PersonalBestModel`
- `ExerciseResetModel`

`nil` means never successfully pushed (or not yet marked after a cloud-applied merge). After a successful batch upsert (or member settings PATCH), the uploader sets `syncedAt` on those records locally. The cloud `synced_at` column is set in the same payload where applicable.

## Dirty criterion (push)

Records are pushed when they are **dirty**:

- `syncedAt` is `nil`, **or**
- device-set `updatedAt` is later than local `syncedAt`

On a pure first-connect (never synced), every local row has `syncedAt == nil`, so the whole history qualifies. After that, ongoing push uses the same dirty rule (including local edits that won a merge and were left unsynced).

## Upload order and batching

`FirstConnectUploader` walks data in FK / dependency order:

1. `members` — settings PATCH only (staleness fields + sync bookkeeping). Never INSERT; broker create-or-adopt owns identity (`auth_user_id`, TeamUp mapping)
2. `sessions`
3. `exercise_entries`
4. `sets`
5. `personal_bests`
6. `exercise_resets`

Dirty exercise entries and sets are scoped to the member being synced (via parent session ownership) so orphan children are never pushed.

Each upsert table is pushed in batches of **`SyncConstants.uploadBatchSize` (50)** via PostgREST upsert:

- `POST /rest/v1/{table}?on_conflict=id`
- `Prefer: resolution=merge-duplicates,return=minimal`
- `Authorization: Bearer {session JWT}` (member RLS scope)

On API failure, already-marked batches stay marked; unmarked records are retried on the next run.

## Code layout

| Area | Path |
|------|------|
| Connect orchestration | `src/utilities/sync-manager/ConnectFlowService.swift` |
| Full cycle | `src/utilities/sync-manager/SyncManager.swift` |
| Upload pipeline (push) | `src/utilities/sync-manager/FirstConnectUploader.swift` |
| PostgREST client | `src/data/sync-service-access/PostgRESTSyncServiceAccess.swift` |
| Local queries | `src/data/sync-service-access/SwiftDataSyncLocalDataAccess.swift` |
| Row mapping | `src/data/sync-service-access/SyncPayloadMapper.swift` |

### Entry point after connect (product path)

Connect UI / `ConnectFlowService` — **not** push-only:

```swift
// ConnectFlowService.syncAfterConnect(session:)
// 1. If broker adopted a different canonical member id → retag local history
// 2. Run full cycle: PULL → MERGE → PUSH (SyncManager.runFullSyncCycle)
let result = await service.syncAfterConnect(session: brokerSession)
// Success UI ("You’re connected") only when result.completed
// (pull.completed && push.completed)
```

Push-only (`uploadLocalHistoryAfterConnect`) remains for tests / harnesses. Do not use it as the product connect path — second-device connect must pull before push.

Disconnect (iOS) and sign-out (web) are separate from sync — see [`docs/member-disconnect-signout.md`](member-disconnect-signout.md).

Full cycle (same cycle connect uses after retag):

```swift
let result = await syncManager.runFullSyncCycle(brokerSession: session)
```

Stub broker + push-only (tests / manual harness):

```swift
let result = await syncManager.mintStubSessionAndUpload()
```

## Unit tests (always)

```bash
xcodebuild test \
  -project GymPerformance.xcodeproj \
  -scheme GymPerformance \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:GymPerformanceTests/SyncPayloadMapperTests \
  -only-testing:GymPerformanceTests/FirstConnectUploaderTests
```

## Configuration (Build 13)

### DEBUG Run (Xcode)

Set **Edit Scheme → Run → Environment Variables** locally (not committed):

| Variable | Purpose |
|----------|---------|
| `GYMPERF_SUPABASE_URL` | Supabase project API URL |
| `GYMPERF_SUPABASE_PUBLISHABLE_KEY` | Supabase publishable (anon) key |
| `GYMPERF_TEST_DEVICE_MEMBER_ID` | Optional — stub/integration harness device id override |
| `GYMPERF_USE_REAL_OAUTH` | Set to `1` for real TeamUp OAuth; omit for stub broker |

Resolution order in DEBUG: scheme env → Info.plist → unavailable.

### Release / TestFlight archive

1. `cp Config/Release.xcconfig.example Config/Release.xcconfig` (gitignored)
2. Fill in values (URL must use xcconfig-safe form — `//` is a comment in xcconfig):
   ```
   GYMPERF_SUPABASE_URL = https:/$()/YOUR_PROJECT.supabase.co
   GYMPERF_SUPABASE_PUBLISHABLE_KEY = sb_publishable_...
   ```
3. Archive — values substitute into `GymPerformance/Info.plist` at build time

Empty `Release.xcconfig` → connect hidden, sync inert (safe default).

## Live cloud test

1. Set scheme environment variables (Xcode → Edit Scheme → Test → Arguments → Environment):

   - `GYMPERF_SUPABASE_URL` — e.g. `https://<project>.supabase.co`
   - `GYMPERF_SUPABASE_PUBLISHABLE_KEY` — Supabase anon/publishable key
   - `GYMPERF_TEST_DEVICE_MEMBER_ID` — device id sent to the broker (adopted member id may differ; test seeds under JWT `member_id`)

2. Run `FirstConnectUploadIntegrationTests` (enabled by default when env is set).

3. The test mints a stub broker session first, seeds local data under the **adopted** `member_id` from the JWT, then uploads. First run expects dirty rows pushed (including member settings / resets when present); second in-test upload expects `counts.total == 0`.

4. Verify in Supabase Table Editor (or SQL) that rows appear under the test `member_id` with matching UUIDs and no duplicates after re-run.

## Device with real local history

Use the same env vars on a debug build, then after onboarding/connect:

```swift
// lldb or temporary debug hook
let manager = try SyncManager.makeFromCloudConfig(modelContext: context)
let result = await manager.mintStubSessionAndUpload()
```

`result.counts` reports how many rows were pushed per table; `result.completed` is `false` if interrupted (safe to retry).
