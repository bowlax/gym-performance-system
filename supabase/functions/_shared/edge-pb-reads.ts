/**
 * Edge-function helpers to derive current PB from sets + manual entries (#28 step 4).
 * Mirrors web `derive-pb-reads.ts` for write-time evaluation in add-manual-pb.
 */

import {
  derivePBs,
  type DerivationRecord,
  type StalenessSetting,
} from "./pb-derivation.ts";
import { evaluatePB, type PBRule, type SetState } from "./pb-evaluation.ts";
import type { ExerciseRow, PersonalBestRow, UserClient } from "./member-edge.ts";
import { todayUtcDateString } from "./member-edge.ts";

const MANUAL_ENTRY = "manualEntry";

function mapStalenessUnit(dbUnit: string): StalenessSetting["unit"] {
  return dbUnit === "month" ? "months" : "quarters";
}

export async function fetchMemberStaleness(
  supabase: UserClient,
  memberId: string,
): Promise<StalenessSetting> {
  const { data, error } = await supabase
    .from("members")
    .select("staleness_enabled, staleness_periods, staleness_unit")
    .eq("id", memberId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    return { enabled: false, periods: 2, unit: "quarters" };
  }

  const row = data as Record<string, unknown>;
  return {
    enabled: Boolean(row.staleness_enabled),
    periods:
      typeof row.staleness_periods === "number" && row.staleness_periods >= 1
        ? row.staleness_periods
        : 2,
    unit: mapStalenessUnit(
      typeof row.staleness_unit === "string" ? row.staleness_unit : "quarter",
    ),
  };
}

export async function fetchExerciseResetAt(
  supabase: UserClient,
  memberId: string,
  exerciseId: string,
): Promise<string | null> {
  const { data, error } = await supabase
    .from("exercise_resets")
    .select("reset_at")
    .eq("member_id", memberId)
    .eq("exercise_id", exerciseId)
    .is("deleted_at", null)
    .maybeSingle();

  if (error) {
    throw error;
  }

  const resetAt = (data as { reset_at?: string } | null)?.reset_at;
  return typeof resetAt === "string" ? resetAt : null;
}

interface SetDerivationRow {
  id: string;
  session_date: string;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
}

export async function fetchExerciseSetsForDerivation(
  supabase: UserClient,
  exerciseId: string,
): Promise<SetDerivationRow[]> {
  const { data, error } = await supabase
    .from("exercise_entries")
    .select(
      "session:sessions!inner(date), sets(id, weight, reps, time_seconds, distance, deleted_at)",
    )
    .eq("exercise_id", exerciseId)
    .is("deleted_at", null);

  if (error) {
    throw error;
  }

  const rows: SetDerivationRow[] = [];
  for (const entry of data ?? []) {
    const record = entry as Record<string, unknown>;
    const session = Array.isArray(record.session)
      ? record.session[0]
      : record.session;
    const sessionDate =
      session && typeof (session as Record<string, unknown>).date === "string"
        ? (session as Record<string, unknown>).date as string
        : null;
    if (!sessionDate) continue;

    for (const set of (record.sets ?? []) as Array<Record<string, unknown>>) {
      if (set.deleted_at != null) continue;
      if (typeof set.id !== "string") continue;
      rows.push({
        id: set.id,
        session_date: sessionDate,
        weight: typeof set.weight === "number" ? set.weight : null,
        reps: typeof set.reps === "number" ? set.reps : null,
        time_seconds: typeof set.time_seconds === "number" ? set.time_seconds : null,
        distance: typeof set.distance === "number" ? set.distance : null,
      });
    }
  }

  return rows;
}

export async function fetchManualPBsForDerivation(
  supabase: UserClient,
  memberId: string,
  exerciseId: string,
): Promise<PersonalBestRow[]> {
  const { data, error } = await supabase
    .from("personal_bests")
    .select(
      "id, gym_id, member_id, exercise_id, set_id, weight, reps, time_seconds, distance, achieved_at, entry_type",
    )
    .eq("member_id", memberId)
    .eq("exercise_id", exerciseId)
    .eq("entry_type", MANUAL_ENTRY)
    .is("deleted_at", null);

  if (error) {
    throw error;
  }

  return (data as PersonalBestRow[] | null) ?? [];
}

export function recordsFromStore(
  sets: SetDerivationRow[],
  manuals: PersonalBestRow[],
): DerivationRecord[] {
  const records: DerivationRecord[] = [];

  for (const set of sets) {
    records.push({
      id: set.id,
      achievedAt: set.session_date,
      weight: set.weight,
      reps: set.reps,
      time: set.time_seconds,
      distance: set.distance,
      entryKind: "set",
    });
  }

  for (const pb of manuals) {
    records.push({
      id: pb.id,
      achievedAt: pb.achieved_at,
      weight: pb.weight,
      reps: pb.reps,
      time: pb.time_seconds,
      distance: pb.distance,
      entryKind: "manual",
    });
  }

  return records;
}

export async function deriveCurrentPBState(
  supabase: UserClient,
  memberId: string,
  exercise: ExerciseRow,
): Promise<{
  currentPB: DerivationRecord | null;
  staleness: StalenessSetting;
  resetAt: string | null;
}> {
  if (!exercise.pb_rule) {
    return { currentPB: null, staleness: { enabled: false, periods: 2, unit: "quarters" }, resetAt: null };
  }

  const [staleness, resetAt, sets, manuals] = await Promise.all([
    fetchMemberStaleness(supabase, memberId),
    fetchExerciseResetAt(supabase, memberId, exercise.id),
    fetchExerciseSetsForDerivation(supabase, exercise.id),
    fetchManualPBsForDerivation(supabase, memberId, exercise.id),
  ]);

  const records = recordsFromStore(sets, manuals);
  const derived = derivePBs({
    rule: exercise.pb_rule as PBRule,
    records,
    staleness,
    resetAt,
    evaluatedAt: todayUtcDateString(),
  });

  return { currentPB: derived.currentPB, staleness, resetAt };
}

export function personalBestToEvaluationState(
  record: DerivationRecord | PersonalBestRow,
): SetState {
  if ("time_seconds" in record) {
    const pb = record as PersonalBestRow;
    return {
      weight: pb.weight,
      reps: pb.reps,
      time: pb.time_seconds,
      distance: pb.distance,
    };
  }
  const derived = record as DerivationRecord;
  return {
    weight: derived.weight ?? null,
    reps: derived.reps ?? null,
    time: derived.time ?? null,
    distance: derived.distance ?? null,
  };
}

export function isManualPB(
  exercise: ExerciseRow,
  currentPB: DerivationRecord | null,
  candidate: SetState,
): boolean {
  if (!exercise.pb_rule) {
    return false;
  }
  return evaluatePB({
    rule: exercise.pb_rule as PBRule,
    currentPB: currentPB ? personalBestToEvaluationState(currentPB) : null,
    newSet: candidate,
    ruleParameters: {
      targetReps: exercise.target_reps,
      minimumReps: exercise.minimum_reps,
    },
  }).isPB;
}

export function resetAtForToday(): string {
  return todayUtcDateString();
}

export function laterResetDate(existing: string, candidate: string): string {
  return candidate > existing ? candidate : existing;
}
