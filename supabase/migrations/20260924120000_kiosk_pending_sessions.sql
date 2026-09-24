-- Kiosk logs that have not been confirmed.
--
-- These rows are not sessions. Board, progression, PB derivation, sync,
-- and the owner surface read sessions / exercise_entries / sets (and views
-- of those). They do not read this table, so an unconfirmed kiosk log is
-- invisible without every reader remembering a status flag.
--
-- Confirm copies one normal session into the live tables and deletes the
-- pending row, in this function, in one transaction. There is no expires_at
-- and no status column. An unconfirmed row stays until that click.

create table public.kiosk_pending_sessions (
    id               uuid primary key default gen_random_uuid(),
    gym_id           uuid not null references public.gyms(id),
    member_id        uuid not null references public.members(id),
    session_date     date not null,
    notes            text,
    calories_burned  integer,
    payload          jsonb not null,
    token_hash       text not null,
    created_at       timestamptz not null default now(),
    constraint kiosk_pending_sessions_token_hash_key unique (token_hash)
);

comment on table public.kiosk_pending_sessions is
    'Unconfirmed kiosk logs. Not a session. Live readers never query this table. commit_kiosk_pending copies one normal session and deletes the row. No expiry.';

comment on column public.kiosk_pending_sessions.token_hash is
    'SHA-256 hex of the confirm-link token. The raw token exists only in the email. No expiry.';

comment on column public.kiosk_pending_sessions.payload is
    'Exercises and exactly one set each, same shape log_session_atomic writes. Ids are assigned at submit.';

create index kiosk_pending_sessions_member
    on public.kiosk_pending_sessions (member_id);

alter table public.kiosk_pending_sessions enable row level security;

-- No select policy. Live readers and the owner JWT cannot list pending rows.
-- Owners may insert and delete rows for their own gym so the kiosk web app
-- can store a pending log with the same session it uses to read members.
-- service_role bypasses RLS.
revoke all on public.kiosk_pending_sessions from public;
revoke all on public.kiosk_pending_sessions from anon;
revoke all on public.kiosk_pending_sessions from authenticated;
grant select, insert, update, delete on public.kiosk_pending_sessions to service_role;
grant insert, delete on public.kiosk_pending_sessions to authenticated;

create policy kiosk_pending_owner_insert on public.kiosk_pending_sessions
    for insert
    to authenticated
    with check (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (auth.jwt() ->> 'app_role') = 'owner'
    );

create policy kiosk_pending_owner_delete on public.kiosk_pending_sessions
    for delete
    to authenticated
    using (
        gym_id = (auth.jwt() ->> 'gym_id')::uuid
        and (auth.jwt() ->> 'app_role') = 'owner'
    );

