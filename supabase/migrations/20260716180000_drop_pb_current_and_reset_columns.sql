-- Issue #28 STEP 4: burn is_current / was_reset. Derivation is the only path.
-- Does NOT migrate was_reset rows into exercise_resets (deliberate — see #28).

drop index if exists idx_pb_current;

alter table personal_bests
    drop column if exists is_current,
    drop column if exists was_reset;
