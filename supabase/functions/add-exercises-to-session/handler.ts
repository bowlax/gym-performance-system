/**
 * Add Exercises To Session — attach new entries/sets to an existing session (#27).
 *
 * Does not create a session or change date/notes/calories. Tombstoned or
 * foreign sessions 404. Writes are one database transaction. Session PBs
 * stay derived at read time (#28).
 */

import {
  createEdgeRequestHandler,
  createUserClient,
  isUuid,
  jsonResponse,
  optionalNumber,
} from "../_shared/member-edge.ts";

const MAX_EXERCISES = 50;
const MAX_SETS_PER_EXERCISE = 30;

export interface AddExercisesSetInput {
  id?: string;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
}

export interface AddExercisesExerciseInput {
  exerciseId: string;
  exerciseEntryId?: string;
  sets: AddExercisesSetInput[];
}

export interface AddExercisesToSessionRequest {
  sessionId: string;
  exercises: AddExercisesExerciseInput[];
}

type ParseResult =
  | { ok: true; request: AddExercisesToSessionRequest }
  | { ok: false; error: string };

function parseSet(raw: unknown): AddExercisesSetInput | null {
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

function parseExercise(raw: unknown): AddExercisesExerciseInput | null {
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
  const sets: AddExercisesSetInput[] = [];
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

function collectIds(request: AddExercisesToSessionRequest): string[] {
  const ids: string[] = [request.sessionId];
  for (const exercise of request.exercises) {
    if (exercise.exerciseEntryId) ids.push(exercise.exerciseEntryId);
    for (const set of exercise.sets) {
      if (set.id) ids.push(set.id);
    }
  }
  return ids;
}

export function parseAddExercisesToSessionRequest(body: unknown): ParseResult {
  if (typeof body !== "object" || body === null) {
    return {
      ok: false,
      error: "Invalid request body. Provide sessionId and exercises.",
    };
  }

  const record = body as Record<string, unknown>;
  if (typeof record.sessionId !== "string" || !isUuid(record.sessionId)) {
    return {
      ok: false,
      error: "Invalid request body. Provide sessionId and exercises.",
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

  const exercises: AddExercisesExerciseInput[] = [];
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

  const request: AddExercisesToSessionRequest = {
    sessionId: record.sessionId,
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
    case "Invalid sessionId":
    case "Invalid exerciseId":
    case "Invalid exerciseEntryId":
    case "Invalid set id":
    case "Invalid exercise":
    case "Invalid set":
    case "Invalid request body. Provide sessionId and exercises.":
      return jsonResponse({ error: message }, 400);
    case "Conflict":
    case "Exercise entry mismatch":
    case "Set mismatch":
      return jsonResponse({ error: message }, 409);
    default:
      return jsonResponse({ error: "Internal server error" }, 500);
  }
}

export const handleAddExercisesToSessionRequest = createEdgeRequestHandler(
  async (req, _claims, authHeader) => {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const parsed = parseAddExercisesToSessionRequest(body);
    if (!parsed.ok) {
      return jsonResponse({ error: parsed.error }, 400);
    }

    const supabase = createUserClient(authHeader);
    const { data, error } = await supabase.rpc("add_exercises_to_session_atomic", {
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
