/**
 * Reset Current PB — Supabase Edge Function
 *
 * Writes a reset_at date to exercise_resets (#28 step 4).
 * Pass undo: true to soft-delete the reset row and restore current standing.
 */

import {
  createUserClient,
  handleEdgeRequest,
  isUuid,
  jsonResponse,
  todayUtcDateString,
  type ExerciseResetRow,
} from "../_shared/member-edge.ts";
import {
  fetchExerciseResetAt,
  laterResetDate,
} from "../_shared/edge-pb-reads.ts";

interface ResetRequest {
  exerciseId: string;
  undo?: boolean;
  resetAt?: string;
}

function parseResetRequest(body: unknown): ResetRequest | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }

  const record = body as Record<string, unknown>;
  if (typeof record.exerciseId !== "string" || !isUuid(record.exerciseId)) {
    return null;
  }

  const undo = record.undo === true;
  const resetAt = typeof record.resetAt === "string" ? record.resetAt : undefined;

  return { exerciseId: record.exerciseId, undo, resetAt };
}

async function fetchExistingReset(
  supabase: ReturnType<typeof createUserClient>,
  memberId: string,
  exerciseId: string,
): Promise<ExerciseResetRow | null> {
  const { data, error } = await supabase
    .from("exercise_resets")
    .select("id, gym_id, member_id, exercise_id, reset_at, created_at, updated_at, deleted_at")
    .eq("member_id", memberId)
    .eq("exercise_id", exerciseId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return (data as ExerciseResetRow | null) ?? null;
}

handleEdgeRequest(async (req, claims, authHeader) => {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const request = parseResetRequest(body);
  if (!request) {
    return jsonResponse({ error: "Invalid request body. Provide exerciseId." }, 400);
  }

  const supabase = createUserClient(authHeader);
  const existing = await fetchExistingReset(
    supabase,
    claims.memberId,
    request.exerciseId,
  );

  if (request.undo) {
    if (!existing || existing.deleted_at) {
      return jsonResponse({ success: true, exerciseReset: null }, 200);
    }

    const now = new Date().toISOString();
    const { data, error } = await supabase
      .from("exercise_resets")
      .update({ deleted_at: now, updated_at: now })
      .eq("id", existing.id)
      .eq("member_id", claims.memberId)
      .eq("gym_id", claims.gymId)
      .select(
        "id, gym_id, member_id, exercise_id, reset_at, created_at, updated_at, deleted_at",
      )
      .single();

    if (error) {
      throw error;
    }

    return jsonResponse({
      success: true,
      exerciseReset: data as ExerciseResetRow,
    }, 200);
  }

  const resetAt = request.resetAt ?? todayUtcDateString();
  const now = new Date().toISOString();

  if (existing && !existing.deleted_at) {
    const mergedResetAt = laterResetDate(existing.reset_at, resetAt);
    const { data, error } = await supabase
      .from("exercise_resets")
      .update({ reset_at: mergedResetAt, updated_at: now, deleted_at: null })
      .eq("id", existing.id)
      .eq("member_id", claims.memberId)
      .eq("gym_id", claims.gymId)
      .select(
        "id, gym_id, member_id, exercise_id, reset_at, created_at, updated_at, deleted_at",
      )
      .single();

    if (error) {
      throw error;
    }

    return jsonResponse({
      success: true,
      exerciseReset: data as ExerciseResetRow,
    }, 200);
  }

  const id = existing?.id ?? crypto.randomUUID();
  const { data, error } = await supabase
    .from("exercise_resets")
    .upsert({
      id,
      gym_id: claims.gymId,
      member_id: claims.memberId,
      exercise_id: request.exerciseId,
      reset_at: resetAt,
      updated_at: now,
      deleted_at: null,
    })
    .select(
      "id, gym_id, member_id, exercise_id, reset_at, created_at, updated_at, deleted_at",
    )
    .single();

  if (error) {
    throw error;
  }

  return jsonResponse({
    success: true,
    exerciseReset: data as ExerciseResetRow,
  }, 200);
});
