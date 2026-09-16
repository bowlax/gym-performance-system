-- Atomic session save (#23)
--
-- One Postgres function writes the session, every exercise entry, and every
-- set in a single transaction. Any validation or insert failure rolls the
-- whole save back. Session-derived PBs are still derived at read time (#28);
-- this function does not insert personal_bests.
--
-- SECURITY INVOKER so existing RLS policies apply. JWT member_id / gym_id
-- are taken from auth.jwt(), never from the payload.

create or replace function public.log_session_atomic(payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  jwt_member_id uuid;
  jwt_gym_id uuid;
  session_obj jsonb;
  exercises jsonb;
  session_id uuid;
  session_date date;
  session_notes text;
  session_calories integer;
  existing_session public.sessions%rowtype;
  exercise_count integer;
  exercise_index integer;
  exercise_item jsonb;
  exercise_id uuid;
  entry_id uuid;
  exercise_row public.exercises%rowtype;
  existing_entry public.exercise_entries%rowtype;
  sets_json jsonb;
  set_count integer;
  set_index integer;
  set_item jsonb;
  set_id uuid;
  existing_set public.sets%rowtype;
  result_exercises jsonb := '[]'::jsonb;
  result_sets jsonb;
begin
  jwt_member_id := nullif(auth.jwt() ->> 'member_id', '')::uuid;
  jwt_gym_id := nullif(auth.jwt() ->> 'gym_id', '')::uuid;
  if jwt_member_id is null or jwt_gym_id is null then
    raise exception 'Unauthorized' using errcode = 'PT401';
  end if;

  if jsonb_typeof(payload) is distinct from 'object' then
    raise exception 'Invalid request body. Provide session and exercises.' using errcode = 'PT400';
  end if;

  session_obj := payload -> 'session';
  exercises := payload -> 'exercises';

  if jsonb_typeof(session_obj) is distinct from 'object' then
    raise exception 'Invalid request body. Provide session and exercises.' using errcode = 'PT400';
  end if;

  if jsonb_typeof(exercises) is distinct from 'array' then
    raise exception 'Invalid request body. Provide session and exercises.' using errcode = 'PT400';
  end if;

  exercise_count := jsonb_array_length(exercises);
  if exercise_count < 1 then
    raise exception 'At least one exercise is required' using errcode = 'PT400';
  end if;

  begin
    if session_obj ->> 'id' is null or session_obj ->> 'id' = '' then
      session_id := gen_random_uuid();
    else
      session_id := (session_obj ->> 'id')::uuid;
    end if;
  exception
    when invalid_text_representation then
      raise exception 'Invalid session id' using errcode = 'PT400';
  end;

  begin
    session_date := (session_obj ->> 'date')::date;
  exception
    when others then
      raise exception 'Invalid session date' using errcode = 'PT400';
  end;

  if session_date is null then
    raise exception 'Invalid session date' using errcode = 'PT400';
  end if;

  if session_obj ->> 'notes' is null or jsonb_typeof(session_obj -> 'notes') = 'null' then
    session_notes := null;
  else
    session_notes := session_obj ->> 'notes';
  end if;

  if jsonb_typeof(session_obj -> 'calories_burned') = 'number' then
    session_calories := round((session_obj ->> 'calories_burned')::numeric)::integer;
  else
    session_calories := null;
  end if;

  begin
    insert into public.sessions (id, gym_id, member_id, date, notes, calories_burned)
    values (
      session_id,
      jwt_gym_id,
      jwt_member_id,
      session_date,
      session_notes,
      session_calories
    )
    on conflict (id) do nothing;
  exception
    when unique_violation then
      raise exception 'Conflict' using errcode = 'PT409';
  end;

  select * into existing_session from public.sessions where id = session_id;
  if not found then
    raise exception 'Session not found' using errcode = 'PT404';
  end if;
  if existing_session.member_id is distinct from jwt_member_id
     or existing_session.gym_id is distinct from jwt_gym_id then
    raise exception 'Forbidden' using errcode = 'PT403';
  end if;
  if existing_session.deleted_at is not null then
    raise exception 'Session not found' using errcode = 'PT404';
  end if;

  for exercise_index in 0 .. exercise_count - 1 loop
    exercise_item := exercises -> exercise_index;
    if jsonb_typeof(exercise_item) is distinct from 'object' then
      raise exception 'Invalid exercise' using errcode = 'PT400';
    end if;

    begin
      exercise_id := (exercise_item ->> 'exerciseId')::uuid;
    exception
      when invalid_text_representation then
        raise exception 'Invalid exerciseId' using errcode = 'PT400';
    end;
    if exercise_id is null then
      raise exception 'Invalid exerciseId' using errcode = 'PT400';
    end if;

    begin
      if exercise_item ->> 'exerciseEntryId' is null
         or exercise_item ->> 'exerciseEntryId' = '' then
        entry_id := gen_random_uuid();
      else
        entry_id := (exercise_item ->> 'exerciseEntryId')::uuid;
      end if;
    exception
      when invalid_text_representation then
        raise exception 'Invalid exerciseEntryId' using errcode = 'PT400';
    end;

    select * into exercise_row
    from public.exercises
    where id = exercise_id
      and deleted_at is null;

    if not found then
      raise exception 'Exercise not found' using errcode = 'PT404';
    end if;
    if exercise_row.gym_id is distinct from jwt_gym_id then
      raise exception 'Exercise not in member gym' using errcode = 'PT403';
    end if;
    if not exercise_row.is_active then
      raise exception 'Exercise is not active' using errcode = 'PT400';
    end if;

    sets_json := exercise_item -> 'sets';
    if jsonb_typeof(sets_json) is distinct from 'array' then
      raise exception 'Each exercise must include at least one set' using errcode = 'PT400';
    end if;
    set_count := jsonb_array_length(sets_json);
    if set_count < 1 then
      raise exception 'Each exercise must include at least one set' using errcode = 'PT400';
    end if;

    begin
      insert into public.exercise_entries (id, gym_id, session_id, exercise_id)
      values (entry_id, jwt_gym_id, session_id, exercise_id)
      on conflict (id) do nothing;
    exception
      when unique_violation then
        raise exception 'Conflict' using errcode = 'PT409';
    end;

    select * into existing_entry from public.exercise_entries where id = entry_id;
    if not found then
      raise exception 'Exercise entry not found' using errcode = 'PT404';
    end if;
    if existing_entry.deleted_at is not null
       or existing_entry.session_id is distinct from session_id
       or existing_entry.exercise_id is distinct from exercise_id
       or existing_entry.gym_id is distinct from jwt_gym_id then
      raise exception 'Exercise entry mismatch' using errcode = 'PT409';
    end if;

    result_sets := '[]'::jsonb;

    for set_index in 0 .. set_count - 1 loop
      set_item := sets_json -> set_index;
      if jsonb_typeof(set_item) is distinct from 'object' then
        raise exception 'Invalid set' using errcode = 'PT400';
      end if;

      begin
        if set_item ->> 'id' is null or set_item ->> 'id' = '' then
          set_id := gen_random_uuid();
        else
          set_id := (set_item ->> 'id')::uuid;
        end if;
      exception
        when invalid_text_representation then
          raise exception 'Invalid set id' using errcode = 'PT400';
      end;

      begin
        insert into public.sets (
          id,
          gym_id,
          exercise_entry_id,
          weight,
          reps,
          time_seconds,
          distance
        )
        values (
          set_id,
          jwt_gym_id,
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
          end
        )
        on conflict (id) do nothing;
      exception
        when unique_violation then
          raise exception 'Conflict' using errcode = 'PT409';
      end;

      select * into existing_set from public.sets where id = set_id;
      if not found then
        raise exception 'Set not found' using errcode = 'PT404';
      end if;
      if existing_set.deleted_at is not null
         or existing_set.exercise_entry_id is distinct from entry_id
         or existing_set.gym_id is distinct from jwt_gym_id then
        raise exception 'Set mismatch' using errcode = 'PT409';
      end if;

      result_sets := result_sets || jsonb_build_array(
        jsonb_build_object(
          'id', existing_set.id,
          'gym_id', existing_set.gym_id,
          'exercise_entry_id', existing_set.exercise_entry_id,
          'weight', existing_set.weight,
          'reps', existing_set.reps,
          'time_seconds', existing_set.time_seconds,
          'distance', existing_set.distance,
          'created_at', existing_set.created_at,
          'updated_at', existing_set.updated_at
        )
      );
    end loop;

    result_exercises := result_exercises || jsonb_build_array(
      jsonb_build_object(
        'exerciseId', exercise_id,
        'exerciseEntryId', existing_entry.id,
        'sets', result_sets
      )
    );
  end loop;

  return jsonb_build_object(
    'session', jsonb_build_object(
      'id', existing_session.id,
      'date', existing_session.date,
      'notes', existing_session.notes,
      'calories_burned', existing_session.calories_burned
    ),
    'exercises', result_exercises
  );
end;
$$;

revoke all on function public.log_session_atomic(jsonb) from public;
revoke all on function public.log_session_atomic(jsonb) from anon;
grant execute on function public.log_session_atomic(jsonb) to authenticated;
