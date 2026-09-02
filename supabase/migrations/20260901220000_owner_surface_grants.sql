-- Owner-surface access grant.
--
-- Training tables already allow coach/owner gym-wide SELECT
-- (`app_role` in ('coach','owner') on members/sessions/sets/personal_bests/
-- exercise_resets). That is necessary source access for derivation, but it
-- is not an owner-only endpoint gate: a member JWT still SELECTs their own
-- rows, so an owner-facing function would succeed with a self-only payload
-- instead of being refused.
--
-- This table is the ResourceAccess check for owner-only endpoints.
-- One row per gym. SELECT succeeds only when:
--   gym_id matches the JWT AND app_role = 'owner'
-- Members and coaches see zero rows. Edge Functions must not re-check
-- app_role in application code; they query this table under the user JWT
-- and treat an empty result as forbidden.

create table owner_surface_grants (
    gym_id uuid primary key references gyms(id)
);

alter table owner_surface_grants enable row level security;

create policy owner_surface_grants_read on owner_surface_grants
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (auth.jwt() ->> 'app_role') = 'owner'
    );

grant select on public.owner_surface_grants to authenticated;
grant select, insert, update on public.owner_surface_grants to service_role;

insert into owner_surface_grants (gym_id)
select id from gyms
on conflict (gym_id) do nothing;

create or replace function public.owner_surface_grants_on_gym_insert()
returns trigger
language plpgsql
as $$
begin
    insert into owner_surface_grants (gym_id)
    values (new.id)
    on conflict (gym_id) do nothing;
    return new;
end;
$$;

create trigger owner_surface_grants_on_gym_insert
    after insert on gyms
    for each row
    execute procedure public.owner_surface_grants_on_gym_insert();
