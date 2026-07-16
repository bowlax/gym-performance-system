import type { SupabaseClient } from "@supabase/supabase-js";
import {
  badgeIds,
  derivePBs,
  type DerivationRecord,
  type StalenessSetting,
} from "@gp-shared/pb-derivation.ts";
import type { PBRule } from "@gp-shared/pb-evaluation.ts";
import { todayISO } from "./log-set";

const SESSION_DERIVED = "sessionDerived";
const MANUAL_ENTRY = "manualEntry";

export interface DerivedSetRow {
  id: string;
  exercise_id: string;
  session_id: string;
  session_date: string;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
}

export interface DerivedManualPBRow {
  id: string;
  exercise_id: string;
  set_id: string | null;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
  achieved_at: string | null;
  entry_type: string | null;
}

export interface DerivedPBDisplay {
  id: string;
  value: number;
  reps: number | null;
  achieved_at: string | null;
  set_id: string | null;
  raw: Record<string, unknown>;
}

export interface ExerciseDerivationReadState {
  currentPB: DerivedPBDisplay | null;
  lifetimePB: DerivedPBDisplay | null;
  badgeIdSet: Set<string>;
  resetAt: string | null;
  staleness: StalenessSetting;
}

export interface BoardDerivationBundle {
  staleness: StalenessSetting;
  setsByExercise: Map<string, DerivedSetRow[]>;
  manualPBsByExercise: Map<string, DerivedManualPBRow[]>;
  resetAtByExercise: Map<string, string>;
}

function mapStalenessUnit(dbUnit: string): StalenessSetting["unit"] {
  return dbUnit === "month" ? "months" : "quarters";
}

/** DB `quarter` / `month` → derivation `quarters` / `months`. */
export function stalenessFromMemberRow(
  row: Record<string, unknown> | null | undefined,
): StalenessSetting {
  if (!row) {
    return { enabled: false, periods: 2, unit: "quarters" };
  }
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

export async function fetchMemberStaleness(
  supabase: SupabaseClient,
): Promise<StalenessSetting> {
  const { data, error } = await supabase
    .from("members")
    .select("staleness_enabled, staleness_periods, staleness_unit")
    .maybeSingle();
  if (error) throw new Error(error.message);
  return stalenessFromMemberRow(data as Record<string, unknown> | null);
}

export async function fetchExerciseResetAt(
  supabase: SupabaseClient,
  exerciseId: string,
): Promise<string | null> {
  const { data, error } = await supabase
    .from("exercise_resets")
    .select("reset_at")
    .eq("exercise_id", exerciseId)
    .is("deleted_at", null)
    .maybeSingle();
  if (error) throw new Error(error.message);
  const resetAt = data?.reset_at;
  return typeof resetAt === "string" ? resetAt : null;
}

export async function fetchExerciseSetsForDerivation(
  supabase: SupabaseClient,
  exerciseId: string,
): Promise<DerivedSetRow[]> {
  const { data, error } = await supabase
    .from("exercise_entries")
    .select(
      "exercise_id, session:sessions!inner(id, date), sets(id, weight, reps, time_seconds, distance, deleted_at)",
    )
    .eq("exercise_id", exerciseId)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);

  const rows: DerivedSetRow[] = [];
  for (const entry of data ?? []) {
    const exercise_id = entry.exercise_id as string;
    const session = Array.isArray(entry.session)
      ? entry.session[0]
      : entry.session;
    const sessionId =
      session && typeof session.id === "string" ? session.id : null;
    const sessionDate =
      session && typeof session.date === "string" ? session.date : null;
    if (!sessionId || !sessionDate) continue;

    for (const set of (entry.sets ?? []) as Array<{
      id: string;
      weight: number | null;
      reps: number | null;
      time_seconds: number | null;
      distance: number | null;
      deleted_at?: string | null;
    }>) {
      if (set.deleted_at != null) continue;
      rows.push({
        id: set.id,
        exercise_id,
        session_id: sessionId,
        session_date: sessionDate,
        weight: set.weight,
        reps: set.reps,
        time_seconds: set.time_seconds,
        distance: set.distance,
      });
    }
  }
  return rows;
}

