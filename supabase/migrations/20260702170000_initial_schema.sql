-- Gym Performance System: initial schema
-- Source: docs/supabase-schema.md

create table gyms (
    id                  uuid primary key default gen_random_uuid(),
    teamup_provider_id  text unique not null,
    name                text not null,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz
);

create table members (
    id                  uuid primary key,
    gym_id              uuid not null references gyms(id),
    teamup_customer_id  text,
    display_name        text not null default 'Member',
    sync_enabled        boolean not null default true,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz,
    unique (gym_id, teamup_customer_id)
);

create table exercises (
    id                  uuid primary key default gen_random_uuid(),
    gym_id              uuid not null references gyms(id),
    name                text not null,
    category            text not null,
    measurement_type    text not null,
    pb_rule             text,
    target_reps         integer,
    minimum_reps        integer,
    parent_exercise_id  uuid references exercises(id),
    display_order       integer not null,
    is_active           boolean not null default true,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz
);

create table sessions (
    id                  uuid primary key,
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

create table sets (
    id                  uuid primary key,
    gym_id              uuid not null references gyms(id),
    exercise_entry_id   uuid not null references exercise_entries(id),
    weight              double precision,
    reps                integer,
    time_seconds        double precision,
    distance            double precision,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz,
    synced_at           timestamptz,
    source_device_id    uuid
);

create table personal_bests (
    id                  uuid primary key,
    gym_id              uuid not null references gyms(id),
    member_id           uuid not null references members(id),
    exercise_id         uuid not null references exercises(id),
    set_id              uuid references sets(id),
    weight              double precision,
    reps                integer,
    time_seconds        double precision,
    distance            double precision,
    achieved_at         date not null,
    is_current          boolean not null default true,
    entry_type          text not null default 'sessionDerived',
    was_reset           boolean not null default false,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz,
    synced_at           timestamptz,
    source_device_id    uuid
);

-- Indexes
create index idx_members_gym on members(gym_id);
create index idx_members_teamup on members(gym_id, teamup_customer_id);

create index idx_sessions_member on sessions(member_id) where deleted_at is null;
create index idx_sessions_gym on sessions(gym_id) where deleted_at is null;
create index idx_sessions_date on sessions(member_id, date) where deleted_at is null;

create index idx_entries_session on exercise_entries(session_id) where deleted_at is null;
create index idx_sets_entry on sets(exercise_entry_id) where deleted_at is null;

create index idx_pb_current on personal_bests(member_id, exercise_id) where is_current = true and deleted_at is null;
create index idx_pb_member on personal_bests(member_id) where deleted_at is null;
create index idx_pb_gym on personal_bests(gym_id) where deleted_at is null;

create index idx_exercises_gym on exercises(gym_id) where deleted_at is null;
