import type { SupabaseClient } from "@supabase/supabase-js";
import type { MeasurementType } from "./format";

export interface ExerciseRow {
  id: string;
  name: string;
  measurement_type: MeasurementType;
  display_order: number;
}

export interface PersonalBestRow {
  id: string;
  value: number;
  reps?: number | null;
  achieved_at: string | null;
  exercise: ExerciseRow;
  raw: Record<string, unknown>;
}

export interface PersonalBestHistoryRow {
  id: string;
  value: number;
  reps: number | null;
  achieved_at: string | null;
  is_current: boolean;
  was_reset: boolean;
  raw: Record<string, unknown>;
}

export interface SessionRow {
  id: string;
  date: string;
}

export interface SessionListRow {
  id: string;
  date: string;
  notes: string | null;
  calories_burned: number | null;
}

export interface SessionSetRow {
  id: string;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
}

export interface SessionEntryRow {
  id: string;
  exercise: ExerciseRow | null;
  sets: SessionSetRow[];
}

export interface SessionDetail {
  session: SessionListRow;
  entries: SessionEntryRow[];
}

function pickBool(row: Record<string, unknown>, keys: string[]): boolean {
  for (const k of keys) {
    const v = row[k];
    if (typeof v === "boolean") return v;
  }
  return false;
}

/** Fetch the exercise definition by id. */
export async function fetchExercise(
  supabase: SupabaseClient,
  exerciseId: string,
): Promise<ExerciseRow | null> {
  const { data, error } = await supabase
    .from("exercises")
    .select("id, name, measurement_type, display_order, pb_rule")
    .eq("id", exerciseId)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return (data as ExerciseRow | null) ?? null;
}

/**
 * Full personal-best history for a single exercise for the signed-in member.
 * Includes current, superseded, and reset records — RLS scopes to the caller.
 */
export async function fetchExerciseHistory(
  supabase: SupabaseClient,
  exerciseId: string,
  measurementType: string | undefined,
): Promise<PersonalBestHistoryRow[]> {
  const { data, error } = await supabase
    .from("personal_bests")
    .select("*")
    .eq("exercise_id", exerciseId)
    .is("deleted_at", null)
    .order("achieved_at", { ascending: true });
  if (error) throw new Error(error.message);
  const raw = (data ?? []) as Array<Record<string, unknown>>;
  return raw.map((r) => ({
    id: String(r.id),
    value: pickPBValue(r, measurementType),
    reps:
      typeof r.reps === "number"
        ? r.reps
        : typeof r.rep_count === "number"
          ? (r.rep_count as number)
          : null,
    achieved_at:
      (r.achieved_at as string) ??
      (r.session_date as string) ??
      (r.created_at as string) ??
      null,
    is_current: pickBool(r, ["is_current"]),
    was_reset: pickBool(r, ["was_reset", "is_reset", "reset"]),
    raw: r,
  }));
}

/**
 * All sessions for the signed-in member, ordered by date.
 * RLS scopes rows to the caller identified in the broker JWT.
 */
export async function fetchSessions(
  supabase: SupabaseClient,
): Promise<SessionRow[]> {
  const { data, error } = await supabase
    .from("sessions")
    .select("id, date")
    .is("deleted_at", null)
    .order("date", { ascending: true });
  if (error) throw new Error(error.message);
  return (data ?? []) as SessionRow[];
}

/**
 * Full session list for the signed-in member, most recent first. Includes
 * summary fields (notes, calories_burned) for the history row display.
 */
export async function fetchSessionHistory(
  supabase: SupabaseClient,
): Promise<SessionListRow[]> {
  const { data, error } = await supabase
    .from("sessions")
    .select("id, date, notes, calories_burned")
    .is("deleted_at", null)
    .order("date", { ascending: false })
    .order("created_at", { ascending: false });
  if (error) throw new Error(error.message);
  return (data ?? []) as SessionListRow[];
}

/**
 * A single session with its exercise entries and sets. RLS scopes rows to
 * the caller, so an unknown or foreign session id simply returns null.
 */
