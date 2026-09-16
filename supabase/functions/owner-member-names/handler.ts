/**
 * Owner member names — cache TeamUp roster names onto members.display_name.
 *
 * Join is GET /customers?query=<members.teamup_email> (M2M), not roster id.
 * JWT `sub` and ProviderCustomerProfile id are different namespaces.
 * TeamUp is contacted only on refresh. Writes use the service role because
 * members_update_own is self-only.
 *
 * Members with no teamup_email (never connected after email capture, JWT
 * omitted email, or family dependants without email) keep display_name
 * 'Member'.
 */

import {
  createEdgeRequestHandler,
  createServiceRoleClient,
  createUserClient,
  jsonResponse,
} from "../_shared/member-edge.ts";
import { fetchOwnerSurfaceGrant } from "../_shared/edge-pb-reads.ts";
import {
  customerDisplayName,
  detectTeamUpAuthPrefix,
  lookupCustomerByEmail,
} from "../_shared/teamup-customers.ts";

export {
  customerDisplayName,
  customerEmail,
  emailsMatch,
  pickCustomerByEmail,
} from "../_shared/teamup-customers.ts";

export interface OwnerMemberNameRow {
  member_id: string;
  teamup_customer_id: string | null;
  display_name: string;
}

interface MemberSyncRow extends OwnerMemberNameRow {
  teamup_email: string | null;
}

async function listMembersForSync(grantGymId: string): Promise<MemberSyncRow[]> {
  const service = createServiceRoleClient();
  const { data, error } = await service
    .from("members")
    .select("id, teamup_customer_id, display_name, teamup_email")
    .eq("gym_id", grantGymId)
    .is("deleted_at", null);

  if (error) throw error;

  const rows: MemberSyncRow[] = [];
  for (const row of data ?? []) {
    const record = row as {
      id?: unknown;
      teamup_customer_id?: unknown;
      display_name?: unknown;
      teamup_email?: unknown;
    };
    if (typeof record.id !== "string") continue;
    rows.push({
      member_id: record.id,
      teamup_customer_id:
        typeof record.teamup_customer_id === "string"
          ? record.teamup_customer_id
          : null,
      display_name:
        typeof record.display_name === "string" ? record.display_name : "Member",
      teamup_email:
        typeof record.teamup_email === "string" ? record.teamup_email : null,
    });
  }
  return rows;
}

function toPublicRows(rows: MemberSyncRow[]): OwnerMemberNameRow[] {
  return rows.map((row) => ({
    member_id: row.member_id,
    teamup_customer_id: row.teamup_customer_id,
    display_name: row.display_name,
  }));
}

export async function syncNamesFromTeamUp(grantGymId: string): Promise<number> {
  const token = Deno.env.get("TEAMUP_M2M_TOKEN")?.trim();
  const providerId = Deno.env.get("TEAMUP_OAUTH_PROVIDER_ID")?.trim();
  if (!token || !providerId) {
    throw jsonResponse({ error: "TeamUp M2M is not configured" }, 503);
  }

  const prefix = await detectTeamUpAuthPrefix(token, providerId);
  const members = await listMembersForSync(grantGymId);
  const service = createServiceRoleClient();
  let updated = 0;

  for (const member of members) {
    if (!member.teamup_email) continue;
    const record = await lookupCustomerByEmail(
      token,
      providerId,
      prefix,
      member.teamup_email,
    );
    const name = record ? customerDisplayName(record) : null;
    if (!name || name === member.display_name) continue;
    const { error } = await service
      .from("members")
      .update({ display_name: name })
      .eq("id", member.member_id)
      .eq("gym_id", grantGymId);
    if (error) throw error;
    updated += 1;
  }

  return updated;
}

function wantsRefresh(req: Request, body: unknown): boolean {
  const url = new URL(req.url);
  if (url.searchParams.get("refresh") === "1") return true;
  if (typeof body === "object" && body !== null) {
    return (body as { refresh?: unknown }).refresh === true;
  }
  return false;
}

export const handleOwnerMemberNamesRequest = createEdgeRequestHandler(
  async (req, _claims, authHeader) => {
    const supabase = createUserClient(authHeader);
    const grantGymId = await fetchOwnerSurfaceGrant(supabase);
    if (grantGymId == null) {
      return jsonResponse({ error: "Forbidden" }, 403);
    }

    let body: unknown = {};
    const contentType = req.headers.get("content-type") ?? "";
    if (contentType.includes("application/json")) {
      try {
        body = await req.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON body" }, 400);
      }
    }

    if (wantsRefresh(req, body)) {
      try {
        await syncNamesFromTeamUp(grantGymId);
      } catch (error) {
        if (error instanceof Response) return error;
        throw error;
      }
    }

    const members = toPublicRows(await listMembersForSync(grantGymId));
    return jsonResponse({ members }, 200);
  },
);
