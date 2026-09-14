# Lessons Learned

This file exists so recurring failure shapes get recognised the next
time they appear, instead of being independently rediscovered. Add to
it when a bug's *pattern* is more valuable than the fix itself.

---

## Recurring pattern: an operation reports success without actually
   doing what it claims

This has hit the codebase at least four times, in different layers.
Each time, the fix looked like a one-off bug; the shape is the same
one recurring.

1. **First-connect sync (Phase C, #17).** `uploadLocalHistoryAfterConnect`
   reported `"nothing to upload"` when local training rows were tagged
   with the wrong (anonymous) member id after adopt. The upload
   genuinely ran and genuinely found zero dirty rows under the id it
   queried - it just queried the wrong id. Fixed by re-tagging rows to
   the canonical id before sync, and by making the sync cycle
   self-healing so a stranded state recovers on the next cycle.

2. **Second-device connect (#17).** Connect only ever *pushed*; a
   fresh device adopting a member with existing cloud history got
   `proceedToUpload`, found nothing local to push, and reported
   success with an empty board. The pull half of "converge via
   pull-merge-push" was never wired into the connect path at all.
   Fixed by making connect run a full pull-merge-push cycle, gating
   `recordSuccess` on the whole cycle completing, not just the push.

3. **Callback 405 / stub 502 (#17, broker).** The broker's OAuth
   routing and stub-rejection logic were correct in isolation, but the
   test suite only asserted *helper function* return values - it never
   drove the real `Deno.serve` HTTP entry point. A live TeamUp redirect
   (double-`?` in the query string) and a live stub-token POST both hit
   real bugs in the actual routing that the tests could not see,
   because the tests never exercised that layer.

4. **Test cleanup silently not cleaning up (this session).** Several
   Edge Function test suites called `admin.from(...).delete()` against
   `service_role`, which has no `DELETE` grant on any table (deliberate
   - hard-delete is a privileged GDPR-only path, not something
   PostgREST roles get). `supabase-js` does not throw on an error
   response unless you check `.error`. So every one of these calls
   silently 403'd, was ignored, and the test reported success while
   leaving live rows behind. Real leftover test gyms sat in the live
   project for weeks before being noticed. Fixed by: tombstoning
   (`UPDATE deleted_at`, which `service_role` *can* do) instead of hard
   delete for test cleanup; explicitly checking every mutation's
   response and throwing loudly on error; and restricting any
   mutating test to `onlyIfLoopback` so a misconfigured env var can't
   silently write test data to the hosted project again.

**The common thread:** in every case, the *operation itself* looked
correct when read in isolation - the upload logic, the connect branch
logic, the routing logic, the delete call - and the failure was in
whether the surrounding check actually confirmed the operation did
what it claimed. The fix each time was the same shape: stop trusting
that "the call didn't throw" or "the function returned" means it
succeeded at the *specific* thing being asked. Check the actual
before/after state, or make failure loud rather than silent.

**Standing practice this suggests:** any test or script that performs
a side-effecting operation (write, delete, sync, push) must either
verify the resulting state directly, or explicitly check the
operation's own error/response field and fail on it. Silence is not
success. This applies with extra weight to anything running against
the hosted project rather than local.

---

## Same-day reset-then-PB bug (member-reported, this session)

**Symptom:** a member did a PB reset and logged a new PB the same
calendar day. The board did not recognise the new PB as current;
changing the achievement date to the following day fixed it.

**Root cause:** `isAfterReset` compares `achievedAt` and `resetAt` as
calendar-day strings with a strict `>`. Two records on the same
calendar day give `"date" > "same date"` = `false`, so same-day
ordering was always lost - the new PB was treated as if it predated
the reset, regardless of which actually happened first that day.

**Why it shipped:** the vectors specified equal-calendar-day as
*excluded* (TC-D7 / OQ-D2 - a PB logged, then reset later the same
day, correctly stays excluded) but never specified the *reverse*
ordering (reset, then a new PB later the same day, which should
count). The exclude-on-equal-day behaviour was deliberate and correct
for one ordering; nobody had specified the other.

**Fix:** keep calendar-day comparison everywhere except the exact-equal
case. Only when `achievedAt == resetAt`, break the tie using each
record's real timestamp (`created_at`) against the reset row's real
timestamp - using `updated_at` on the reset, not `created_at`, because
resets reuse the same row on every re-reset (`created_at` would
freeze at the *first ever* reset for that member-exercise). Timestamps
are used *only* to resolve this one ambiguity; staleness/period math
and the separately-pinned equal-value "latest wins" tie-break remain
calendar-day only, deliberately.

Fixed identically in `PBDerivation.swift` and `pb-derivation.ts`, with
two new shared vectors (TC-D21, TC-D22) covering both same-day
orderings, so the specification - not just the code - now covers this
case.

**iOS-specific note:** this fix lives in Swift and TypeScript, but
only the TypeScript half (web, Edge Functions, owner surface) took
effect on deploy. iOS requires a new app build to reach any given
member - a backend/web deploy alone does not fix this for someone
already on an older installed build.

---

## Session/entry delete was a hard-delete, not a tombstone (this session)

**Symptom (discovered while investigating an unrelated question):**
iOS `deleteSession` and `deleteHistoryEntry` (single set) both used
SwiftData `context.delete` - a genuine local removal, never setting
`deletedAt`. For a session/entry that had already synced, this meant:
the cloud copy was never told to delete anything, so it stayed live
in Postgres, on web, and in every owner-surface read; and a later pull
(reinstall, second device) could resurrect the "deleted" session,
because the merge logic sees "cloud has it, local doesn't" as *local
needing to catch up*, not as a deliberate removal.

**Why hard-delete resurrects and tombstoning doesn't:** sync works by
comparing what each side has. A genuinely missing row is
indistinguishable from "never synced here yet." A tombstoned row
(`deleted_at` set, row still present) carries the actual instruction
"this was removed," which every reader and every device can see and
respect.

**Compounding gap:** even after switching to tombstoning, most
derivation/read queries only checked their *own* row's `deleted_at` -
not the parent session's. A session-level-only tombstone would not
have hidden its still-"live" child entries and sets almost anywhere
except two owner-surface views that had already been built checking
the parent explicitly. Fixed by cascading the tombstone to every
child row explicitly (not relying on parent-checking), and by adding
the missing `session.deleted_at is null` filter to every derivation
query that joins through sessions.

**Permanent limitation, not a TODO:** sessions/entries hard-deleted
*before* this fix cannot be identified or cleaned up after the fact.
There is no tombstone and no deletion log for them - a missing local
row looks identical to "never synced to this device." Any real member
data lost to this bug prior to the fix stays live in the cloud
(orphaned, but not incorrect - just not actually deleted the way the
member expected) until it resurfaces and is deleted again under the
corrected path, or an admin is given known IDs.

**Feature parity finding:** while investigating this, discovered web
had no way to delete an entire session at all (only single-entry
delete existed), and no way to edit an existing manual PB in place
(add-then-delete-and-recreate only) - both undocumented gaps against
the stated "identical features" requirement, not deliberate platform
differences like onboarding shape or offline mode. Both closed in the
same body of work as the tombstone fix.

**Verification note:** the HTTP-level tests for all of this passed
cleanly, but three real UI bugs only surfaced when someone actually
clicked through the live, deployed web app in a browser - a success-
copy React state bug (fixed), a suspected Cancel-button failure that
turned out to be the test driver not genuinely clicking (not a real
bug, confirmed by re-testing with a real click), and a viewport-
centering note (accepted as expected desktop-browser behaviour for a
phone-first app). Passing tests did not substitute for a real
click-through, and a real click-through's own findings still needed
scrutiny before being trusted as real bugs.
