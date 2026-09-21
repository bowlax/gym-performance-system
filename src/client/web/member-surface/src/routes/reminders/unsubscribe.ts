import { createFileRoute } from "@tanstack/react-router";
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from "@/lib/gp/env";

function unsubscribeUpstream(token: string): string {
  const target = new URL(
    "functions/v1/log-reminders/unsubscribe",
    SUPABASE_URL.endsWith("/") ? SUPABASE_URL : `${SUPABASE_URL}/`,
  );
  target.searchParams.set("token", token);
  return target.toString();
}

async function proxyUnsubscribe(request: Request): Promise<Response> {
  const token = new URL(request.url).searchParams.get("token") ?? "";
  const upstream = await fetch(unsubscribeUpstream(token), {
    method: request.method,
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      "Content-Type": request.headers.get("Content-Type") ??
        "application/x-www-form-urlencoded",
    },
    body: request.method === "POST" ? await request.text() : undefined,
    redirect: "manual",
  });
  return new Response(await upstream.text(), {
    status: upstream.status,
    headers: {
      "Content-Type": upstream.headers.get("Content-Type") ??
        "text/html; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

export const Route = createFileRoute("/reminders/unsubscribe")({
  server: {
    handlers: {
      GET: async ({ request }) => proxyUnsubscribe(request),
      POST: async ({ request }) => proxyUnsubscribe(request),
    },
  },
});
