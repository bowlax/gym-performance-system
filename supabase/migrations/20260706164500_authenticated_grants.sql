-- authenticated role table grants
--
-- The hosted project disables automatic table exposure. service_role was granted
-- explicitly for the token broker; member-scoped clients (JWT + RLS) use the
-- authenticated role and need the same base privileges. RLS policies restrict
-- which rows each member can touch.
--
-- DELETE is deliberately excluded (same rationale as service_role_grants).

grant select, insert, update on
    public.gyms,
    public.members,
    public.exercises,
    public.sessions,
    public.exercise_entries,
    public.sets,
    public.personal_bests
to authenticated;
