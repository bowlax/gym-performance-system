/**
 * Add Manual PB — Supabase Edge Function
 *
 * Records a manual personal-best entry for a web member. Uses the caller's JWT
 * (RLS enforced) and shared pb-evaluation logic.
 *
 * iOS semantics (DefaultMemberPerformance.recordManualPB):
 * - If the entry is not a PB, nothing is persisted; returns isNewPB false.
 * - If it is a PB, supersedes the current PB and inserts a manualEntry row.
 */

import { evaluatePB } from "../_shared/pb-evaluation.ts";
import {
  createUserClient,
  DATE_PATTERN,
  fetchCurrentPersonalBest,
  fetchExercise,
  handleEdgeRequest,
  isFutureDate,
  isPbRule,
  isUuid,
  jsonResponse,
  optionalNumber,
  personalBestToEvaluationState,
  todayUtcDateString,
  validateMeasurementFields,
  type PersonalBestRow,
} from "../_shared/member-edge.ts";

interface AddManualPBRequest {
  exerciseId: string;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
  achievedAt: string;
}

function parseAddManualPBRequest(body: unknown): AddManualPBRequest | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }

  const record = body as Record<string, unknown>;
  if (typeof record.exerciseId !== "string" || !isUuid(record.exerciseId)) {
    return null;
  }

  const achievedAtRaw = record.achievedAt;
  const achievedAt = typeof achievedAtRaw === "string" && DATE_PATTERN.test(achievedAtRaw)
    ? achievedAtRaw
    : todayUtcDateString();

  return {
    exerciseId: record.exerciseId,
    weight: optionalNumber(record.weight),
    reps: optionalNumber(record.reps),
    time_seconds: optionalNumber(record.time_seconds),
    distance: optionalNumber(record.distance),
    achievedAt,
  };
}

handleEdgeRequest(async (req, claims, authHeader) => {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const request = parseAddManualPBRequest(body);
  if (!request) {
    return jsonResponse(
      { error: "Invalid request body. Provide exerciseId and measurement values." },
      400,
    );
  }

  if (isFutureDate(request.achievedAt)) {
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

  const currentPB = await fetchCurrentPersonalBest(
    supabase,
    claims.memberId,
    request.exerciseId,
  );

  const evaluation = evaluatePB({
    rule: exercise.pb_rule,
    currentPB: currentPB ? personalBestToEvaluationState(currentPB) : null,
    newSet: {
      weight: request.weight,
      reps: request.reps,
      time: request.time_seconds,
      distance: request.distance,
    },
    ruleParameters: {
      targetReps: exercise.target_reps,
      minimumReps: exercise.minimum_reps,
    },
  });

  if (!evaluation.isPB) {
    return jsonResponse({ isNewPB: false, personalBest: null }, 200);
  }

  if (currentPB) {
    const { error: supersedeError } = await supabase
      .from("personal_bests")
      .update({ is_current: false, updated_at: new Date().toISOString() })
      .eq("id", currentPB.id)
      .eq("member_id", claims.memberId)
      .eq("gym_id", claims.gymId);

    if (supersedeError) {
      throw supersedeError;
    }
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
      is_current: true,
      entry_type: "manualEntry",
      was_reset: false,
    })
    .select(
      "id, gym_id, member_id, exercise_id, set_id, weight, reps, time_seconds, distance, achieved_at, is_current, was_reset, entry_type",
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
