-- Only the member the pending log belongs to may commit it.
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

  if (auth.jwt() ->> 'member_id') is distinct from pending.member_id::text then
    raise exception 'Sign in on the member app to confirm this session' using errcode = 'PT403';
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
revoke all on function public.commit_kiosk_pending(text) from anon;
grant execute on function public.commit_kiosk_pending(text) to authenticated;;
