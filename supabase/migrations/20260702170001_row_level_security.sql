-- Gym Performance System: row-level security policies
-- Source: docs/supabase-schema-rls.md

alter table gyms              enable row level security;
alter table members           enable row level security;
alter table exercises         enable row level security;
alter table sessions          enable row level security;
alter table exercise_entries  enable row level security;
alter table sets              enable row level security;
alter table personal_bests    enable row level security;

-- gyms
create policy gyms_read on gyms
    for select
    using (id = (auth.jwt() ->> 'gym_id')::uuid);

-- members
create policy members_read on members
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'role') in ('coach','owner')
            or id = (auth.jwt() ->> 'member_id')::uuid
        )
    );

create policy members_update_own on members
    for update
    using (
        id = (auth.jwt() ->> 'member_id')::uuid
        and gym_id = (auth.jwt() ->> 'gym_id')::uuid
    )
    with check (
        id = (auth.jwt() ->> 'member_id')::uuid
        and gym_id = (auth.jwt() ->> 'gym_id')::uuid
    );

-- exercises
create policy exercises_read on exercises
    for select
    using (gym_id = (auth.jwt() ->> 'gym_id')::uuid);

-- sessions
create policy sessions_read on sessions
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'role') in ('coach','owner')
            or member_id = (auth.jwt() ->> 'member_id')::uuid
        )
    );

create policy sessions_insert_own on sessions
    for insert
    with check (
        member_id = (auth.jwt() ->> 'member_id')::uuid
        and gym_id = (auth.jwt() ->> 'gym_id')::uuid
    );

create policy sessions_update_own on sessions
    for update
    using (
        member_id = (auth.jwt() ->> 'member_id')::uuid
        and gym_id = (auth.jwt() ->> 'gym_id')::uuid
    )
    with check (
        member_id = (auth.jwt() ->> 'member_id')::uuid
        and gym_id = (auth.jwt() ->> 'gym_id')::uuid
    );

-- exercise_entries
create policy entries_read on exercise_entries
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'role') in ('coach','owner')
            or exists (
                select 1 from sessions s
                where s.id = exercise_entries.session_id
                  and s.member_id = (auth.jwt() ->> 'member_id')::uuid
            )
        )
    );

create policy entries_insert_own on exercise_entries
    for insert
    with check (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and exists (
            select 1 from sessions s
            where s.id = exercise_entries.session_id
              and s.member_id = (auth.jwt() ->> 'member_id')::uuid
        )
    );

create policy entries_update_own on exercise_entries
    for update
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and exists (
            select 1 from sessions s
            where s.id = exercise_entries.session_id
              and s.member_id = (auth.jwt() ->> 'member_id')::uuid
        )
    );

-- sets
create policy sets_read on sets
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'role') in ('coach','owner')
            or exists (
                select 1
                from exercise_entries e
                join sessions s on s.id = e.session_id
                where e.id = sets.exercise_entry_id
                  and s.member_id = (auth.jwt() ->> 'member_id')::uuid
            )
        )
    );

create policy sets_insert_own on sets
    for insert
    with check (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and exists (
            select 1
            from exercise_entries e
            join sessions s on s.id = e.session_id
            where e.id = sets.exercise_entry_id
              and s.member_id = (auth.jwt() ->> 'member_id')::uuid
        )
    );

create policy sets_update_own on sets
    for update
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and exists (
            select 1
            from exercise_entries e
            join sessions s on s.id = e.session_id
            where e.id = sets.exercise_entry_id
              and s.member_id = (auth.jwt() ->> 'member_id')::uuid
        )
    );

-- personal_bests
create policy pb_read on personal_bests
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'role') in ('coach','owner')
            or member_id = (auth.jwt() ->> 'member_id')::uuid
        )
    );

create policy pb_insert_own on personal_bests
    for insert
    with check (
        member_id = (auth.jwt() ->> 'member_id')::uuid
        and gym_id = (auth.jwt() ->> 'gym_id')::uuid
    );

create policy pb_update_own on personal_bests
    for update
    using (
        member_id = (auth.jwt() ->> 'member_id')::uuid
        and gym_id = (auth.jwt() ->> 'gym_id')::uuid
    )
    with check (
        member_id = (auth.jwt() ->> 'member_id')::uuid
        and gym_id = (auth.jwt() ->> 'gym_id')::uuid
    );
