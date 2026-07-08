import { LOG_SET_URL } from "./env";

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

  const isPersonalBest = Boolean(
    raw.isPersonalBest ?? raw.isNewPB ?? raw.isPB ?? raw.pb ?? false,
  );
  const previousValue = typeof raw.previousValue === "number" ? raw.previousValue : undefined;
  const newValue = typeof raw.newValue === "number" ? raw.newValue : undefined;
  return { isPersonalBest, previousValue, newValue, raw };
}

/**
 * Log multiple exercises into a single session. The first set creates the session;
 * subsequent sets reuse the same sessionId (iOS saveSession parity).
 */
export async function logSession(
  token: string,
  input: LogSessionInput,
): Promise<LogSessionResult> {
  if (input.exercises.length === 0) {
    throw new Error("At least one exercise is required to log a session.");
  }

  const sessionId = crypto.randomUUID();
  const results: LogSessionResult["results"] = [];

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
    results.push({ exerciseId: ex.exerciseId, result });
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