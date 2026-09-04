-- Add sessions.calories_burned to owner_session_activity.
-- Column already exists and is synced; the view omitted it.
-- CREATE OR REPLACE may only append columns; calories_burned is last.

create or replace view public.owner_session_activity
    with (security_invoker = true, security_barrier = true)
as
select
    s.id as session_id,
    s.gym_id,
    s.member_id,
    m.teamup_customer_id,
    s.date as session_date,
    s.calories_burned
from public.sessions s
join public.members m
    on m.id = s.member_id
    and m.deleted_at is null
join public.owner_surface_grants g
    on g.gym_id = s.gym_id
where s.deleted_at is null
  and s.gym_id = (auth.jwt() ->> 'gym_id')::uuid
  and (auth.jwt() ->> 'app_role') = 'owner';

comment on view public.owner_session_activity is
    'Owner-only raw session facts. security_invoker + owner_surface_grants. No derivation, no names.';

notify pgrst, 'reload schema';
