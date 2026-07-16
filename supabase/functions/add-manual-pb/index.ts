/**
 * Add Manual PB — Supabase Edge Function
 *
 * Records a manual personal-best entry. Compares against derived current PB (#28 step 4).
 * `achievedAt` may be null (undated lifetime entry) or a YYYY-MM-DD string.
 * Missing / null → store null. Invalid non-null string → 400 (never invent today).
 */

import {
  createUserClient,
  DATE_PATTERN,
  fetchExercise,
  handleEdgeRequest,
  isFutureDate,
  isPbRule,
  isUuid,
  jsonResponse,
  optionalNumber,
  validateMeasurementFields,
  type PersonalBestRow,
} from "../_shared/member-edge.ts";
import {
  deriveCurrentPBState,
  isManualPB,
} from "../_shared/edge-pb-reads.ts";

interface AddManualPBRequest {
  exerciseId: string;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
  /** Null = undated lifetime entry. */
  achievedAt: string | null;
}

type ParseResult =
  | { ok: true; request: AddManualPBRequest }
  | { ok: false; error: string };

function parseAchievedAt(raw: unknown): { ok: true; value: string | null } | { ok: false; error: string } {
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

function parseAddManualPBRequest(body: unknown): ParseResult {
  if (typeof body !== "object" || body === null) {
    return { ok: false, error: "Invalid request body. Provide exerciseId and measurement values." };
  }

  const record = body as Record<string, unknown>;
  if (typeof record.exerciseId !== "string" || !isUuid(record.exerciseId)) {
    return { ok: false, error: "Invalid request body. Provide exerciseId and measurement values." };
  }

  const achievedAt = parseAchievedAt(record.achievedAt);
  if (!achievedAt.ok) {
    return { ok: false, error: achievedAt.error };
  }

  return {
    ok: true,
    request: {
      exerciseId: record.exerciseId,
      weight: optionalNumber(record.weight),
      reps: optionalNumber(record.reps),
      time_seconds: optionalNumber(record.time_seconds),
      distance: optionalNumber(record.distance),
      achievedAt: achievedAt.value,
    },
  };
}

handleEdgeRequest(async (req, claims, authHeader) => {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const parsed = parseAddManualPBRequest(body);
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

  if (!exercise.pb_rule || !isPbRule(exercise.pb_rule)) {
    return jsonResponse({ isNewPB: false, personalBest: null }, 200);
  }

  const { currentPB } = await deriveCurrentPBState(
    supabase,
    claims.memberId,
    exercise,
  );

  const candidate = {
    weight: request.weight,
    reps: request.reps,
    time: request.time_seconds,
    distance: request.distance,
  };

  if (!isManualPB(exercise, currentPB, candidate)) {
    return jsonResponse({ isNewPB: false, personalBest: null }, 200);
  }

  const { data, error } = await supabase
    .from("personal_bests")
    .insert({
      id: crypto.randomUUID(),
      gym_id: claims.gymId,
      member_id: claims.memberId,
      exercise_id: request.exerciseId,
      set_id: null,
      weight: request.weight,
      reps: request.reps,
      time_seconds: request.time_seconds,
      distance: request.distance,
      achieved_at: request.achievedAt,
      entry_type: "manualEntry",
    })
    .select(
      "id, gym_id, member_id, exercise_id, set_id, weight, reps, time_seconds, distance, achieved_at, entry_type",
    )
    .single();

  if (error) {
    throw error;
  }

  return jsonResponse({
    isNewPB: true,
    personalBest: data as PersonalBestRow,
  }, 200);
});
