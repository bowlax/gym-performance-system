# iOS first-connect sync upload

The **first-connect / push path** within the sync system: resumable bulk upload of an existing local member history to Supabase after broker connect.

Pull, merge, and the ongoing full cycle (**PULL → MERGE → PUSH**) are implemented separately — see [`docs/ios-sync-pull-merge-push.md`](ios-sync-pull-merge-push.md). This document covers the push mechanics shared by first-connect upload and the push phase of a full cycle.

## Local sync state

Optional `syncedAt: Date?` on:

- `SessionModel`
- `ExerciseEntryModel`
- `ModelSet`
- `PersonalBestModel`

`nil` means never successfully pushed (or not yet marked after a cloud-applied merge). After a successful batch upsert, the uploader sets `syncedAt` on those records locally. The cloud `synced_at` column is set in the same payload.

## Dirty criterion (push)

Records are pushed when they are **dirty**:

- `syncedAt` is `nil`, **or**
- device-set `updatedAt` is later than local `syncedAt`

On a pure first-connect (never synced), every local row has `syncedAt == nil`, so the whole history qualifies. After that, ongoing push uses the same dirty rule (including local edits that won a merge and were left unsynced).

## Upload order and batching

`FirstConnectUploader` walks data in FK order:

1. `sessions`
2. `exercise_entries`
3. `sets`
4. `personal_bests`

Dirty exercise entries and sets are scoped to the member being synced (via parent session ownership) so orphan children are never pushed.

Each table is pushed in batches of **`SyncConstants.uploadBatchSize` (50)** via PostgREST upsert:

- `POST /rest/v1/{table}?on_conflict=id`
- `Prefer: resolution=merge-duplicates,return=minimal`
- `Authorization: Bearer {broker JWT}` (member RLS scope)

On API failure, already-marked batches stay marked; unmarked records are retried on the next run.

## Code layout

| Area | Path |
|------|------|
| Orchestration | `src/utilities/sync-manager/SyncManager.swift` |
| Upload pipeline | `src/utilities/sync-manager/FirstConnectUploader.swift` |
| PostgREST client | `src/data/sync-service-access/PostgRESTSyncServiceAccess.swift` |
| Local queries | `src/data/sync-service-access/SwiftDataSyncLocalDataAccess.swift` |
| Row mapping | `src/data/sync-service-access/SyncPayloadMapper.swift` |

Entry point after connect (first-connect push only):

```swift
let result = await syncManager.uploadLocalHistoryAfterConnect(brokerSession: session)
```

Full cycle (pull then push):

```swift
let result = await syncManager.runFullSyncCycle(brokerSession: session)
```

Stub broker + upload (tests / manual harness):

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

## Live cloud test

1. Set scheme environment variables (Xcode → Edit Scheme → Test → Arguments → Environment):

   - `GYMPERF_SUPABASE_URL` — e.g. `https://<project>.supabase.co`
   - `GYMPERF_SUPABASE_PUBLISHABLE_KEY` — Supabase anon/publishable key
   - `GYMPERF_TEST_DEVICE_MEMBER_ID` — device id sent to the broker (adopted member id may differ; test seeds under JWT `member_id`)

2. Run `FirstConnectUploadIntegrationTests` (enabled by default when env is set).

3. The test mints a stub broker session first, seeds local data under the **adopted** `member_id` from the JWT, then uploads. First run expects sessions/entries/sets/PBs pushed; second in-test upload expects `counts.total == 0`.

4. Verify in Supabase Table Editor (or SQL) that rows appear under the test `member_id` with matching UUIDs and no duplicates after re-run.

## Device with real local history

Use the same env vars on a debug build, then after onboarding/connect:

```swift
// lldb or temporary debug hook
let manager = try SyncManager.makeFromCloudConfig(modelContext: context)
let result = await manager.mintStubSessionAndUpload()
```

`result.counts` reports how many rows were pushed per table; `result.completed` is `false` if interrupted (safe to retry).