export async function fetchManualPBsForDerivation(
  supabase: SupabaseClient,
  exerciseId?: string,
): Promise<DerivedManualPBRow[]> {
  let query = supabase
    .from("personal_bests")
    .select(
      "id, exercise_id, set_id, weight, reps, time_seconds, distance, achieved_at, entry_type",
    )
    .neq("entry_type", SESSION_DERIVED)
    .is("deleted_at", null);

  if (exerciseId) {
    query = query.eq("exercise_id", exerciseId);
  }

  const { data, error } = await query;
  if (error) throw new Error(error.message);

  return (data ?? []).map((row) => ({
    id: String(row.id),
    exercise_id: String(row.exercise_id),
    set_id: typeof row.set_id === "string" ? row.set_id : null,
    weight: typeof row.weight === "number" ? row.weight : null,
    reps: typeof row.reps === "number" ? row.reps : null,
    time_seconds:
      typeof row.time_seconds === "number" ? row.time_seconds : null,
    distance: typeof row.distance === "number" ? row.distance : null,
    achieved_at:
      typeof row.achieved_at === "string" ? row.achieved_at : null,
    entry_type:
      typeof row.entry_type === "string" ? row.entry_type : null,
  }));
}

export async function fetchBoardDerivationBundle(
  supabase: SupabaseClient,
): Promise<BoardDerivationBundle> {
  const [staleness, setsResult, manualPBs, resetsResult] = await Promise.all([
    fetchMemberStaleness(supabase),
    supabase
      .from("exercise_entries")
      .select(
        "exercise_id, session:sessions!inner(id, date), sets(id, weight, reps, time_seconds, distance, deleted_at)",
      )
      .is("deleted_at", null),
    fetchManualPBsForDerivation(supabase),
    supabase
      .from("exercise_resets")
      .select("exercise_id, reset_at")
      .is("deleted_at", null),
  ]);

  if (setsResult.error) throw new Error(setsResult.error.message);
  if (resetsResult.error) throw new Error(resetsResult.error.message);

  const setsByExercise = new Map<string, DerivedSetRow[]>();
  for (const entry of setsResult.data ?? []) {
    const exerciseId = entry.exercise_id as string;
    const session = Array.isArray(entry.session)
      ? entry.session[0]
      : entry.session;
    const sessionId =
      session && typeof session.id === "string" ? session.id : null;
    const sessionDate =
      session && typeof session.date === "string" ? session.date : null;
    if (!sessionId || !sessionDate) continue;

    const bucket = setsByExercise.get(exerciseId) ?? [];
    for (const set of (entry.sets ?? []) as Array<{
      id: string;
      weight: number | null;
      reps: number | null;
      time_seconds: number | null;
      distance: number | null;
      deleted_at?: string | null;
    }>) {
      if (set.deleted_at != null) continue;
      bucket.push({
        id: set.id,
        exercise_id: exerciseId,
        session_id: sessionId,
        session_date: sessionDate,
        weight: set.weight,
        reps: set.reps,
        time_seconds: set.time_seconds,
        distance: set.distance,
      });
    }
    setsByExercise.set(exerciseId, bucket);
  }

  const manualPBsByExercise = new Map<string, DerivedManualPBRow[]>();
  for (const pb of manualPBs) {
    const bucket = manualPBsByExercise.get(pb.exercise_id) ?? [];
    bucket.push(pb);
    manualPBsByExercise.set(pb.exercise_id, bucket);
  }

  const resetAtByExercise = new Map<string, string>();
  for (const row of resetsResult.data ?? []) {
    const exerciseId = row.exercise_id;
    const resetAt = row.reset_at;
    if (typeof exerciseId === "string" && typeof resetAt === "string") {
      resetAtByExercise.set(exerciseId, resetAt);
    }
  }

  return { staleness, setsByExercise, manualPBsByExercise, resetAtByExercise };
}

