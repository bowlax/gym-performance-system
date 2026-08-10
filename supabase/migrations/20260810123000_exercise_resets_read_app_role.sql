-- #40: exercise_resets_read must use app_role, not role.
--
-- PostgREST reserves JWT claim `role` for the Postgres session role
-- (`authenticated`). Product roles (member/coach/owner) live in `app_role`
-- (design §18; same fix as 20260706170000 for other tables). The original
-- exercise_resets policy in 20260715180000 incorrectly checked `role`, so the
-- coach/owner OR branch never matched under Auth-session JWTs.

drop policy if exists exercise_resets_read on exercise_resets;

create policy exercise_resets_read on exercise_resets
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'app_role') in ('coach','owner')
            or member_id = (auth.jwt() ->> 'member_id')::uuid
        )
    );