create or replace function public.commit_kiosk_pending(p_token_hash text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  pending public.kiosk_pending_sessions%rowtype;
  member_row public.members%rowtype;
  exercises jsonb;
  exercise_count integer;
  exercise_index integer;
  exercise_item jsonb;
  exercise_id uuid;
  entry_id uuid;
  exercise_row public.exercises%rowtype;
  sets_json jsonb;
  set_count integer;
  set_item jsonb;
  set_id uuid;
  session_id uuid;
  write_at timestamptz := now();
begin
  if p_token_hash is null or length(p_token_hash) = 0 then
    raise exception 'Pending log not found' using errcode = 'PT404';
  end if;

  select * into pending
  from public.kiosk_pending_sessions
  where token_hash = p_token_hash
  for update;

  if not found then
    raise exception 'Pending log not found' using errcode = 'PT404';
  end if;

  select * into member_row
  from public.members
  where id = pending.member_id
    and gym_id = pending.gym_id
    and deleted_at is null;

  if not found then
    raise exception 'Member not found' using errcode = 'PT404';
  end if;

  exercises := pending.payload -> 'exercises';
  if jsonb_typeof(exercises) is distinct from 'array' then
    raise exception 'Invalid pending payload' using errcode = 'PT400';
  end if;

  exercise_count := jsonb_array_length(exercises);
  if exercise_count < 1 then
    raise exception 'At least one exercise is required' using errcode = 'PT400';
  end if;

  begin
    session_id := (pending.payload ->> 'sessionId')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'Invalid session id' using errcode = 'PT400';
  end;
  if session_id is null then
    raise exception 'Invalid session id' using errcode = 'PT400';
  end if;

  insert into public.sessions (
    id, gym_id, member_id, date, notes, calories_burned, updated_at, synced_at
  )
  values (
    session_id,
    pending.gym_id,
    pending.member_id,
    pending.session_date,
    pending.notes,
    pending.calories_burned,
    write_at,
    write_at
  );

  for exercise_index in 0 .. exercise_count - 1 loop
    exercise_item := exercises -> exercise_index;
    if jsonb_typeof(exercise_item) is distinct from 'object' then
      raise exception 'Invalid exercise' using errcode = 'PT400';
    end if;

    begin
      exercise_id := (exercise_item ->> 'exerciseId')::uuid;
      entry_id := (exercise_item ->> 'exerciseEntryId')::uuid;
    exception
      when invalid_text_representation then
        raise exception 'Invalid exerciseId' using errcode = 'PT400';
    end;
    if exercise_id is null or entry_id is null then
      raise exception 'Invalid exerciseId' using errcode = 'PT400';
    end if;

    select * into exercise_row
    from public.exercises
    where id = exercise_id
      and deleted_at is null;

    if not found then
      raise exception 'Exercise not found' using errcode = 'PT404';
    end if;
    if exercise_row.gym_id is distinct from pending.gym_id then
      raise exception 'Exercise not in member gym' using errcode = 'PT403';
    end if;
    if not exercise_row.is_active then
      raise exception 'Exercise is not active' using errcode = 'PT400';
    end if;

    sets_json := exercise_item -> 'sets';
    if jsonb_typeof(sets_json) is distinct from 'array' then
      raise exception 'Each exercise must include exactly one set' using errcode = 'PT400';
    end if;
    set_count := jsonb_array_length(sets_json);
    if set_count <> 1 then
      raise exception 'Each exercise must include exactly one set' using errcode = 'PT400';
    end if;

    set_item := sets_json -> 0;
    if jsonb_typeof(set_item) is distinct from 'object' then
      raise exception 'Invalid set' using errcode = 'PT400';
    end if;

    begin
      set_id := (set_item ->> 'id')::uuid;
    exception
      when invalid_text_representation then
        raise exception 'Invalid set id' using errcode = 'PT400';
    end;
    if set_id is null then
      raise exception 'Invalid set id' using errcode = 'PT400';
    end if;

    insert into public.exercise_entries (
      id, gym_id, session_id, exercise_id, updated_at, synced_at
    )
    values (
      entry_id, pending.gym_id, session_id, exercise_id, write_at, write_at
    );

    insert into public.sets (
      id,
      gym_id,
      exercise_entry_id,
      weight,
      reps,
      time_seconds,
      distance,
      updated_at,
      synced_at
    )
    values (
      set_id,
      pending.gym_id,
      entry_id,
      case
        when jsonb_typeof(set_item -> 'weight') = 'number'
          then (set_item ->> 'weight')::double precision
        else null
      end,
      case
        when jsonb_typeof(set_item -> 'reps') = 'number'
          then round((set_item ->> 'reps')::numeric)::integer
        else null
      end,
      case
        when jsonb_typeof(set_item -> 'time_seconds') = 'number'
          then (set_item ->> 'time_seconds')::double precision
        else null
      end,
      case
        when jsonb_typeof(set_item -> 'distance') = 'number'
          then (set_item ->> 'distance')::double precision
        else null
      end,
      write_at,
      write_at
    );
  end loop;

  delete from public.kiosk_pending_sessions where id = pending.id;

  return jsonb_build_object(
    'sessionId', session_id,
    'memberId', pending.member_id,
    'date', pending.session_date
  );
end;
$$;

revoke all on function public.commit_kiosk_pending(text) from public;
grant execute on function public.commit_kiosk_pending(text) to anon, authenticated, service_role;

comment on function public.commit_kiosk_pending(text) is
    'Turns one kiosk_pending_sessions row into a normal session, entries, and sets, then deletes the pending row. Does not consult created_at. No expiry.';
