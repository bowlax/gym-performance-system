import type { SupabaseClient } from "@supabase/supabase-js";
import { bestSetFromSets } from "./best-set";
import type { MeasurementType } from "./format";
import {
  mergeProgressionEntries,
  type ExerciseSetSummary,
  type ProgressionEntryRow,
} from "./progression-entry-merger";

export interface ExerciseRow {
  id: string;
  name: string;
  measurement_type: MeasurementType;
  display_order: number;
  pb_rule?: string | null;
}

export type { ExerciseSetSummary, ProgressionEntryRow };

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
  set_id: string | null;
  entry_type: string | null;
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
  has_pb?: boolean;
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
  pbSetIds: string[];
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

async function fetchPbSetIds(
  supabase: SupabaseClient,
  setIds: string[],
): Promise<Set<string>> {
  if (setIds.length === 0) return new Set();
  const { data, error } = await supabase
    .from("personal_bests")
    .select("set_id")
    .in("set_id", setIds)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);
  return new Set(
    (data ?? [])
      .map((row) => row.set_id)
      .filter((id): id is string => typeof id === "string"),
  );
}

async function fetchSessionIdsWithPb(
  supabase: SupabaseClient,
  sessionIds: string[],
): Promise<Set<string>> {
  if (sessionIds.length === 0) return new Set();

  const { data: entries, error: eErr } = await supabase
    .from("exercise_entries")
    .select("session_id, sets(id, deleted_at)")
    .in("session_id", sessionIds)
    .is("deleted_at", null);
  if (eErr) throw new Error(eErr.message);

  const setToSession = new Map<string, string>();
  for (const entry of entries ?? []) {
    const sessionId = entry.session_id as string;
    for (const set of (entry.sets ?? []) as Array<{
      id: string;
      deleted_at?: string | null;
    }>) {
      if (set.deleted_at != null) continue;
      setToSession.set(set.id, sessionId);
    }
  }

  const pbSetIds = await fetchPbSetIds(supabase, [...setToSession.keys()]);
  const sessionsWithPb = new Set<string>();
  for (const setId of pbSetIds) {
    const sessionId = setToSession.get(setId);
    if (sessionId) sessionsWithPb.add(sessionId);
  }
  return sessionsWithPb;
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
    set_id: typeof r.set_id === "string" ? r.set_id : null,
    entry_type: typeof r.entry_type === "string" ? r.entry_type : null,
    raw: r,
  }));
}

/**
 * Best set per session for one exercise — mirrors iOS `exerciseHistory`.
 */
export async function fetchExerciseSessionHistory(
  supabase: SupabaseClient,
  exerciseId: string,
  pbRule: string | null | undefined,
  pbSetIds: ReadonlySet<string>,
): Promise<ExerciseSetSummary[]> {
  const { data, error } = await supabase
    .from("exercise_entries")
    .select(
      "id, session:sessions!inner(id, date), sets(id, weight, reps, time_seconds, distance, deleted_at)",
    )
    .eq("exercise_id", exerciseId)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);

  const rows = (data ?? []) as unknown as Array<{
    id: string;
    session: { id: string; date: string } | Array<{ id: string; date: string }>;
    sets: Array<
      SessionSetRow & { deleted_at?: string | null }
    >;
  }>;

  const bySession = new Map<string, { date: string; sets: SessionSetRow[] }>();

  for (const row of rows) {
    const session = Array.isArray(row.session) ? row.session[0] : row.session;
    if (!session) continue;

    const activeSets = (row.sets ?? [])
      .filter((set) => set.deleted_at == null)
      .map((set) => ({
        id: set.id,
        weight: set.weight,
        reps: set.reps,
        time_seconds: set.time_seconds,
        distance: set.distance,
      }));

    const existing = bySession.get(session.id);
    if (existing) {
      existing.sets.push(...activeSets);
    } else {
      bySession.set(session.id, { date: session.date, sets: [...activeSets] });
    }
  }

  const summaries: ExerciseSetSummary[] = [];
  for (const { date, sets } of bySession.values()) {
    const best = bestSetFromSets(sets, pbRule);
    if (!best) continue;
    summaries.push({
      sessionDate: date,
      set: best,
      isPB: pbSetIds.has(best.id),
    });
  }

  return summaries.sort((left, right) =>
    left.sessionDate.localeCompare(right.sessionDate),
  );
}

export interface MergedProgressionData {
  entries: ProgressionEntryRow[];
  personalBests: PersonalBestHistoryRow[];
}

/** Session sets merged with PB history for the progression chart and list. */
export async function fetchMergedProgression(
  supabase: SupabaseClient,
  exerciseId: string,
  exercise: ExerciseRow,
): Promise<MergedProgressionData> {
  const personalBests = await fetchExerciseHistory(
    supabase,
    exerciseId,
    exercise.measurement_type,
  );
  const pbSetIds = new Set(
    personalBests
      .map((pb) => pb.set_id)
      .filter((id): id is string => id != null),
  );
  const sessionHistory = await fetchExerciseSessionHistory(
    supabase,
    exerciseId,
    exercise.pb_rule,
    pbSetIds,
  );
  const entries = mergeProgressionEntries({
    sessionHistory,
    personalBests,
    exercise,
    from: new Date(0),
  });
  return { entries, personalBests };
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
  const sessions = (data ?? []) as SessionListRow[];
  const sessionsWithPb = await fetchSessionIdsWithPb(
    supabase,
    sessions.map((s) => s.id),
  );
  return sessions.map((s) => ({
    ...s,
    has_pb: sessionsWithPb.has(s.id),
  }));
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
    pbSetIds: [],
  }));

  const allSetIds = normalized.flatMap((entry) => entry.sets.map((set) => set.id));
  const pbSetIds = await fetchPbSetIds(supabase, allSetIds);
  const entriesWithPb = normalized.map((entry) => ({
    ...entry,
    pbSetIds: entry.sets
      .map((set) => set.id)
      .filter((setId) => pbSetIds.has(setId)),
  }));

  return { session: session as SessionListRow, entries: entriesWithPb };
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