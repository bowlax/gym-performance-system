# iOS sync: pull-merge-push cycle

Builds on the first-connect push slice. Multi-device sync for the **normal** case (broker create-or-adopt already reconciled identity). The anonymous-local-then-adopt edge case is deferred (see Design decisions).

## Last-pull marker

Stored in `UserDefaults` per member via `SyncLastPullMarker`:

- Key: `syncLastPullSyncedAt.<memberUUID>`
- Value: `Date` — the high-water mark of cloud **`synced_at`** (cloud-authoritative), not device-set `updated_at`

Pull queries: `synced_at=gt.<marker>` (or `synced_at=not.is.null` on first pull). Marker advances only after a fully successful pull-and-merge.

## Merge / marker discipline

`SyncRecordMerger` — last-write-wins on device-set `updated_at`:

| Case | Action | Local `syncedAt` |
|------|--------|------------------|
| No local row | Insert from cloud | Set (cloud-applied) — **not** re-pushed |
| Cloud `updated_at` later | Overwrite local (including soft `deleted_at`) | Set (cloud-applied) — **not** re-pushed |
| Local `updated_at` later | Keep local | Unchanged (stays dirty if never pushed / edited after sync) |

Soft deletes: a pulled row with `deleted_at` is a normal LWW update; if cloud wins, local `deletedAt` is set.

## Push (generalised dirty)

Dirty criterion: `synced_at == nil OR updated_at > synced_at` (`SyncDirtiness`). Still parent-filtered, FK-ordered, idempotent upserts, mark-synced only after successful upsert.

## Full cycle entry point

```swift
let result = await syncManager.runFullSyncCycle(brokerSession: session)
// result.pull / result.push / result.completed

// Tests / stub:
let result = await syncManager.mintStubSessionAndRunFullSyncCycle()
```

Order: **PULL → MERGE → PUSH**. First-connect upload remains: `uploadLocalHistoryAfterConnect` (see `docs/ios-sync-first-connect.md`).

## Design decisions

### Anonymous-local-then-adopt (deferred): discard-cloud-wins

Not built yet. Applies when a member with **anonymous local data** connects and the broker **adopts** an existing cloud member that **already has cloud data**.

**Resolution: discard-cloud-wins** — after a clear informed warning framed as a choice at connect, the local anonymous data is discarded and the device is populated from the cloud (clear local + pull). No re-parenting or de-duplication of two histories. Triggers only when the adopted member already has cloud data.

Normal multi-device sync (same TeamUp customer, create-or-adopt, then pull-merge-push) does not use this path. Canonical record: `docs/gym-performance-system-design.md` §20.

## Tests

- Unit: `SyncRecordMergerTests` (insert, cloud-wins, local-wins, soft-delete, dirty criterion)
- Integration: `SyncCycleIntegrationTests` (push → simulate cloud edit → full cycle → idempotent second cycle)
