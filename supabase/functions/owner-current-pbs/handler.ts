/**
 * Owner Current PBs — gym-wide current PB summary for the owner surface.
 *
 * Access is the RLS policy on owner_surface_grants (app_role = 'owner' and
 * gym_id match). This handler does not inspect app_role in application code.
 * Current PB values come from derivePBs via edge-pb-reads — not a SQL rewrite
 * of freshness / reset / tie-break.
 */

import {
  createEdgeRequestHandler,
  createUserClient,
  jsonResponse,
} from "../_shared/member-edge.ts";
import {
  deriveGymCurrentPBs,
  fetchOwnerSurfaceGrant,
} from "../_shared/edge-pb-reads.ts";

export const handleOwnerCurrentPBsRequest = createEdgeRequestHandler(
  async (_req, _claims, authHeader) => {
    const supabase = createUserClient(authHeader);
    const grantGymId = await fetchOwnerSurfaceGrant(supabase);
    if (grantGymId == null) {
      return jsonResponse({ error: "Forbidden" }, 403);
    }

    const currentPBs = await deriveGymCurrentPBs(supabase);
    return jsonResponse({ currentPBs }, 200);
  },
);
