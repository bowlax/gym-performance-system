# GymPerformance - Phase 2 Progress Status

**Last updated:** July 2026
**Overall sense:** Roughly one third through phase 2, but the completed third was the hardest and riskiest. The foundation is done and proven; what remains is substantial but well-specified building, largely unblocked.

---

## The shape of it

The genuinely hard, uncertain, foundational work is behind you. The data and identity model, the security model, the sync design, and the server-side business logic are all designed and, where built, proven. You are past the part where you did not know how something would work. What remains is the surfaces and the sync machinery: meaningful builds, but well understood.

---

## Done and proven

- **Central store schema** - 7 tables, indexes, applied to cloud and captured as migrations
- **RLS policies** - full access model enforced at the database level, captured as migrations
- **Seeded data** - Wolf gym row and 19 exercises, correct UUIDs and display order, captured as migrations
- **service_role grants** - explicit table grants (needed due to locked-down project defaults), captured as migration
- **Member identity remediation** - phase 1 hardcoded UUID replaced with persisted per-install UUID plus one-time migration; tested on simulator and physical device; shipped to internal testing (not yet pushed to Wolf members group)
- **Token broker Edge Function** - create-or-adopt member logic working end to end against the cloud; gym lookup, member creation, JWT minting all proven (TeamUp verification stubbed, HS256 interim signing)
- **Shared JSON test vectors** - 19 vectors covering every PB rule, proven against the Swift implementation
- **TypeScript PB evaluation logic** - pure server-side module passing all 19 vectors, matching Swift semantics exactly

---

## In progress

- **log-set Edge Function** - the first server-side write path for web members: fetch current PB, evaluate via shared logic, persist result

---

## Still to build - unblocked

- **Member web surface (React)** - primarily for Android users, who currently have no functionality at all. Reads and simple writes go direct to the store under RLS; PB logging goes through the log-set Edge Function. This is the most isolated build, since it disturbs no existing user.
- **iOS Sync Manager** - syncs existing iPhone members' local data up to the cloud and back (pull-merge-push, last-write-wins). Reuses existing Swift business logic, so needs no new logic, but does touch existing members.

---

## Still to build - blocked on outside input

- **Real TeamUp verification + ES256 signing** - the "make the broker real" work. Needs TeamUp API access, which needs the gym owner to authorise it against the gym's TeamUp business account. Tracked as a GitHub issue with a launch gate. The stub keeps all current building unblocked.
- **Owner surface** - waiting on the owner's discovery responses, coming back one question at a time. (Decision: for now, a single provider-facing owner surface rather than separate coach and owner surfaces; revisit later, since the three coaches have a read-only operational need distinct from the owner's strategic view.)

---

## Chosen build path

The current focus is the isolated, unblocked Android member path, in this order:

1. TypeScript PB evaluation logic (done)
2. log-set Edge Function (in progress)
3. React member web surface

In parallel: sorting TeamUp API access with the owner, which unblocks the "make the broker real" work.

Then: the iOS Sync Manager for existing iPhone members.

---

## Client architecture decision

Split pattern for the web surface: direct Supabase client for reads and simple writes (protected by RLS, low latency, no duplicated code), Edge Functions only where genuine server-side business logic is required (PB evaluation). Everything-through-functions was considered and rejected due to added latency, duplicated querying, and maintenance surface.

---

## Honest caveat on the estimate

The "one third" figure is reasoning from the shape of the work, not a measurement. The reliable statement is qualitative: the hard, uncertain, foundational work is behind you; what remains is substantial but well-understood.
