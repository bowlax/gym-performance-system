/**
 * Log Session — write a full training session in one database transaction (#23).
 *
 * Receives the session, every exercise entry, and every set in a single
 * request and calls `log_session_atomic`. Failure rolls the whole save back.
 * Session-derived PBs are evaluated at read time via derivation (#28); this
 * function does not insert personal_bests.
 */

import {
  createEdgeRequestHandler,
  createUserClient,
  DATE_PATTERN,
  isUuid,
  jsonResponse,
  optionalNumber,
  optionalString,
} from "../_shared/member-edge.ts";

const MAX_EXERCISES = 50;
const MAX_SETS_PER_EXERCISE = 30;

export interface LogSessionSetInput {
  id?: string;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
}

export interface LogSessionExerciseInput {
  exerciseId: string;
  exerciseEntryId?: string;
  sets: LogSessionSetInput[];
}

export interface LogSessionRequest {
  session: {
    id?: string;
    date: string;
    notes: string | null;
    calories_burned: number | null;
  };
  exercises: LogSessionExerciseInput[];
}

type ParseResult =
  | { ok: true; request: LogSessionRequest }
  | { ok: false; error: string };

function parseSet(raw: unknown): LogSessionSetInput | null {
  if (typeof raw !== "object" || raw === null) {
    return null;
  }
  const record = raw as Record<string, unknown>;
  if (record.id != null && (typeof record.id !== "string" || !isUuid(record.id))) {
    return null;
  }
  return {
    id: typeof record.id === "string" ? record.id : undefined,
    weight: optionalNumber(record.weight),
    reps: optionalNumber(record.reps),
    time_seconds: optionalNumber(record.time_seconds),
    distance: optionalNumber(record.distance),
  };
}

function parseExercise(raw: unknown): LogSessionExerciseInput | null {
  if (typeof raw !== "object" || raw === null) {
    return null;
  }
  const record = raw as Record<string, unknown>;
  if (typeof record.exerciseId !== "string" || !isUuid(record.exerciseId)) {
    return null;
  }
  if (
    record.exerciseEntryId != null &&
    (typeof record.exerciseEntryId !== "string" || !isUuid(record.exerciseEntryId))
  ) {
    return null;
  }
  if (!Array.isArray(record.sets) || record.sets.length === 0) {
    return null;
  }
  if (record.sets.length > MAX_SETS_PER_EXERCISE) {
    return null;
  }
  const sets: LogSessionSetInput[] = [];
  for (const item of record.sets) {
    const parsed = parseSet(item);
    if (!parsed) {
      return null;
    }
    sets.push(parsed);
  }
  return {
    exerciseId: record.exerciseId,
    exerciseEntryId: typeof record.exerciseEntryId === "string"
      ? record.exerciseEntryId
      : undefined,
    sets,
  };
}

function collectIds(request: LogSessionRequest): string[] {
  const ids: string[] = [];
  if (request.session.id) ids.push(request.session.id);
  for (const exercise of request.exercises) {
    if (exercise.exerciseEntryId) ids.push(exercise.exerciseEntryId);
    for (const set of exercise.sets) {
      if (set.id) ids.push(set.id);
    }
  }
  return ids;
}

export function parseLogSessionRequest(body: unknown): ParseResult {
  if (typeof body !== "object" || body === null) {
    return {
      ok: false,
      error: "Invalid request body. Provide session and exercises.",
    };
  }

  const record = body as Record<string, unknown>;
  if (typeof record.session !== "object" || record.session === null) {
    return {
      ok: false,
      error: "Invalid request body. Provide session and exercises.",
    };
  }

  const sessionRecord = record.session as Record<string, unknown>;
  if (typeof sessionRecord.date !== "string" || !DATE_PATTERN.test(sessionRecord.date)) {
    return {
      ok: false,
      error: "Invalid request body. Provide session.date as YYYY-MM-DD.",
    };
  }
  if (
    sessionRecord.id != null &&
    (typeof sessionRecord.id !== "string" || !isUuid(sessionRecord.id))
  ) {
    return {
      ok: false,
      error: "Invalid request body. Provide session and exercises.",
    };
  }

  if (!Array.isArray(record.exercises) || record.exercises.length === 0) {
    return {
      ok: false,
      error: "At least one exercise is required.",
    };
  }
  if (record.exercises.length > MAX_EXERCISES) {
    return {
      ok: false,
      error: `A session may include at most ${MAX_EXERCISES} exercises.`,
    };
  }

  const exercises: LogSessionExerciseInput[] = [];
  for (const item of record.exercises) {
    const parsed = parseExercise(item);
    if (!parsed) {
      return {
        ok: false,
        error:
          "Invalid request body. Each exercise needs exerciseId and at least one set.",
      };
    }
    exercises.push(parsed);
  }

  const request: LogSessionRequest = {
    session: {
      id: typeof sessionRecord.id === "string" ? sessionRecord.id : undefined,
      date: sessionRecord.date,
      notes: optionalString(sessionRecord.notes),
      calories_burned: optionalNumber(sessionRecord.calories_burned),
    },
    exercises,
  };

  const ids = collectIds(request);
  if (new Set(ids).size !== ids.length) {
    return {
      ok: false,
      error: "Duplicate ids in session payload.",
    };
  }

  return { ok: true, request };
}

interface PostgrestErrorLike {
  message?: string;
  code?: string;
}

function rpcErrorResponse(error: PostgrestErrorLike): Response {
  const message = typeof error.message === "string" && error.message.length > 0
    ? error.message
    : "Internal server error";
  const pt = /^PT(\d{3})$/.exec(error.code ?? "");
  if (pt) {
    const status = Number(pt[1]);
    if (status >= 400 && status < 600) {
      return jsonResponse({ error: message }, status);
    }
  }

  switch (message) {
    case "Exercise not found":
    case "Session not found":
    case "Exercise entry not found":
    case "Set not found":
      return jsonResponse({ error: message }, 404);
    case "Forbidden":
    case "Exercise not in member gym":
      return jsonResponse({ error: message }, 403);
    case "Unauthorized":
      return jsonResponse({ error: message }, 401);
    case "Exercise is not active":
    case "At least one exercise is required":
    case "Each exercise must include at least one set":
    case "Invalid session date":
    case "Invalid session id":
    case "Invalid exerciseId":
    case "Invalid exerciseEntryId":
    case "Invalid set id":
    case "Invalid exercise":
    case "Invalid set":
    case "Invalid request body. Provide session and exercises.":
      return jsonResponse({ error: message }, 400);
    case "Conflict":
    case "Exercise entry mismatch":
    case "Set mismatch":
      return jsonResponse({ error: message }, 409);
    default:
      return jsonResponse({ error: "Internal server error" }, 500);
  }
}

export const handleLogSessionRequest = createEdgeRequestHandler(
  async (req, _claims, authHeader) => {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const parsed = parseLogSessionRequest(body);
    if (!parsed.ok) {
      return jsonResponse({ error: parsed.error }, 400);
    }

    const supabase = createUserClient(authHeader);
    const { data, error } = await supabase.rpc("log_session_atomic", {
      payload: parsed.request,
    });

    if (error) {
      return rpcErrorResponse(error);
    }

    if (typeof data !== "object" || data === null) {
      return jsonResponse({ error: "Internal server error" }, 500);
    }

    return jsonResponse(data as Record<string, unknown>, 200);
  },
);