export async function fetchSessionDetail(
  supabase: SupabaseClient,
  sessionId: string,
): Promise<SessionDetail | null> {
  const { data: session, error: sErr } = await supabase
    .from("sessions")
    .select("id, date, notes, calories_burned")
    .eq("id", sessionId)
    .is("deleted_at", null)
    .maybeSingle();
  if (sErr) throw new Error(sErr.message);
  if (!session) return null;

  const { data: entries, error: eErr } = await supabase
    .from("exercise_entries")
    .select(
      "id, created_at, exercise:exercises(id, name, measurement_type, display_order), sets(id, weight, reps, time_seconds, distance, created_at)",
    )
    .eq("session_id", sessionId)
    .is("deleted_at", null)
    .order("created_at", { ascending: true });
  if (eErr) throw new Error(eErr.message);

  const rows = (entries ?? []) as unknown as Array<{
    id: string;
    exercise: ExerciseRow | ExerciseRow[] | null;
    sets: Array<SessionSetRow & { created_at?: string; deleted_at?: string | null }>;
  }>;

  const normalized: SessionEntryRow[] = rows.map((r) => ({
    id: r.id,
    exercise: Array.isArray(r.exercise) ? (r.exercise[0] ?? null) : (r.exercise ?? null),
    sets: (r.sets ?? [])
      .filter((s) => (s as { deleted_at?: string | null }).deleted_at == null)
      .map((s) => ({
        id: s.id,
        weight: s.weight,
        reps: s.reps,
        time_seconds: s.time_seconds,
        distance: s.distance,
      })),
  }));

  return { session: session as SessionListRow, entries: normalized };
}

/**
 * Current PBs for the signed-in member, ordered by exercise display_order.
 * RLS scopes rows to the caller identified in the broker JWT.
 */
export async function fetchCurrentPBs(
  supabase: SupabaseClient,
): Promise<PersonalBestRow[]> {
  const { data, error } = await supabase
    .from("personal_bests")
    .select(
      "*, exercise:exercises!inner(id, name, measurement_type, display_order)",
    )
    .eq("is_current", true)
    .is("deleted_at", null);

  if (error) throw new Error(error.message);

  const raw = (data ?? []) as Array<Record<string, unknown>>;
  const rows: PersonalBestRow[] = raw.map((r) => {
    const exercise = r.exercise as ExerciseRow;
    return {
      id: String(r.id),
      value: pickPBValue(r, exercise?.measurement_type),
      reps:
        typeof r.reps === "number"
          ? r.reps
          : typeof r.rep_count === "number"
            ? (r.rep_count as number)
            : null,
      achieved_at:
        (r.achieved_at as string) ??
        (r.session_date as string) ??
        (r.created_at as string) ??
        null,
      exercise,
      raw: r,
    };
  });
  return rows.sort(
    (a, b) => (a.exercise?.display_order ?? 0) - (b.exercise?.display_order ?? 0),
  );
}

/**
 * The personal_bests table shape varies by measurement type: some rows use
 * `weight`, others `time_seconds`, `distance_meters`, or `reps`. Pick the
 * primary scalar based on the exercise's measurement type, falling back to
 * the first numeric value column we recognise.
 */
function pickPBValue(
  row: Record<string, unknown>,
  measurementType: string | undefined,
): number {
  const candidatesByType: Record<string, string[]> = {
    weightAndReps: ["weight", "weight_kg", "value"],
    weightAndTime: ["weight", "weight_kg", "value"],
    timeOnly: ["time_seconds", "time", "seconds", "value"],
    distanceOnly: ["distance_meters", "distance", "meters", "value"],
    repsOnly: ["reps", "rep_count", "value"],
  };
  const generic = ["value", "weight", "weight_kg", "time_seconds", "time", "distance_meters", "distance", "reps"];
  const keys = [...(candidatesByType[measurementType ?? ""] ?? []), ...generic];
  for (const k of keys) {
    const v = row[k];
    if (typeof v === "number" && Number.isFinite(v)) return v;
    if (typeof v === "string" && v !== "" && Number.isFinite(Number(v))) return Number(v);
  }
  return NaN;
}

/** All exercises, ordered for the Log-a-Set picker. */
export async function fetchExercises(
  supabase: SupabaseClient,
): Promise<ExerciseRow[]> {
  const { data, error } = await supabase
    .from("exercises")
    .select("id, name, measurement_type, display_order")
    .is("deleted_at", null)
    .eq("is_active", true)
    .order("display_order", { ascending: true });
  if (error) throw new Error(error.message);
  return (data ?? []) as ExerciseRow[];
}

export interface BoardRow {
  exercise: ExerciseRow;
  pb: PersonalBestRow | null;
}

/**
 * The full Board: every active exercise for the gym, with its current PB
 * attached if one exists. Exercises without a PB still appear.
 */
export async function fetchBoard(
  supabase: SupabaseClient,
): Promise<BoardRow[]> {
  const [exercises, pbs] = await Promise.all([
    fetchExercises(supabase),
    fetchCurrentPBs(supabase),
  ]);
  const pbByExercise = new Map<string, PersonalBestRow>();
  for (const pb of pbs) {
    const exId = pb.exercise?.id;
    if (exId) pbByExercise.set(exId, pb);
  }
  return exercises.map((exercise) => ({
    exercise,
    pb: pbByExercise.get(exercise.id) ?? null,
  }));
}