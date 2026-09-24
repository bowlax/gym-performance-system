import "@tanstack/react-start/server-only";

import { kioskMemberOptions } from "@gp-shared/kiosk-names.ts";
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from "./env";
import { confirmKioskPending } from "./kiosk-save.server";
import { readFreshKioskSession } from "./kiosk-session.server";

const NO_STORE = { "Cache-Control": "private, no-store" };

function supabaseOrigin(): string {
  if (!SUPABASE_URL || !SUPABASE_PUBLISHABLE_KEY) {
    throw new Error("Supabase public config missing on server");
  }
  return SUPABASE_URL.endsWith("/") ? SUPABASE_URL : `${SUPABASE_URL}/`;
}

export async function kioskOwnerHeaders(): Promise<Headers | Response> {
  const session = await readFreshKioskSession();
  if (!session) {
    return Response.json({ error: "Unauthorized" }, { status: 401, headers: NO_STORE });
  }
  return new Headers({
    Authorization: `Bearer ${session.accessToken}`,
    apikey: SUPABASE_PUBLISHABLE_KEY,
    "Content-Type": "application/json",
  });
}

function upstreamErrorMessage(text: string, fallback: string): string {
  try {
    const body = JSON.parse(text) as { error?: unknown; message?: unknown };
    if (typeof body.error === "string" && body.error.length > 0) return body.error;
    if (typeof body.message === "string" && body.message.length > 0) return body.message;
  } catch {
    // Not JSON.
  }
  return fallback;
}

/**
 * Names come from PostgREST `members`, not the kiosk-log edge function.
 * That function is not deployed yet; calling it returned 404 and the picker
 * stayed empty. Owner JWTs may select members in their gym (members_read).
 * Email and roster id are used only to decide who is listed.
 */
export async function listKioskMembers(): Promise<Response> {
  const headers = await kioskOwnerHeaders();
  if (headers instanceof Response) return headers;
  headers.set("Accept", "application/json");
  const target = new URL("rest/v1/members", supabaseOrigin());
  target.searchParams.set(
    "select",
    "id,display_name,teamup_email,teamup_roster_id,deleted_at",
  );
  target.searchParams.set("deleted_at", "is.null");
  const upstream = await fetch(target, { method: "GET", headers });
  const text = await upstream.text();
  if (!upstream.ok) {
    return Response.json(
      { error: upstreamErrorMessage(text, "Could not load members.") },
      { status: upstream.status, headers: NO_STORE },
    );
  }
  let rows: unknown;
  try {
    rows = JSON.parse(text);
  } catch {
    return Response.json(
      { error: "Could not load members." },
      { status: 502, headers: NO_STORE },
    );
  }
  if (!Array.isArray(rows)) {
    return Response.json(
      { error: "Could not load members." },
      { status: 502, headers: NO_STORE },
    );
  }
  return Response.json(
    { members: kioskMemberOptions(rows) },
    { headers: NO_STORE },
  );
}

export async function proxyKioskExercises(): Promise<Response> {
  const headers = await kioskOwnerHeaders();
  if (headers instanceof Response) return headers;
  headers.set("Accept", "application/json");
  const target = new URL("rest/v1/exercises", supabaseOrigin());
  target.searchParams.set(
    "select",
    "id,name,measurement_type,display_order,pb_rule",
  );
  target.searchParams.set("is_active", "eq.true");
  target.searchParams.set("deleted_at", "is.null");
  target.searchParams.set("order", "display_order.asc");
  const upstream = await fetch(target, { method: "GET", headers });
  const text = await upstream.text();
  return new Response(text, {
    status: upstream.status,
    headers: { ...NO_STORE, "Content-Type": "application/json" },
  });
}

export async function confirmKioskToken(token: string): Promise<Response> {
  return confirmKioskPending(token);
}
