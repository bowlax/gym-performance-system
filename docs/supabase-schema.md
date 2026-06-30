# Supabase Central Data Store -- Schema Specification

**Project:** Gym Performance System  
**Phase:** 2 -- Central Data Store  
**Database:** PostgreSQL (Supabase)  
**Status:** Design -- not yet implemented  
**Last updated:** June 2026

> This is the central store schema. It is based on the phase 1 SwiftData schema 
> (docs/data-schema.md) with phase 2 additions: real member identity, gym_id, 
> sync metadata, soft delete, and row-level security.
> 
> The device remains the source of truth in the local-first model. This store is 
> a sync target for members who have opted in.

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
gym association, TeamUp auth mapping, and sync preference. Does NOT duplicate TeamUp-owned 
data (membership status, billing, bookings) -- those are read live from TeamUp.

```sql
create table members (
    id                  uuid primary key,        -- the per-install UUID, canonical identity
    gym_id              uuid not null references gyms(id),
    teamup_customer_id  text,                    -- populated when member connects. Null if not yet mapped
    display_name        text not null default 'Member',
    sync_enabled        boolean not null default true,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz,
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

A PB record. Member-owned. Full history retained via is_current flag.

```sql
create table personal_bests (
    id                  uuid primary key,
    gym_id              uuid not null references gyms(id),
    member_id           uuid not null references members(id),
    exercise_id         uuid not null references exercises(id),
    set_id              uuid references sets(id),  -- null for manual entries
    weight              double precision,
    reps                integer,
    time_seconds        double precision,
    distance            double precision,
    achieved_at         date not null,
    is_current          boolean not null default true,
    entry_type          text not null default 'sessionDerived',  -- sessionDerived | manualEntry
    was_reset           boolean not null default false,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz,
    synced_at           timestamptz,
    source_device_id    uuid
);
```

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

-- PB queries
create index idx_pb_current on personal_bests(member_id, exercise_id) where is_current = true and deleted_at is null;
create index idx_pb_member on personal_bests(member_id) where deleted_at is null;
create index idx_pb_gym on personal_bests(gym_id) where deleted_at is null;

-- Exercise lookups
create index idx_exercises_gym on exercises(gym_id) where deleted_at is null;
```

---

## Row-Level Security (RLS)

RLS enforces the privacy model at the database level. These are the rules in plain terms; 
exact policy SQL depends on how TeamUp identity maps to Supabase auth (to be finalised 
during the auth integration).

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
| Member identity | Single per device (was hardcoded, now per-install UUID) | Real distinct members in members table |
| gym_id | Not present | On every entity |
| Soft delete | Hard delete only (no delete for most) | deleted_at timestamp |
| Sync metadata | None | synced_at, source_device_id |
| Security | None (single user per device) | Row-level security |
| Exercise definitions | Bundled with app | Per-gym in exercises table |
| TeamUp mapping | None | teamup_customer_id on members |
| Set table name | ModelSet (Swift collision) | sets (no collision in SQL) |
| time field | time (Double, seconds) | time_seconds (explicit) |

---

## What Stays Identical

The core data model is unchanged -- same entities, same relationships, same business 
meaning. A session still contains exercise entries, which contain sets. PBs still 
reference the achieving set and carry full history via is_current. The UUIDs are the 
same values as the local store, which is what makes the merge-on-connection clean.

This is the phase 1 schema with identity, tenancy, sync, and security layered on -- 
not a redesign.
