# Issue 29 (draft): Sync uploader — filter entries/sets by parent session member

**Status:** Fixed

## Problem

First-connect upload fetched sessions filtered by JWT `member_id`, but fetched **all** unsynced `exercise_entries` and `sets`. Child rows could be pushed when their parent session was never uploaded → RLS 403 (`entries_insert_own` EXISTS fails).

## Fix

- `fetchUnsyncedExerciseEntries(memberId:)` — entries whose `session_id` belongs to that member's sessions
- `fetchUnsyncedSets(memberId:)` — sets whose parent entry chains to that member's sessions
- `FirstConnectUploader` passes `memberId` into both phases
- Unit test `uploadSkipsOrphanChildrenForOtherMembers`

## Create on GitHub

```bash
gh issue create --title "Sync uploader: filter exercise entries and sets by parent session member" --body-file docs/issues/29-sync-uploader-parent-filter.md
gh issue close <N> --comment "Fixed: member-scoped entry/set fetch in SwiftDataSyncLocalDataAccess + FirstConnectUploader."
```
