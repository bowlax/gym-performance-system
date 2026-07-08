/**
 * Delete Personal Best — Supabase Edge Function
 *
 * Soft-deletes a personal-best record and cascades current-PB promotion using
 * shared pb-cascade logic. Uses the caller's JWT (RLS enforced).
 *
 * iOS semantics:
 * - deletePersonalBest: removes PB; if was current, promotes bestRestorable.
 * - deleteHistoryEntry with setId: also removes the linked set.
 */

import { bestRestorable } from "../_shared/pb-cascade.ts";
import {
  createUserClient,
  fetchAllPersonalBests,
  fetchExercise,
  fetchPersonalBestById,
  handleEdgeRequest,
  isPbRule,
  isUuid,
  jsonResponse,
  softDeletePersonalBest,
  softDeleteSet,
  type PersonalBestRow,
  type SetRow,
} from "../_shared/member-edge.ts";

interface DeletePersonalBestRequest {
  exerciseId: string;
  personalBestId: string;
  setId?: string;
}

interface ExerciseEntryRow {
  id: string;
  exercise_id: string;
  session_id: string;
}

interface SessionRow {
  id: string;
  member_id: string;
  gym_id: string;
}

function parseDeleteRequest(body: unknown): DeletePersonalBestRequest | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }

  const record = body as Record<string, unknown>;
  if (typeof record.exerciseId !== "string" || !isUuid(record.exerciseId)) {
    return null;
  }
  if (
    typeof record.personalBestId !== "string" ||
    !isUuid(record.personalBestId)
  ) {
    return null;
  }

  let setId: string | undefined;
  if (record.setId != null) {
    if (typeof record.setId !== "string" || !isUuid(record.setId)) {
      return null;
    }
    setId = record.setId;
  }

  return {
    exerciseId: record.exerciseId,
    personalBestId: record.personalBestId,
    setId,
  };
}

async function verifySetOwnership(
  supabase: ReturnType<typeof createUserClient>,
  setId: string,
  exerciseId: string,
  memberId: string,
  gymId: string,
): Promise<SetRow> {
  const { data: setData, error: setError } = await supabase
    .from("sets")
    .select("id, gym_id, exercise_entry_id, weight, reps, time_seconds, distance")
    .eq("id", setId)
    .is("deleted_at", null)
    .maybeSingle();

  if (setError) {
    throw setError;
  }
  if (!setData) {
    throw jsonResponse({ error: "Set not found" }, 404);
  }

  const set = setData as SetRow;
  if (set.gym_id !== gymId) {
    throw jsonResponse({ error: "Forbidden" }, 403);
  }

  const { data: entryData, error: entryError } = await supabase
    .from("exercise_entries")
    .select("id, exercise_id, session_id")
    .eq("id", set.exercise_entry_id)
    .is("deleted_at", null)
    .maybeSingle();

  if (entryError) {
    throw entryError;
  }
  if (!entryData) {
    throw jsonResponse({ error: "Exercise entry not found" }, 404);
  }

  const entry = entryData as ExerciseEntryRow;
  if (entry.exercise_id !== exerciseId) {
    throw jsonResponse({ error: "Set does not belong to this exercise" }, 403);
  }

  const { data: sessionData, error: sessionError } = await supabase
    .from("sessions")
    .select("id, member_id, gym_id")
    .eq("id", entry.session_id)
    .is("deleted_at", null)
    .maybeSingle();

  if (sessionError) {
    throw sessionError;
  }
  if (!sessionData) {
    throw jsonResponse({ error: "Session not found" }, 404);
  }

  const session = sessionData as SessionRow;
  if (session.member_id !== memberId || session.gym_id !== gymId) {
    throw jsonResponse({ error: "Forbidden" }, 403);
  }

  return set;
}

function findPersonalBestForDeletedSet(
  allPBs: PersonalBestRow[],
  setId: string,
): PersonalBestRow | null {
  const matching = allPBs.filter((pb) => pb.set_id === setId);
  if (matching.length === 0) {
    return null;
  }

  const current = matching.find((pb) => pb.is_current);
  if (current) {
    return current;
  }

  return matching.reduce((best, candidate) =>
    candidate.achieved_at > best.achieved_at ? candidate : best
  );
}

async function promoteBestRestorable(
  supabase: ReturnType<typeof createUserClient>,
  memberId: string,
  exerciseId: string,
  gymId: string,
  pbRule: string,
): Promise<PersonalBestRow | null> {
  if (!isPbRule(pbRule)) {
    return null;
  }

  const remaining = await fetchAllPersonalBests(supabase, memberId, exerciseId);
  const selectedId = bestRestorable({
    rule: pbRule,
    records: remaining.map((pb) => ({
      id: pb.id,
      weight: pb.weight,
      reps: pb.reps,
      time: pb.time_seconds,
      distance: pb.distance,
      wasReset: pb.was_reset,
      setId: pb.set_id,
    })),
  });

  if (!selectedId) {
    return null;
  }

  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from("personal_bests")
    .update({ is_current: true, updated_at: now })
    .eq("id", selectedId)
    .eq("member_id", memberId)
    .eq("gym_id", gymId)
    .select(
      "id, gym_id, member_id, exercise_id, set_id, weight, reps, time_seconds, distance, achieved_at, is_current, was_reset, entry_type",
    )
    .single();

  if (error) {
    throw error;
  }

  return data as PersonalBestRow;
}

handleEdgeRequest(async (req, claims, authHeader) => {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const request = parseDeleteRequest(body);
  if (!request) {
    return jsonResponse(
      {
        error:
          "Invalid request body. Provide exerciseId and personalBestId.",
      },
      400,
    );
  }

  const supabase = createUserClient(authHeader);
  const exercise = await fetchExercise(supabase, request.exerciseId, claims.gymId);

  let deletedSet: SetRow | null = null;
  let targetPB: PersonalBestRow | null = null;

  if (request.setId) {
    deletedSet = await verifySetOwnership(
      supabase,
      request.setId,
      request.exerciseId,
      claims.memberId,
      claims.gymId,
    );

    const allPBs = await fetchAllPersonalBests(
      supabase,
      claims.memberId,
      request.exerciseId,
    );
    targetPB = findPersonalBestForDeletedSet(allPBs, request.setId);

    await softDeleteSet(supabase, request.setId);
  } else {
    targetPB = await fetchPersonalBestById(
      supabase,
      request.personalBestId,
      claims.memberId,
      request.exerciseId,
      claims.gymId,
    );
  }

  if (!targetPB) {
    return jsonResponse({
      deleted: null,
      deletedSet,
      newCurrent: null,
    }, 200);
  }

  const wasCurrent = targetPB.is_current;
  const deletedPB = { ...targetPB };

  await softDeletePersonalBest(supabase, targetPB.id);

  let newCurrent: PersonalBestRow | null = null;
  if (wasCurrent && exercise.pb_rule) {
    newCurrent = await promoteBestRestorable(
      supabase,
      claims.memberId,
      request.exerciseId,
      claims.gymId,
      exercise.pb_rule,
    );
  }

  return jsonResponse({
    deleted: deletedPB,
    deletedSet,
    newCurrent,
  }, 200);
});
