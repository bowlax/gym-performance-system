/**
 * Log-reminder Edge Function.
 *
 * POST  — cron-secret job (verify_jwt is off; do not use createEdgeRequestHandler).
 * GET/POST /unsubscribe — public signed-token opt-out (HTML page + Gmail one-click).
 */

import {
  corsHeaders,
  createServiceRoleClient,
  jsonResponse,
  logCaughtError,
} from "../_shared/member-edge.ts";
import { runLogReminderJob } from "../_shared/log-reminder-job.ts";
import { buildReminderCopy, REMINDER_FROM } from "../_shared/log-reminder-copy.ts";
import {
  signLogReminderOptOutToken,
  verifyLogReminderOptOutToken,
} from "../_shared/log-reminder-token.ts";

function timingSafeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i += 1) {
    mismatch |= a[i]! ^ b[i]!;
  }
  return mismatch === 0;
}

function cronAuthorized(req: Request): boolean {
  const expected = Deno.env.get("LOG_REMINDER_CRON_SECRET")?.trim();
  if (!expected) return false;
  const header = req.headers.get("Authorization") ?? "";
  const prefix = "Bearer ";
  if (!header.startsWith(prefix)) return false;
  return timingSafeEqual(header.slice(prefix.length), expected);
}

function htmlPage(status: number, message: string): Response {
  return new Response(
    `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>GymPerformance</title></head><body><p>${message}</p></body></html>`,
    {
      status,
      headers: {
        ...corsHeaders,
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
      },
    },
  );
}

function isUnsubscribePath(url: URL): boolean {
  return url.pathname.endsWith("/unsubscribe");
}

async function handleUnsubscribe(req: Request): Promise<Response> {
  if (req.method !== "GET" && req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const token = new URL(req.url).searchParams.get("token") ?? "";
  const secret = Deno.env.get("LOG_REMINDER_UNSUBSCRIBE_SECRET")?.trim();
  if (!secret) {
    return req.method === "GET"
      ? htmlPage(503, "Unsubscribe is not configured.")
      : jsonResponse({ error: "Unsubscribe is not configured" }, 503);
  }

  let memberId: string;
  try {
    ({ memberId } = await verifyLogReminderOptOutToken(token, secret));
  } catch {
    return req.method === "GET"
      ? htmlPage(400, "This unsubscribe link is invalid or has expired.")
      : jsonResponse({ error: "Invalid unsubscribe token" }, 400);
  }

  const service = createServiceRoleClient();
  const { error } = await service
    .from("members")
    .update({ log_reminder_email_opted_out_at: new Date().toISOString() })
    .eq("id", memberId)
    .is("deleted_at", null);
  if (error) throw error;

  return req.method === "GET"
    ? htmlPage(
      200,
      "You are unsubscribed from session reminder emails. You can turn them back on in Settings.",
    )
    : jsonResponse({ ok: true }, 200);
}

function parseNowMs(body: unknown): number {
  if (typeof body !== "object" || body === null) return Date.now();
  const raw = (body as { now?: unknown }).now;
  if (typeof raw !== "string" || raw.trim().length === 0) return Date.now();
  const parsed = Date.parse(raw);
  if (!Number.isFinite(parsed)) {
    throw jsonResponse({ error: "now must be an ISO timestamp" }, 400);
  }
  return parsed;
}

/** Live proof only — never a gym member address. */
function parseTestRecipient(body: unknown): string | null {
  if (typeof body !== "object" || body === null) return null;
  const raw = (body as { test_to?: unknown }).test_to;
  if (typeof raw !== "string") return null;
  const email = raw.trim().toLowerCase();
  if (!email.endsWith("@lbconsulting.tech")) return null;
  return email;
}

async function sendTestReminderEmail(
  to: string,
): Promise<{ id: string | null }> {
  const resendKey = Deno.env.get("RESEND_API_KEY")?.trim();
  if (!resendKey) throw new Error("RESEND_API_KEY is not configured");
  const memberWeb = Deno.env.get("MEMBER_WEB_ORIGIN")?.trim()?.replace(
    /\/$/,
    "",
  );
  if (!memberWeb) throw new Error("MEMBER_WEB_ORIGIN is not configured");
  const unsubSecret = Deno.env.get("LOG_REMINDER_UNSUBSCRIBE_SECRET")?.trim();
  const token = unsubSecret
    ? await signLogReminderOptOutToken(crypto.randomUUID(), unsubSecret)
    : "test";
  const unsubscribeUrl =
    `${memberWeb}/reminders/unsubscribe?token=${encodeURIComponent(token)}`;
  const copy = buildReminderCopy(
    "morning",
    [{ name: "Test class", startsAt: "2026-07-15T07:15:00.000Z" }],
    `${memberWeb}/log`,
    unsubscribeUrl,
    "Lee Ball",
  );
  const resendRes = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
        from: REMINDER_FROM,
      to: [to],
      subject: copy.subject,
      text: copy.text,
      html: copy.html,
      headers: {
        "List-Unsubscribe": `<${unsubscribeUrl}>`,
        "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
      },
    }),
  });
  const payload = await resendRes.json() as { id?: unknown; message?: unknown };
  if (!resendRes.ok) {
    throw new Error(
      `Resend failed (${resendRes.status}): ${String(payload.message ?? "").slice(0, 200)}`,
    );
  }
  return { id: typeof payload.id === "string" ? payload.id : null };
}

export async function handleLogRemindersRequest(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    if (isUnsubscribePath(url)) {
      return await handleUnsubscribe(req);
    }

    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }
    if (!cronAuthorized(req)) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    let body: unknown = {};
    const contentType = req.headers.get("content-type") ?? "";
    if (contentType.includes("application/json")) {
      try {
        const text = await req.text();
        body = text.length > 0 ? JSON.parse(text) : {};
      } catch {
        return jsonResponse({ error: "Invalid JSON body" }, 400);
      }
    }

    if (typeof body === "object" && body !== null && "test_to" in body) {
      const testTo = parseTestRecipient(body);
      if (!testTo) {
        return jsonResponse(
          { error: "test_to must be an @lbconsulting.tech address" },
          400,
        );
      }
      const sent = await sendTestReminderEmail(testTo);
      return jsonResponse({ test: true, to: testTo, id: sent.id }, 200);
    }

    const result = await runLogReminderJob({
      nowMs: parseNowMs(body),
      fetchImpl: fetch,
    });
    return jsonResponse({ ...result }, 200);
  } catch (error) {
    if (error instanceof Response) return error;
    logCaughtError("log-reminders", error);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
}
