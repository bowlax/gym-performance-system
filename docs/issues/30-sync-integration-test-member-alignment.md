# Issue 30 (draft): Sync integration test — align seeded member id with broker-adopted id

**Status:** Fixed

## Problem

Integration test seeded local sessions under `GYMPERF_TEST_DEVICE_MEMBER_ID`, but stub broker adopts existing cloud member for `TEST-CUSTOMER-001`. JWT `member_id` could differ from seeded local `member_id` → sessions upload empty, entries orphan → RLS 403.

## Fix

1. `SyncManager.mintStubBrokerSession()` for tests
2. Integration test mints broker first, decodes adopted `member_id`, seeds under that id
3. Seeds session, entry, set, and personal best for full FK chain

## Create on GitHub

```bash
gh issue create --title "Sync integration test: align seeded member id with broker-adopted id" --body-file docs/issues/30-sync-integration-test-member-alignment.md
gh issue close <N> --comment "Fixed: seed after broker mint using JWT-adopted member_id."
```
