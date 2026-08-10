# GymPerformance - Phase 2 Progress Status

**Last updated:** August 2026
**Overall sense:** Foundation, member web, real TeamUp OAuth / Auth sessions, and iOS sync are shipped and live-validated. What remains is largely coach/owner surface work and further product polish — still substantial, but the identity and sync risks that blocked everything else are behind you.

---

## The shape of it

The genuinely hard, uncertain, foundational work is behind you: central store + RLS, token broker with real TeamUp OAuth and Supabase Auth ES256 sessions, member web on Cloudflare Workers, and iOS pull-merge-push sync. You are past the part where you did not know how identity or sync would work. Remaining work is surfaces and features on top of that foundation.

---

## Done and proven

- **Central store schema** - tables, indexes, applied to cloud and captured as migrations (including `exercise_resets`, member staleness, `members.auth_user_id`)
- **RLS policies** - full access model enforced at the database level, captured as migrations
- **Seeded data** - Wolf gym row and 19 exercises, correct UUIDs and display order, captured as migrations
- **service_role grants** - explicit table grants (needed due to locked-down project defaults), captured as migration
- **Member identity remediation** - phase 1 hardcoded UUID replaced with persisted per-install UUID plus one-time migration; tested on simulator and physical device; shipped to internal testing (not yet pushed to Wolf members group)
- **Token broker Edge Function** - create-or-adopt end to end against the cloud; **real TeamUp OAuth** + **Supabase Auth ES256 sessions** live in production. Custom access token hook promotes `member_id` / `gym_id` / `app_role`. GitHub issue [#17](https://github.com/bowlax/gym-performance-system/issues/17) (HS256 → Auth-session ES256) **closed 21 Jul 2026**. `JWT_SIGNING_SECRET` is local/stub-only and removed from deployed secrets; OAuth `state` uses `OAUTH_STATE_SECRET`
- **Shared JSON test vectors** - 19 vectors covering every PB rule, proven against the Swift implementation
- **TypeScript PB evaluation logic** - pure server-side module passing all 19 vectors, matching Swift semantics exactly
- **log-set and related Edge Functions** - server-side write paths for web members (`log-set`, `add-manual-pb`, `reset-current-pb`, `delete-personal-best`)
- **Member web surface** - **deployed** on Cloudflare Workers SSR (`gymperf-member-web`, TanStack Start). Real OAuth; session sealed in httpOnly cookie (`SESSION_SECRET`). Live URL linked from the landing page
- **iOS Sync Manager** - first-connect / full pull-merge-push cycle built and live-validated (retag → PULL → MERGE → PUSH on connect; discard-cloud-wins for anonymous-local-then-adopt #33)

---

## Still to build - unblocked / product follow-on

- Further member web and iOS polish (hardening, automated E2E, UX gaps)
- Engineering docs still catching up on some operational details (allowlists, schema completeness) — see ongoing doc tidy-up

---

## Still to build - blocked on outside input

- **Owner / coach surfaces** - waiting on the owner's discovery responses, coming back one question at a time. (Decision: for now, a single provider-facing owner surface rather than separate coach and owner surfaces; revisit later, since the three coaches have a read-only operational need distinct from the owner's strategic view.)

---

## Chosen build path (historical)

The phase 2 slice that de-risked everything was:

1. TypeScript PB evaluation logic
2. log-set Edge Function
3. React member web surface (now deployed)
4. Real TeamUp OAuth + Auth-session ES256 (#17 — done)
5. iOS Sync Manager for existing iPhone members (done)

Current focus shifts to coach/owner discovery and remaining product polish on the shipped member paths.

---

## Client architecture decision

Split pattern for the web surface: direct Supabase client for reads and simple writes (protected by RLS, low latency, no duplicated code), Edge Functions only where genuine server-side business logic is required (PB evaluation). Everything-through-functions was considered and rejected due to added latency, duplicated querying, and maintenance surface. Auth for web: broker OAuth callback → Worker seals session cookie → `GET /api/auth/session` exposes access token to the client (refresh stays server-side).

---

## Honest caveat on the estimate

Earlier “one third” figures were reasoning from the shape of the work, not a measurement. The reliable statement now is qualitative: identity, sync, and member web are live; coach/owner and further polish remain.
