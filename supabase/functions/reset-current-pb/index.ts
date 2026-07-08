/**
 * Reset Current PB — Supabase Edge Function
 *
 * Marks the member's current PB for an exercise as reset. Uses the caller's JWT
 * (RLS enforced).
 *
 * iOS semantics (DefaultMemberPerformance.resetCurrentPB):
 * - Sets was_reset true and is_current false on the current PB.
 * - Does NOT promote a replacement; board shows no current PB until a new one
 *   is logged.
 * - No-op when no current PB exists.
 */

import {
  createUserClient,
  fetchCurrentPersonalBest,
  handleEdgeRequest,
  isUuid,
  jsonResponse,
  type PersonalBestRow,
} from "../_shared/member-edge.ts";

function parseResetRequest(body: unknown): { exerciseId: string } | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }

  const record = body as Record<string, unknown>;
  if (typeof record.exerciseId !== "string" || !isUuid(record.exerciseId)) {
    return null;
  }

  return { exerciseId: record.exerciseId };
}

handleEdgeRequest(async (req, _claims, authHeader) => {
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
  const currentPB = await fetchCurrentPersonalBest(
    supabase,
    _claims.memberId,
    request.exerciseId,
  );

  if (!currentPB) {
    return jsonResponse({ success: true, resetRecord: null }, 200);
  }

  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from("personal_bests")
    .update({
      was_reset: true,
      is_current: false,
      updated_at: now,
    })
    .eq("id", currentPB.id)
    .eq("member_id", _claims.memberId)
    .eq("gym_id", _claims.gymId)
    .select(
      "id, gym_id, member_id, exercise_id, set_id, weight, reps, time_seconds, distance, achieved_at, is_current, was_reset, entry_type",
    )
    .single();

  if (error) {
    throw error;
  }

  return jsonResponse({
    success: true,
    resetRecord: data as PersonalBestRow,
  }, 200);
});
