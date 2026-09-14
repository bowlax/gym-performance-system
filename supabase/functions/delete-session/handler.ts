/**
 * Delete Session — cascade tombstone a session and every child entry/set.
 *
 * Matches iOS `deleteSession`: stamp `deleted_at` + `updated_at` on the
 * session and its full child tree. Never hard-delete.
 */

import {
  createEdgeRequestHandler,
  createUserClient,
  isUuid,
  jsonResponse,
  softDeleteSessionCascade,
} from "../_shared/member-edge.ts";

interface DeleteSessionRequest {
  sessionId: string;
}

function parseDeleteSessionRequest(body: unknown): DeleteSessionRequest | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }

  const record = body as Record<string, unknown>;
  if (typeof record.sessionId !== "string" || !isUuid(record.sessionId)) {
    return null;
  }

  return { sessionId: record.sessionId };
}

export const handleDeleteSessionRequest = createEdgeRequestHandler(
  async (req, claims, authHeader) => {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const request = parseDeleteSessionRequest(body);
    if (!request) {
      return jsonResponse(
        { error: "Invalid request body. Provide sessionId." },
        400,
      );
    }

    const supabase = createUserClient(authHeader);
    await softDeleteSessionCascade(supabase, request.sessionId, claims.memberId);

    return jsonResponse({ deleted: { id: request.sessionId } }, 200);
  },
);