export function buildDerivationRecords(params: {
  sets: DerivedSetRow[];
  manualPBs: DerivedManualPBRow[];
}): DerivationRecord[] {
  const setIds = new Set(params.sets.map((set) => set.id));
  const records: DerivationRecord[] = [];

  for (const set of params.sets) {
    records.push({
      id: set.id,
      achievedAt: set.session_date,
      weight: set.weight,
      reps: set.reps,
      time: set.time_seconds,
      distance: set.distance,
      entryKind: SESSION_DERIVED,
    });
  }

  for (const pb of params.manualPBs) {
    if (pb.entry_type === SESSION_DERIVED) continue;
    if (pb.set_id && setIds.has(pb.set_id)) continue;
    records.push({
      id: pb.id,
      achievedAt: pb.achieved_at,
      weight: pb.weight,
      reps: pb.reps,
      time: pb.time_seconds,
      distance: pb.distance,
      entryKind: pb.entry_type ?? MANUAL_ENTRY,
    });
  }

  return records;
}

export function recordToRaw(record: DerivationRecord): Record<string, unknown> {
  return {
    weight: record.weight ?? null,
    reps: record.reps ?? null,
    time_seconds: record.time ?? null,
    distance: record.distance ?? null,
  };
}

export function pickRecordScalarValue(
  record: DerivationRecord,
  measurementType: string | undefined,
): number {
  const raw = recordToRaw(record);
  const candidatesByType: Record<string, string[]> = {
    weightAndReps: ["weight", "weight_kg", "value"],
    weightAndTime: ["weight", "weight_kg", "value"],
    timeOnly: ["time_seconds", "time", "seconds", "value"],
    distanceOnly: ["distance_meters", "distance", "meters", "value"],
    repsOnly: ["reps", "rep_count", "value"],
  };
  const generic = [
    "value",
    "weight",
    "weight_kg",
    "time_seconds",
    "time",
    "distance_meters",
    "distance",
    "reps",
  ];
  const keys = [
    ...(candidatesByType[measurementType ?? ""] ?? []),
    ...generic,
  ];
  for (const key of keys) {
    const value = raw[key];
    if (typeof value === "number" && Number.isFinite(value)) return value;
    if (typeof value === "string" && value !== "" && Number.isFinite(Number(value))) {
      return Number(value);
    }
  }
  return NaN;
}

export function derivationRecordToDisplay(
  record: DerivationRecord,
  measurementType: string | undefined,
  setIds: ReadonlySet<string>,
): DerivedPBDisplay {
  const raw = recordToRaw(record);
  return {
    id: record.id,
    value: pickRecordScalarValue(record, measurementType),
    reps: record.reps ?? null,
    achieved_at: record.achievedAt ?? null,
    set_id: setIds.has(record.id) ? record.id : null,
    raw,
  };
}

export function deriveExerciseReadState(params: {
  pbRule: string | null | undefined;
  measurementType: string | undefined;
  sets: DerivedSetRow[];
  manualPBs: DerivedManualPBRow[];
  staleness: StalenessSetting;
  resetAt: string | null;
  evaluatedAt?: string;
}): ExerciseDerivationReadState {
  const rule = params.pbRule as PBRule | null | undefined;
  const evaluatedAt = params.evaluatedAt ?? todayISO();
  const setIds = new Set(params.sets.map((set) => set.id));
  const records = buildDerivationRecords({
    sets: params.sets,
    manualPBs: params.manualPBs,
  });

  if (!rule || records.length === 0) {
    return {
      currentPB: null,
      lifetimePB: null,
      badgeIdSet: new Set(),
      resetAt: params.resetAt,
      staleness: params.staleness,
    };
  }

  const { currentPB, lifetimePB } = derivePBs({
    rule,
    records,
    staleness: params.staleness,
    resetAt: params.resetAt,
    evaluatedAt,
  });

  const badges = badgeIds({ rule, records });

  return {
    currentPB: currentPB
      ? derivationRecordToDisplay(currentPB, params.measurementType, setIds)
      : null,
    lifetimePB: lifetimePB
      ? derivationRecordToDisplay(lifetimePB, params.measurementType, setIds)
      : null,
    badgeIdSet: new Set(badges),
    resetAt: params.resetAt,
    staleness: params.staleness,
  };
}
