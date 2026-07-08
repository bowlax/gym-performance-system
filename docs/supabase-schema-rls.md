# Row-Level Security Policies -- Gym Performance System

**To be appended to supabase-schema.md**

These policies enforce the phase 2 access model. They read claims from the Supabase JWT
minted by the token broker Edge Function: member_id, gym_id, role.

> Note: these policies assume the JWT custom claims are accessible via
> auth.jwt() ->> 'claim_name'. The exact claim path depends on how the broker
> structures the JWT. Adjust the claim extraction to match the broker implementation.

---

## Helper expressions

Throughout, these expressions read the JWT claims:

- Current gym:    (auth.jwt() ->> 'gym_id')::uuid
- Current member: (auth.jwt() ->> 'member_id')::uuid
- App role:       (auth.jwt() ->> 'app_role')   -- member | coach | owner

The JWT `role` claim is reserved for PostgREST (`authenticated`). The token broker
sets `role: "authenticated"` and puts the app role in `app_role`.

---

## Enable RLS on all tables

```sql
alter table gyms              enable row level security;
alter table members           enable row level security;
alter table exercises         enable row level security;
alter table sessions          enable row level security;
alter table exercise_entries  enable row level security;
alter table sets              enable row level security;
alter table personal_bests    enable row level security;
```

---

## gyms

Members and staff can read their own gym. No writes via normal roles.

```sql
create policy gyms_read on gyms
    for select
    using (id = (auth.jwt() ->> 'gym_id')::uuid);
```

---

## members

A member can read and update their own record. Coaches and owners can read all
members in their gym. Inserts happen via the token broker (service role), not normal roles.

```sql
-- Member reads own record; coach/owner read all in gym
create policy members_read on members
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'app_role') in ('coach','owner')
            or id = (auth.jwt() ->> 'member_id')::uuid
        )
    );

-- Member updates own record only (e.g. display_name, sync_enabled)
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
```

---

## exercises

All authenticated users in a gym can read that gym's exercises. Writes are
administrative (service role / seeding), not exposed to normal roles.

```sql
create policy exercises_read on exercises
    for select
    using (gym_id = (auth.jwt() ->> 'gym_id')::uuid);
```

---

## sessions

Members read and write their own. Coaches and owners read all in gym, no writes.

```sql
-- Read: own if member, all in gym if coach/owner
create policy sessions_read on sessions
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'app_role') in ('coach','owner')
            or member_id = (auth.jwt() ->> 'member_id')::uuid
        )
    );

-- Insert: members only, own rows, own gym
create policy sessions_insert_own on sessions
    for insert
    with check (
        member_id = (auth.jwt() ->> 'member_id')::uuid
        and gym_id = (auth.jwt() ->> 'gym_id')::uuid
    );

-- Update: members only, own rows (includes soft-delete via deleted_at)
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

-- No delete policy: hard-delete not exposed to normal roles (GDPR is privileged)
```

---

## exercise_entries

Owned via session. Member access derived through the parent session's member_id,
denormalised onto the row (gym_id present; member linkage through session).
Because entries carry no member_id, we join to sessions for the ownership check.

```sql
-- Read: coach/owner all in gym; member only entries whose session they own
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

-- Insert: member, into a session they own
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

-- Update: member, entries in a session they own
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
```

---

## sets

Owned via exercise_entry -> session. Ownership check joins up the chain.

```sql
-- Read
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

-- Insert
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

-- Update
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
```

---

## personal_bests

Members carry member_id directly, so checks are simpler.

```sql
-- Read: coach/owner all in gym; member own
create policy pb_read on personal_bests
    for select
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (
            (auth.jwt() ->> 'app_role') in ('coach','owner')
            or member_id = (auth.jwt() ->> 'member_id')::uuid
        )
    );

-- Insert: member own
create policy pb_insert_own on personal_bests
    for insert
    with check (
        member_id = (auth.jwt() ->> 'member_id')::uuid
        and gym_id = (auth.jwt() ->> 'gym_id')::uuid
    );

-- Update: member own (includes is_current changes, reset, soft-delete)
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
```

---

## Notes on the policy design

1. **No delete policies anywhere.** Hard-delete is never exposed to member, coach, or
   owner roles. Normal "deletion" is soft-delete via updating deleted_at, covered by the
   update policies. GDPR hard-erasure runs via the service role (privileged), outside RLS.

2. **Coaches and owners are read-only on performance data.** They have select but no
   insert/update/delete on sessions, entries, sets, and personal_bests. Their write
   capabilities (commentary, goals) come with later phase 2 coach features and their own tables.

3. **The service role bypasses RLS.** The token broker Edge Function and administrative
   operations use the Supabase service role, which is not subject to these policies. This is
   where member creation (create-or-adopt) and GDPR hard-delete happen.

4. **gym_id is checked in every policy.** No cross-gym access is possible under any role.
   This is the multi-gym isolation guarantee, enforced even though only one gym exists today.

5. **Soft-deleted rows remain readable** by these policies (no deleted_at filter in the
   using clause) because sync needs to see deletions to propagate them. Application queries
   filter deleted_at is null for normal display; the indexes already reflect this.
