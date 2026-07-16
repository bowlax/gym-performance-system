-- Issue #28 STEP 2 (additive): member staleness settings + exercise_resets.
-- Does NOT drop is_current/was_reset or alter personal_bests derivation columns.

-- ---------------------------------------------------------------------------
-- 1. Staleness setting on members
-- DEFAULT: staleness OFF so existing members are unaffected.
-- periods/unit default to the design window (two complete quarters) for when
-- a member later enables staleness without choosing a custom window.
-- synced_at / source_device_id unlock the same dirty / watermark sync path
-- used by sessions and other member-owned rows.
-- ---------------------------------------------------------------------------

alter table members
    add column if not exists staleness_enabled boolean not null default false,
    add column if not exists staleness_periods integer not null default 2,
    add column if not exists staleness_unit text not null default 'quarter',
    add column if not exists synced_at timestamptz,
    add column if not exists source_device_id uuid;

alter table members
    drop constraint if exists members_staleness_unit_check;

alter table members
    add constraint members_staleness_unit_check
    check (staleness_unit in ('quarter', 'month'));

alter table members
    drop constraint if exists members_staleness_periods_check;

alter table members
    add constraint members_staleness_periods_check
    check (staleness_periods >= 1);

-- Authenticated clients may UPDATE their own member row (staleness settings)
-- via members_update_own (existing). They must NOT INSERT members — create-
-- or-adopt is broker/service_role only. A device-minted row without
-- teamup_customer_id would be a shadow identity no second device can adopt.

-- ---------------------------------------------------------------------------
-- 2. exercise_resets — one reset_at date per member-exercise
--
-- Dedicated table (not a column on personal_bests / sets) because:
--   - sparse: most member-exercise pairs never have a reset
--   - orthogonal to records (reset is a line, not a flag on rows)
--   - undo = soft-delete (or clear) without touching history rows
--   - syncable as its own member-owned entity (sessions pattern)
-- Unique (member_id, exercise_id) keeps the “one line” invariant; later
-- resets overwrite reset_at on the same row (monotonic by convention).
-- ---------------------------------------------------------------------------

create table if not exists exercise_resets (
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

create index if not exists idx_exercise_resets_member
    on exercise_resets(member_id)
    where deleted_at is null;

create index if not exists idx_exercise_resets_gym
    on exercise_resets(gym_id)
    where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 3. RLS — same ownership model as sessions (direct member_id + gym_id)
-- ---------------------------------------------------------------------------

alter table exercise_resets enable row level security;

create policy exercise_resets_read on exercise_resets
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'role') in ('coach','owner')
            or member_id = (auth.jwt() ->> 'member_id')::uuid
        )
    );

create policy exercise_resets_insert_own on exercise_resets
    for insert
    with check (
        member_id = (auth.jwt() ->> 'member_id')::uuid
        and gym_id = (auth.jwt() ->> 'gym_id')::uuid
    );

create policy exercise_resets_update_own on exercise_resets
    for update
    using (
        member_id = (auth.jwt() ->> 'member_id')::uuid
        and gym_id = (auth.jwt() ->> 'gym_id')::uuid
    )
    with check (
        member_id = (auth.jwt() ->> 'member_id')::uuid
        and gym_id = (auth.jwt() ->> 'gym_id')::uuid
    );

-- ---------------------------------------------------------------------------
-- 4. Grants (hosted project locks table exposure by default)
-- ---------------------------------------------------------------------------

grant select, insert, update on public.exercise_resets to service_role;
grant select, insert, update on public.exercise_resets to authenticated;
