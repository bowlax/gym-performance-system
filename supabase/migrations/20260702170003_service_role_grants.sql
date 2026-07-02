-- service_role table grants
--
-- The hosted project was created with locked-down defaults (automatic table
-- exposure disabled), so service_role requires explicit table privileges for
-- the token broker and other administrative operations that bypass RLS.
--
-- DELETE is deliberately excluded: hard delete is a privileged GDPR-only
-- operation and should be granted separately if needed.

grant select, insert, update on
    public.gyms,
    public.members,
    public.exercises,
    public.sessions,
    public.exercise_entries,
    public.sets,
    public.personal_bests
to service_role;
