/**
 * Owner member names — cache TeamUp roster names onto members.display_name.
 *
 * Access is owner_surface_grants (same gate as other owner functions).
 * TeamUp is contacted only on refresh, never on a plain list.
 * Writes use the service role because members_update_own is self-only.
 */

import {
  createEdgeRequestHandler,
  createServiceRoleClient,
  createUserClient,
  jsonResponse,
  optionalString,
} from "../_shared/member-edge.ts";
import { fetchOwnerSurfaceGrant } from "../_shared/edge-pb-reads.ts";

const TEAMUP_CUSTOMERS_URL = "https://goteamup.com/api/v2/customers";
const AUTH_PREFIXES = ["Bearer", "Token", "JWT"] as const;

export interface OwnerMemberNameRow {
  member_id: string;
  teamup_customer_id: string | null;
  display_name: string;
}

interface TeamUpCustomerPage {
  count?: number;
  next?: string | null;
  results?: unknown[];
}

function customerDisplayName(record: Record<string, unknown>): string | null {
  const combined = optionalString(record.name);
  if (combined && combined.trim().length > 0) return combined.trim();

  const first =
    optionalString(record.first_name) ?? optionalString(record.firstName);
  const last =
    optionalString(record.last_name) ?? optionalString(record.lastName);
  const joined = [first, last].filter((part) => part && part.trim().length > 0)
    .join(" ")
    .trim();
  return joined.length > 0 ? joined : null;
}

function customerId(record: Record<string, unknown>): string | null {
  const id = record.id;
  if (typeof id === "number" && Number.isFinite(id)) return String(id);
  if (typeof id === "string" && id.length > 0) return id;
  return null;
}

async function teamUpGetCustomers(
  token: string,
  providerId: string,
  prefix: string,
  page: number,
): Promise<{ ok: true; json: TeamUpCustomerPage } | { ok: false; status: number }> {
  const url = new URL(TEAMUP_CUSTOMERS_URL);
  url.searchParams.set("page", String(page));
  url.searchParams.set("page_size", "100");

  const response = await fetch(url, {
    headers: {
      Authorization: `${prefix} ${token}`,
      "TeamUp-Provider-ID": providerId,
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    return { ok: false, status: response.status };
  }

  const json = await response.json() as TeamUpCustomerPage;
  return { ok: true, json };
}

export async function detectTeamUpAuthPrefix(
  token: string,
  providerId: string,
): Promise<string> {
  for (const prefix of AUTH_PREFIXES) {
    const result = await teamUpGetCustomers(token, providerId, prefix, 1);
    if (result.ok) return prefix;
  }
  throw new Error("TeamUp customers list rejected every auth prefix");
}

export async function fetchAllTeamUpCustomerNames(
  token: string,
  providerId: string,
  prefix: string,
): Promise<Map<string, string>> {
  const names = new Map<string, string>();
  let page = 1;
  while (true) {
    const result = await teamUpGetCustomers(token, providerId, prefix, page);
    if (!result.ok) {
      throw new Error(`TeamUp customers page ${page} failed`);
    }
    const rows = Array.isArray(result.json.results) ? result.json.results : [];
    for (const row of rows) {
      if (typeof row !== "object" || row === null) continue;
      const record = row as Record<string, unknown>;
      const id = customerId(record);
      const name = customerDisplayName(record);
      if (id && name) names.set(id, name);
    }
    if (!result.json.next || rows.length === 0) break;
    page += 1;
    if (page > 50) break;
  }
  return names;
}

async function listMemberNames(
  grantGymId: string,
): Promise<OwnerMemberNameRow[]> {
  const service = createServiceRoleClient();
  const { data, error } = await service
    .from("members")
    .select("id, teamup_customer_id, display_name")
    .eq("gym_id", grantGymId)
    .is("deleted_at", null);

  if (error) throw error;

  const rows: OwnerMemberNameRow[] = [];
  for (const row of data ?? []) {
    const record = row as {
      id?: unknown;
      teamup_customer_id?: unknown;
      display_name?: unknown;
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
    });
  }
  return rows;
}

async function syncNamesFromTeamUp(grantGymId: string): Promise<number> {
  const token = Deno.env.get("TEAMUP_M2M_TOKEN")?.trim();
  const providerId = Deno.env.get("TEAMUP_OAUTH_PROVIDER_ID")?.trim();
  if (!token || !providerId) {
    throw jsonResponse({ error: "TeamUp M2M is not configured" }, 503);
  }

  const prefix = await detectTeamUpAuthPrefix(token, providerId);
  const names = await fetchAllTeamUpCustomerNames(token, providerId, prefix);
  const members = await listMemberNames(grantGymId);
  const service = createServiceRoleClient();
  let updated = 0;

  for (const member of members) {
    if (!member.teamup_customer_id) continue;
    const name = names.get(member.teamup_customer_id);
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

    const members = await listMemberNames(grantGymId);
    return jsonResponse({ members }, 200);
  },
);
