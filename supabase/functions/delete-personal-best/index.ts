/**
 * Delete Personal Best — Supabase Edge Function
 *
 * Soft-deletes a manual personal-best entry (#28 step 4).
 * Set deletion is handled separately via direct set soft-delete (RLS).
 */

import {
  createUserClient,
  fetchPersonalBestById,
  handleEdgeRequest,
  isUuid,
  jsonResponse,
  softDeletePersonalBest,
  type PersonalBestRow,
} from "../_shared/member-edge.ts";

interface DeletePersonalBestRequest {
  exerciseId: string;
  personalBestId: string;
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

  return {
    exerciseId: record.exerciseId,
    personalBestId: record.personalBestId,
  };
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
  const targetPB = await fetchPersonalBestById(
    supabase,
    request.personalBestId,
    claims.memberId,
    request.exerciseId,
    claims.gymId,
  );

  const deletedPB: PersonalBestRow = { ...targetPB };
  await softDeletePersonalBest(supabase, targetPB.id);

  return jsonResponse({ deleted: deletedPB }, 200);
});
