import { LOG_SET_URL } from "./env";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  deriveExerciseReadState,
  fetchBoardDerivationBundle,
} from "./derive-pb-reads";
import type { ExerciseRow } from "./queries";
import {
  measurementAsSetState,
  sessionSetEarnedCelebration,
} from "./session-pb-celebration";
import type { PBRule } from "@gp-shared/pb-evaluation.ts";

export interface LogSetInput {
  sessionDate: string; // YYYY-MM-DD
  /** Reuse an existing session instead of creating one. */
  sessionId?: string;
  /** Client-generated id when creating a new session (first exercise in a multi-set save). */
  sessionClientId?: string;
  /** Session metadata when creating a new session (ignored when sessionId is set). */
  notes?: string | null;
  calories_burned?: number | null;
  exerciseId: string;
  weight?: number;
  reps?: number;
  /** Seconds elapsed; sent to the API as `set.time_seconds`. */
  time_seconds?: number;
  /** Form-layer alias; mapped to `time_seconds` when building the request. */
  time?: number;
  distance?: number;
}

export interface LogSessionExerciseInput {
  exerciseId: string;
  weight?: number;
  reps?: number;
  time_seconds?: number;
  time?: number;
  distance?: number;
}

export interface LogSessionInput {
  sessionDate: string;
  notes?: string | null;
  calories_burned?: number | null;
  exercises: LogSessionExerciseInput[];
}

export interface LogSessionResult {
  sessionId: string;
  results: { exerciseId: string; result: LogSetResult }[];
}

export interface LogSetResult {
  isPersonalBest: boolean;
  previousValue?: number;
  newValue?: number;
  raw: Record<string, unknown>;
}

export async function logSet(
  token: string,
  input: LogSetInput,
): Promise<LogSetResult> {
  const set: Record<string, number> = {};
  if (typeof input.weight === "number") set.weight = input.weight;
  if (typeof input.reps === "number") set.reps = input.reps;
  const timeSeconds =
    typeof input.time_seconds === "number"
      ? input.time_seconds
      : typeof input.time === "number"
        ? input.time
        : undefined;
  if (typeof timeSeconds === "number") set.time_seconds = timeSeconds;
  if (typeof input.distance === "number") set.distance = input.distance;

  const body: Record<string, unknown> = {
    exerciseId: input.exerciseId,
    set,
  };

  if (input.sessionId) {
    body.sessionId = input.sessionId;
  } else {
    body.session = {
      date: input.sessionDate,
      ...(input.sessionClientId ? { id: input.sessionClientId } : {}),
      ...(input.notes != null ? { notes: input.notes } : {}),
      ...(input.calories_burned != null
        ? { calories_burned: input.calories_burned }
        : {}),
    };
  }

  if (import.meta.env.DEV) {
    // Debug: verify the payload the edge function receives.
    // eslint-disable-next-line no-console
    console.debug("[log-set] request body", body);
  }

  const response = await fetch(LOG_SET_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });

  const raw = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  if (!response.ok) {
    const msg =
      (typeof raw.error === "string" && raw.error) ||
      (typeof raw.message === "string" && raw.message) ||
      `Log set failed (${response.status})`;
    throw new Error(msg);
  }

  return { isPersonalBest: false, raw };
}

/**
 * Log multiple exercises into a single session. Derives PB celebration client-side
 * (before/after current PB comparison; strict improvement only).
 */
export async function logSession(
  supabase: SupabaseClient,
  token: string,
  input: LogSessionInput,
  exercisesById: Map<string, ExerciseRow>,
): Promise<LogSessionResult> {
  if (input.exercises.length === 0) {
    throw new Error("At least one exercise is required to log a session.");
  }

  const bundleBefore = await fetchBoardDerivationBundle(supabase);
  const beforeCurrentByExercise = new Map<string, ReturnType<typeof deriveExerciseReadState>["currentPB"]>();

  for (const ex of input.exercises) {
    const exercise = exercisesById.get(ex.exerciseId);
    if (!exercise?.pb_rule) continue;
    const before = deriveExerciseReadState({
      pbRule: exercise.pb_rule,
      measurementType: exercise.measurement_type,
      sets: bundleBefore.setsByExercise.get(ex.exerciseId) ?? [],
      manualPBs: bundleBefore.manualPBsByExercise.get(ex.exerciseId) ?? [],
      staleness: bundleBefore.staleness,
      resetAt: bundleBefore.resetAtByExercise.get(ex.exerciseId) ?? null,
    });
    beforeCurrentByExercise.set(ex.exerciseId, before.currentPB);
  }

  const sessionId = crypto.randomUUID();
  const results: LogSessionResult["results"] = [];
  const loggedSetIdsByExercise = new Map<string, Set<string>>();

  for (let i = 0; i < input.exercises.length; i++) {
    const ex = input.exercises[i]!;
    const result = await logSet(token, {
      ...ex,
      sessionDate: input.sessionDate,
      ...(i === 0
        ? {
            sessionClientId: sessionId,
            notes: input.notes,
            calories_burned: input.calories_burned,
          }
        : { sessionId }),
    });

    const setId =
      typeof result.raw.set === "object" &&
      result.raw.set !== null &&
      typeof (result.raw.set as Record<string, unknown>).id === "string"
        ? ((result.raw.set as Record<string, unknown>).id as string)
        : undefined;

    if (setId) {
      const ids = loggedSetIdsByExercise.get(ex.exerciseId) ?? new Set<string>();
      ids.add(setId);
      loggedSetIdsByExercise.set(ex.exerciseId, ids);
    }

    results.push({ exerciseId: ex.exerciseId, result });
  }

  const bundleAfter = await fetchBoardDerivationBundle(supabase);

  for (const entry of results) {
    const exercise = exercisesById.get(entry.exerciseId);
    if (!exercise?.pb_rule) continue;

    const after = deriveExerciseReadState({
      pbRule: exercise.pb_rule,
      measurementType: exercise.measurement_type,
      sets: bundleAfter.setsByExercise.get(entry.exerciseId) ?? [],
      manualPBs: bundleAfter.manualPBsByExercise.get(entry.exerciseId) ?? [],
      staleness: bundleAfter.staleness,
      resetAt: bundleAfter.resetAtByExercise.get(entry.exerciseId) ?? null,
    });

    const logged = input.exercises.find((ex) => ex.exerciseId === entry.exerciseId);
    if (!logged) continue;

    entry.result.isPersonalBest = sessionSetEarnedCelebration({
      rule: exercise.pb_rule as PBRule,
      beforeCurrent: beforeCurrentByExercise.get(entry.exerciseId) ?? null,
      afterCurrent: after.currentPB,
      loggedSetIds: loggedSetIdsByExercise.get(entry.exerciseId) ?? new Set(),
      loggedSet: measurementAsSetState(logged),
    });
  }

  return { sessionId, results };
}

export function todayISO(): string {
  const d = new Date();
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}