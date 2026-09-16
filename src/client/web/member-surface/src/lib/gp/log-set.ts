import { LOG_SESSION_URL, LOG_SET_URL } from "./env";
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

export interface LogSessionSetPayload {
  id: string;
  weight?: number;
  reps?: number;
  time_seconds?: number;
  distance?: number;
}

export interface LogSessionPayload {
  session: {
    id: string;
    date: string;
    notes?: string | null;
    calories_burned?: number | null;
  };
  exercises: {
    exerciseId: string;
    exerciseEntryId: string;
    sets: LogSessionSetPayload[];
  }[];
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

interface LogSessionApiSet {
  id?: unknown;
  weight?: unknown;
  reps?: unknown;
  time_seconds?: unknown;
  distance?: unknown;
}

interface LogSessionApiExercise {
  exerciseId?: unknown;
  exerciseEntryId?: unknown;
  sets?: LogSessionApiSet[];
}

interface LogSessionApiResponse {
  session?: { id?: unknown };
  exercises?: LogSessionApiExercise[];
  error?: unknown;
  message?: unknown;
}

function measurementFields(input: {
  weight?: number;
  reps?: number;
  time_seconds?: number;
  time?: number;
  distance?: number;
}): Omit<LogSessionSetPayload, "id"> {
  const set: Omit<LogSessionSetPayload, "id"> = {};
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
  return set;
}

export function buildLogSessionPayload(input: LogSessionInput): LogSessionPayload {
  if (input.exercises.length === 0) {
    throw new Error("At least one exercise is required to log a session.");
  }

  return {
    session: {
      id: crypto.randomUUID(),
      date: input.sessionDate,
      ...(input.notes != null ? { notes: input.notes } : {}),
      ...(input.calories_burned != null
        ? { calories_burned: input.calories_burned }
        : {}),
    },
    exercises: input.exercises.map((ex) => ({
      exerciseId: ex.exerciseId,
      exerciseEntryId: crypto.randomUUID(),
      sets: [
        {
          id: crypto.randomUUID(),
          ...measurementFields(ex),
        },
      ],
    })),
  };
}

export async function logSet(
  token: string,
  input: LogSetInput,
): Promise<LogSetResult> {
  const set: Record<string, number> = measurementFields(input);

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
 * Log multiple exercises into a single session in one atomic request (#23).
 * Derives PB celebration client-side (before/after current PB comparison;
 * strict improvement only).
 */
export async function logSession(
  supabase: SupabaseClient,
  token: string,
  input: LogSessionInput,
  exercisesById: Map<string, ExerciseRow>,
): Promise<LogSessionResult> {
  const payload = buildLogSessionPayload(input);

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
      resetOccurredAt: bundleBefore.resetOccurredAtByExercise.get(ex.exerciseId) ?? null,
    });
    beforeCurrentByExercise.set(ex.exerciseId, before.currentPB);
  }

  if (import.meta.env.DEV) {
    // eslint-disable-next-line no-console
    console.debug("[log-session] request body", payload);
  }

  const response = await fetch(LOG_SESSION_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(payload),
  });

  const raw = (await response.json().catch(() => ({}))) as LogSessionApiResponse;
  if (!response.ok) {
    const msg =
      (typeof raw.error === "string" && raw.error) ||
      (typeof raw.message === "string" && raw.message) ||
      `Log session failed (${response.status})`;
    throw new Error(msg);
  }

  const sessionId =
    typeof raw.session?.id === "string" ? raw.session.id : payload.session.id;
  const apiExercises = Array.isArray(raw.exercises) ? raw.exercises : [];
  const results: LogSessionResult["results"] = [];
  const loggedSetIdsByExercise = new Map<string, Set<string>>();

  for (let i = 0; i < input.exercises.length; i++) {
    const ex = input.exercises[i]!;
    const apiExercise = apiExercises[i];
    const apiSets = Array.isArray(apiExercise?.sets) ? apiExercise.sets : [];
    const ids = loggedSetIdsByExercise.get(ex.exerciseId) ?? new Set<string>();
    for (const set of apiSets) {
      if (typeof set.id === "string") ids.add(set.id);
    }
    for (const set of payload.exercises[i]?.sets ?? []) {
      ids.add(set.id);
    }
    loggedSetIdsByExercise.set(ex.exerciseId, ids);
    results.push({
      exerciseId: ex.exerciseId,
      result: {
        isPersonalBest: false,
        raw: (apiExercise as Record<string, unknown> | undefined) ?? {},
      },
    });
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
      resetOccurredAt: bundleAfter.resetOccurredAtByExercise.get(entry.exerciseId) ?? null,
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
