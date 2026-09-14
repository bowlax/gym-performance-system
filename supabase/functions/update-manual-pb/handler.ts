/**
 * Update Manual PB — in-place correction of an existing manual entry.
 *
 * Matches iOS `updateManualPB`:
 * - Same row id (never delete-and-recreate)
 * - Values and optional date (`achievedAt` null = undated lifetime-only)
 * - Does **not** require beating the current PB
 * - Dated ↔ undated is allowed; derivation at read time decides current vs lifetime
 */

import {
  createEdgeRequestHandler,
  createUserClient,
  DATE_PATTERN,
  fetchExercise,
  fetchPersonalBestById,
  isFutureDate,
  isUuid,
  jsonResponse,
  optionalNumber,
  validateMeasurementFields,
  type PersonalBestRow,
} from "../_shared/member-edge.ts";

interface UpdateManualPBRequest {
  exerciseId: string;
  personalBestId: string;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
  achievedAt: string | null;
}

type ParseResult =
  | { ok: true; request: UpdateManualPBRequest }
  | { ok: false; error: string };

function parseAchievedAt(
  raw: unknown,
): { ok: true; value: string | null } | { ok: false; error: string } {
  if (raw === undefined || raw === null) {
    return { ok: true, value: null };
  }
  if (typeof raw !== "string") {
    return { ok: false, error: "achievedAt must be a YYYY-MM-DD string or null" };
  }
  const trimmed = raw.trim();
  if (trimmed === "") {
    return { ok: true, value: null };
  }
  if (!DATE_PATTERN.test(trimmed)) {
    return { ok: false, error: "achievedAt must be a valid YYYY-MM-DD date or null" };
  }
  return { ok: true, value: trimmed };
}

function parseUpdateManualPBRequest(body: unknown): ParseResult {
  if (typeof body !== "object" || body === null) {
    return {
      ok: false,
      error: "Invalid request body. Provide personalBestId, exerciseId, and measurement values.",
    };
  }

  const record = body as Record<string, unknown>;
  if (typeof record.exerciseId !== "string" || !isUuid(record.exerciseId)) {
    return {
      ok: false,
      error: "Invalid request body. Provide personalBestId, exerciseId, and measurement values.",
    };
  }
  if (
    typeof record.personalBestId !== "string" ||
    !isUuid(record.personalBestId)
  ) {
    return {
      ok: false,
      error: "Invalid request body. Provide personalBestId, exerciseId, and measurement values.",
    };
  }

  const achievedAt = parseAchievedAt(record.achievedAt);
  if (!achievedAt.ok) {
    return { ok: false, error: achievedAt.error };
  }

  return {
    ok: true,
    request: {
      exerciseId: record.exerciseId,
      personalBestId: record.personalBestId,
      weight: optionalNumber(record.weight),
      reps: optionalNumber(record.reps),
      time_seconds: optionalNumber(record.time_seconds),
      distance: optionalNumber(record.distance),
      achievedAt: achievedAt.value,
    },
  };
}

export const handleUpdateManualPBRequest = createEdgeRequestHandler(
  async (req, claims, authHeader) => {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const parsed = parseUpdateManualPBRequest(body);
    if (!parsed.ok) {
      return jsonResponse({ error: parsed.error }, 400);
    }
    const request = parsed.request;

    if (request.achievedAt != null && isFutureDate(request.achievedAt)) {
      return jsonResponse({ error: "achievedAt cannot be in the future" }, 400);
    }

    const supabase = createUserClient(authHeader);
    const exercise = await fetchExercise(supabase, request.exerciseId, claims.gymId);

    if (
      !validateMeasurementFields(exercise.measurement_type, {
        weight: request.weight,
        reps: request.reps,
        time_seconds: request.time_seconds,
        distance: request.distance,
      })
    ) {
      return jsonResponse(
        {
          error: `Missing required measurement fields for ${exercise.measurement_type}`,
        },
        400,
      );
    }

    const existing = await fetchPersonalBestById(
      supabase,
      request.personalBestId,
      claims.memberId,
      request.exerciseId,
      claims.gymId,
    );

    const now = new Date().toISOString();
    const { data, error } = await supabase
      .from("personal_bests")
      .update({
        weight: request.weight,
        reps: request.reps,
        time_seconds: request.time_seconds,
        distance: request.distance,
        achieved_at: request.achievedAt,
        updated_at: now,
      })
      .eq("id", existing.id)
      .select(
        "id, gym_id, member_id, exercise_id, set_id, weight, reps, time_seconds, distance, achieved_at, entry_type",
      )
      .single();

    if (error) {
      throw error;
    }

    return jsonResponse({
      personalBest: data as PersonalBestRow,
    }, 200);
  },
);
