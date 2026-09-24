import "@tanstack/react-start/server-only";

import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from "./env";
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

export async function proxyKioskFunction(body: unknown): Promise<Response> {
  const headers = await kioskOwnerHeaders();
  if (headers instanceof Response) return headers;
  const target = new URL("functions/v1/kiosk-log", supabaseOrigin());
  const upstream = await fetch(target, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  const text = await upstream.text();
  return new Response(text, {
    status: upstream.status,
    headers: { ...NO_STORE, "Content-Type": "application/json" },
  });
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
  const target = new URL("functions/v1/kiosk-log/confirm", supabaseOrigin());
  target.searchParams.set("token", token);
  return await fetch(target, {
    method: "GET",
    headers: { apikey: SUPABASE_PUBLISHABLE_KEY },
  });
}
