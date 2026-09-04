-- Owner-surface raw-fact views (no PB derivation).
--
-- Steve's discovery questions that are answerable from raw rows alone:
--   1. who trained, when, how often  -> owner_session_activity
--   2. what was logged (exercise, weight, reps, date) -> owner_set_detail
--   3. exercise names/ids for joining -> owner_exercise_catalogue
--
-- Identity is member_id + teamup_customer_id only. Names are resolved
-- separately (owner-member-names). These views never call TeamUp.
--
-- No owner-member-exercise-history Edge Function: a history chart is a
-- filtered read of owner_set_detail. "When was the current PB set / has
-- it lapsed" is a filtered read of owner-current-pbs (derivation already
-- lives there). A scoped single-member-single-exercise endpoint would not
-- be a new capability.
--
-- Access: security_invoker (NOT the Postgres default security_definer).
-- Justification:
--   Default views run as the view owner and bypass RLS on the base
--   tables. A missed predicate would then leak gym-wide training rows
--   through PostgREST. security_invoker keeps table RLS as a floor.
--
--   Table RLS is not enough on its own for this surface: members still
--   SELECT their own sessions/sets, and coaches SELECT gym-wide. The
--   owner-only gate is the same owner_surface_grants check already
--   proven for the Edge Functions (app_role = 'owner' AND gym_id match).
--   Each view INNER JOINs that table so members/coaches get zero rows
--   even though they can read the underlying training tables. Explicit
--   JWT predicates duplicate that policy so the view cannot widen
--   access if grants RLS is later loosened.
--
-- GRANT SELECT only. The join to a second table also makes these views
-- not auto-updatable, so INSERT/UPDATE/DELETE cannot pass through to
-- the base tables even if a write grant were added by mistake.

create view public.owner_session_activity
    with (security_invoker = true, security_barrier = true)
as
select
    s.id as session_id,
    s.gym_id,
    s.member_id,
    m.teamup_customer_id,
    s.date as session_date
from public.sessions s
join public.members m
    on m.id = s.member_id
    and m.deleted_at is null
join public.owner_surface_grants g
    on g.gym_id = s.gym_id
where s.deleted_at is null
  and s.gym_id = (auth.jwt() ->> 'gym_id')::uuid
  and (auth.jwt() ->> 'app_role') = 'owner';

create view public.owner_set_detail
    with (security_invoker = true, security_barrier = true)
as
select
    st.id as set_id,
    s.id as session_id,
    st.gym_id,
    s.member_id,
    m.teamup_customer_id,
    e.exercise_id,
    s.date as session_date,
    st.weight,
    st.reps,
    st.time_seconds,
    st.distance
from public.sets st
join public.exercise_entries e
    on e.id = st.exercise_entry_id
    and e.deleted_at is null
join public.sessions s
    on s.id = e.session_id
    and s.deleted_at is null
join public.members m
    on m.id = s.member_id
    and m.deleted_at is null
join public.owner_surface_grants g
    on g.gym_id = st.gym_id
where st.deleted_at is null
  and st.gym_id = (auth.jwt() ->> 'gym_id')::uuid
  and (auth.jwt() ->> 'app_role') = 'owner';

create view public.owner_exercise_catalogue
    with (security_invoker = true, security_barrier = true)
as
select
    e.id as exercise_id,
    e.gym_id,
    e.name,
    e.category,
    e.measurement_type,
    e.pb_rule,
    e.target_reps,
    e.minimum_reps,
    e.parent_exercise_id,
    e.display_order,
    e.is_active
from public.exercises e
join public.owner_surface_grants g
    on g.gym_id = e.gym_id
where e.deleted_at is null
  and e.gym_id = (auth.jwt() ->> 'gym_id')::uuid
  and (auth.jwt() ->> 'app_role') = 'owner';

comment on view public.owner_session_activity is
    'Owner-only raw session facts. security_invoker + owner_surface_grants. No derivation, no names.';

comment on view public.owner_set_detail is
    'Owner-only raw set/exercise facts. security_invoker + owner_surface_grants. No derivation, no names.';

comment on view public.owner_exercise_catalogue is
    'Owner-only exercise id/name catalogue for joining the other owner views. No TeamUp.';

revoke all on table public.owner_session_activity from public, anon, authenticated, service_role;
revoke all on table public.owner_set_detail from public, anon, authenticated, service_role;
revoke all on table public.owner_exercise_catalogue from public, anon, authenticated, service_role;

grant select on table public.owner_session_activity to authenticated, service_role;
grant select on table public.owner_set_detail to authenticated, service_role;
grant select on table public.owner_exercise_catalogue to authenticated, service_role;

notify pgrst, 'reload schema';
