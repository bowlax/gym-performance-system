# Supabase Central Data Store -- Schema Specification

**Project:** Gym Performance System  
**Phase:** 2 -- Central Data Store  
**Database:** PostgreSQL (Supabase)  
**Status:** Live (migrations are the applied source)  
**Last updated:** July 2026

> This is the central store schema. It is based on the phase 1 SwiftData schema 
> (docs/data-schema.md) with phase 2 additions: real member identity, gym_id, 
> sync metadata, soft delete, and row-level security.
> 
> The device remains the source of truth in the local-first model. This store is 
> a sync target for members who have opted in.

### Migration history provenance

The hosted project was initially set up by running SQL in the Supabase dashboard
SQL editor. Files in `supabase/migrations/` were a parallel record of that
state — not the applied source of truth — so `supabase_migrations.schema_migrations`
on live was empty even though the tables existed.

On **2026-07-16** (issue #28 step 4 deploy), migration history was repaired:
versions through `20260706170000` were marked applied (already present on live),
then `20260715180000` (staleness + `exercise_resets`) and
`20260716180000` (drop `is_current` / `was_reset`) were pushed for real.
During that repair, step 2’s `exercise_resets` table and member staleness
columns were found **missing** on live — they had never been dashboard-applied —
and landed for the first time in that push.

From that date forward, `supabase/migrations/` is the applied source. Use
`npx supabase db push` for new migrations; do not re-apply early versions by hand.

---

## Design Decisions

| Decision | Choice |
|---|---|
| Member identity | Member's own per-install UUID (canonical). TeamUp customer ID stored separately for auth mapping |
| Soft delete | `deleted_at` timestamp -- null means active, a timestamp means soft-deleted |
| GDPR erasure | Hard delete -- physical row removal |
| Conflict resolution | Last-write-wins by `updated_at` |
| Multi-gym | `gym_id` on every entity. Maps to TeamUp provider ID |
| Sync metadata | `synced_at`, `source_device_id` on syncable entities |
| Identity scheme | Same UUID scheme as phase 1 local store -- clean merge on connection |

---

## Universal Columns

Most tables carry these columns:

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | Primary key. Same UUID as the local device record -- enables clean merge |
| `gym_id` | uuid | Which gym this belongs to. Maps to TeamUp provider ID. Not null |
| `member_id` | uuid | Owning member. FK to members.id. Not null on member-owned records |
| `created_at` | timestamptz | Record creation. Default now() |
| `updated_at` | timestamptz | Last modification. Drives last-write-wins. Default now() |
| `deleted_at` | timestamptz | Soft delete. Null = active |
| `synced_at` | timestamptz | When last synced from a device. Diagnostics |
| `source_device_id` | uuid | Which device the record originated from. Support and conflict diagnosis |

---

## Tables

### gyms

The tenant table. One row per gym. Anticipates multi-gym without building full multi-tenancy.

```sql
create table gyms (
    id                  uuid primary key default gen_random_uuid(),
    teamup_provider_id  text unique not null,   -- maps to TeamUp provider
    name                text not null,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz
);
```

---

### members

The identity anchor. One row per connected member. Holds the canonical member UUID, 
gym association, TeamUp auth mapping, sync preference, and staleness settings (#28).
Does NOT duplicate TeamUp-owned data (membership status, billing, bookings).

```sql
create table members (
    id                  uuid primary key,        -- the per-install UUID, canonical identity
    gym_id              uuid not null references gyms(id),
    teamup_customer_id  text,                    -- populated when member connects. Null if not yet mapped
    display_name        text not null default 'Member',
    sync_enabled        boolean not null default true,
    staleness_enabled   boolean not null default false,
    staleness_periods   integer not null default 2,
    staleness_unit      text not null default 'quarter',  -- quarter | month
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz,
    synced_at           timestamptz,
    source_device_id    uuid,
    unique (gym_id, teamup_customer_id)          -- one member per TeamUp customer per gym
);
```

---

### exercises

Exercise definitions. In phase 1 these were bundled per-app. In phase 2 they become 
per-gym so different gyms can have different exercises. Owned by the gym, not a member.

```sql
create table exercises (
    id                  uuid primary key default gen_random_uuid(),
    gym_id              uuid not null references gyms(id),
    name                text not null,
    category            text not null,           -- 'pbExercise' | 'conditioning'
    measurement_type    text not null,           -- weightAndReps | weightAndTime | timeOnly | distanceOnly | repsOnly | weightAndDistance
    pb_rule             text,                    -- heaviestWeightAtReps | heaviestWeight | bestWeightAndReps | fastestTime | longestDistance | mostReps. Null for conditioning
    target_reps         integer,                 -- for heaviestWeightAtReps
    minimum_reps        integer,                 -- for bestWeightAndReps
    parent_exercise_id  uuid references exercises(id),  -- variant relationship
    display_order       integer not null,
    is_active           boolean not null default true,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz
);
```

---

### sessions

A training session. Member-owned.

```sql
create table sessions (
    id                  uuid primary key,        -- same UUID as local device record
    gym_id              uuid not null references gyms(id),
    member_id           uuid not null references members(id),
    date                date not null,
    notes               text,
    calories_burned     integer,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz,
    synced_at           timestamptz,
    source_device_id    uuid
);
```

---

### exercise_entries

One exercise performed within a session. Relates to member via session.

```sql
create table exercise_entries (
    id                  uuid primary key,
    gym_id              uuid not null references gyms(id),
    session_id          uuid not null references sessions(id),
    exercise_id         uuid not null references exercises(id),
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz,
    synced_at           timestamptz,
    source_device_id    uuid
);
```

---

### sets

One logged set within an exercise entry. Note: named `sets` here -- the Swift collision 
that forced `ModelSet` does not apply in Postgres.

```sql
create table sets (
    id                  uuid primary key,
    gym_id              uuid not null references gyms(id),
    exercise_entry_id   uuid not null references exercise_entries(id),
    weight              double precision,
    reps                integer,
    time_seconds        double precision,        -- named explicitly to avoid SQL 'time' type confusion
    distance            double precision,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz,
    synced_at           timestamptz,
    source_device_id    uuid
);
```

---

### personal_bests

**Manual PB entries only** (no set behind them). Session PBs are derived from `sets` +
manuals at read time (#28). There is no `is_current` / `was_reset` — those columns were
dropped in `20260716180000`.

```sql
create table personal_bests (
    id                  uuid primary key,
    gym_id              uuid not null references gyms(id),
    member_id           uuid not null references members(id),
    exercise_id         uuid not null references exercises(id),
    set_id              uuid references sets(id),  -- null for manuals; unused for new writes
    weight              double precision,
    reps                integer,
    time_seconds        double precision,
    distance            double precision,
    achieved_at         date,
    entry_type          text not null default 'manualEntry',  -- manualEntry (sessionDerived = legacy)
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz,
    synced_at           timestamptz,
    source_device_id    uuid
);
```

---

### exercise_resets

One `reset_at` date per member-exercise. Sparse. Affects **current** derivation only
(lifetime unchanged). Repeat resets overwrite `reset_at` (later wins). Undo = soft-delete.

```sql
create table exercise_resets (
    id                  uuid primary key,
    gym_id              uuid not null references gyms(id),
    member_id           uuid not null references members(id),
    exercise_id         uuid not null references exercises(id),
    reset_at            date not null,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz,
    synced_at           timestamptz,
    source_device_id    uuid,
    unique (member_id, exercise_id)
);
```

---

## Personal-best derivation (as built, #28)

Same semantics as local (`docs/data-schema.md`):

- **Current** = best where `achieved_at` > `reset_at` (if any) and fresh under staleness.
  Tie → most recent `achieved_at`.
- **Lifetime** = best overall (no reset / freshness filter).
- **Fresh** = before expiry of N complete calendar periods since `achieved_at`; OFF = no expiry.
- **Badges** = running max over dated records; equal not badged.
- Shared vectors: `tests/vectors/pb-{expiry,derivation,badge,evaluation}-vectors.json`.

**Not migrated:** legacy `was_reset` flags were not translated into `exercise_resets`
(deliberate — see issue #28). **Derivation reads sets + manuals**, not session PB rows;
real-device check confirmed set completeness (19/19).

---

## Indexes

```sql
-- Member lookups
create index idx_members_gym on members(gym_id);
create index idx_members_teamup on members(gym_id, teamup_customer_id);

-- Session queries
create index idx_sessions_member on sessions(member_id) where deleted_at is null;
create index idx_sessions_gym on sessions(gym_id) where deleted_at is null;
create index idx_sessions_date on sessions(member_id, date) where deleted_at is null;

-- Entry and set traversal
create index idx_entries_session on exercise_entries(session_id) where deleted_at is null;
create index idx_sets_entry on sets(exercise_entry_id) where deleted_at is null;

-- PB / reset queries (current PB is derived — no idx_pb_current)
create index idx_pb_member on personal_bests(member_id) where deleted_at is null;
create index idx_pb_gym on personal_bests(gym_id) where deleted_at is null;
create index idx_exercise_resets_member on exercise_resets(member_id) where deleted_at is null;
create index idx_exercise_resets_gym on exercise_resets(gym_id) where deleted_at is null;

-- Exercise lookups
create index idx_exercises_gym on exercises(gym_id) where deleted_at is null;
```

---

## Row-Level Security (RLS)

RLS enforces the privacy model at the database level. These are the rules in plain terms; 
exact policy SQL depends on how TeamUp identity maps to Supabase auth (to be finalised 
during the auth integration). See also `docs/supabase-schema-rls.md`.

### Principles

| Actor | Can read | Can write |
|---|---|---|
| Member | Own records only (member_id matches their identity) | Own records only |
| Coach | All records for members in their gym | Commentary and goals only (phase 2 coach features) |
| Owner | All records for their gym | Member and coach management |
| Anonymous member | Nothing in the central store -- they are local-only | Nothing |

### Key rules

1. Every query is scoped to the requester's `gym_id` -- no cross-gym access ever
2. Members can only see and modify rows where `member_id` equals their own identity
3. Coaches (TeamUp providers) can read all member rows within their gym
4. Soft-deleted rows (`deleted_at is not null`) are excluded from normal reads but retained for sync
5. GDPR erasure is a privileged operation that hard-deletes -- not exposed to normal member or coach roles

> **Note:** RLS policy SQL is deferred until the TeamUp-to-Supabase auth mapping is designed. 
> The principles above are the contract those policies must enforce.

---

## Differences From Phase 1 Local Schema

| Aspect | Phase 1 (SwiftData) | Phase 2 (Postgres) |
|---|---|---|
| Member identity | Per-install UUID in UserDefaults + UserIdentityModel state | Real distinct members in members table |
| gym_id | Not present | On every entity |
| Soft delete | Soft delete on syncable entities | deleted_at timestamp |
| Sync metadata | synced_at, source_device_id on syncable entities | Same |
| Security | None (single user per device) | Row-level security |
| Exercise definitions | Bundled with app | Per-gym in exercises table |
| TeamUp mapping | None | teamup_customer_id on members |
| Set table name | ModelSet (Swift collision) | sets (no collision in SQL) |
| time field | time (Double, seconds) | time_seconds (explicit) |
| PB status | Derived (#28) | Derived (#28) — same vectors |
| Manual PBs | PersonalBestModel | personal_bests |
| Resets | ExerciseResetModel | exercise_resets |

---

## What Stays Identical

The core workout record is unchanged: sessions contain exercise entries, which contain
sets. Manual PBs live in `personal_bests`. Current / lifetime / badges are **derived**
over sets + manuals (plus `exercise_resets` and member staleness), not stored as
`is_current` flags. The UUIDs match the local store so merge-on-connection stays clean.

This is the phase 1 workout schema with identity, tenancy, sync, security, and derived
PB status layered on — not a redesign of what a set or session means.
