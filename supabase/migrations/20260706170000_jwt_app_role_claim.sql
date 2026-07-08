-- JWT app_role claim
--
-- PostgREST uses the JWT "role" claim as the Postgres session role (authenticated,
-- anon, service_role). App roles (member, coach, owner) must live in a separate
-- claim. Policies that gate coach/owner read access now read app_role.

drop policy members_read on members;
create policy members_read on members
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'app_role') in ('coach','owner')
            or id = (auth.jwt() ->> 'member_id')::uuid
        )
    );

drop policy sessions_read on sessions;
create policy sessions_read on sessions
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'app_role') in ('coach','owner')
            or member_id = (auth.jwt() ->> 'member_id')::uuid
        )
    );

drop policy entries_read on exercise_entries;
create policy entries_read on exercise_entries
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'app_role') in ('coach','owner')
            or exists (
                select 1 from sessions s
                where s.id = exercise_entries.session_id
                  and s.member_id = (auth.jwt() ->> 'member_id')::uuid
            )
        )
    );

drop policy sets_read on sets;
create policy sets_read on sets
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'app_role') in ('coach','owner')
            or exists (
                select 1
                from exercise_entries e
                join sessions s on s.id = e.session_id
                where e.id = sets.exercise_entry_id
                  and s.member_id = (auth.jwt() ->> 'member_id')::uuid
            )
        )
    );

drop policy pb_read on personal_bests;
create policy pb_read on personal_bests
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'app_role') in ('coach','owner')
            or member_id = (auth.jwt() ->> 'member_id')::uuid
        )
    );
