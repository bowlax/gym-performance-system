import "@tanstack/react-start/server-only";

import {
  buildKioskConfirmEmail,
  hashKioskToken,
  hasResolvedKioskName,
  newKioskToken,
  parseKioskSubmitBody,
  type KioskEmailExercise,
  type KioskNameRow,
} from "@gp-shared/kiosk-names.ts";
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from "./env";
import { readFreshKioskSession } from "./kiosk-session.server";

const NO_STORE = { "Cache-Control": "private, no-store" };
const REMINDER_FROM = "Wolf Reminders <reminders@lbconsulting.tech>";

function json(status: number, body: Record<string, unknown>): Response {
  return Response.json(body, { status, headers: NO_STORE });
}

function runtimeEnv(name: string): string {
  const fromProcess =
    typeof process !== "undefined" ? process.env[name] : undefined;
  const fromNitro =
    typeof globalThis !== "undefined"
      ? (globalThis as { __env__?: Record<string, string | undefined> }).__env__?.[name]
      : undefined;
  return (fromProcess ?? fromNitro ?? "").trim();
}

function supabaseOrigin(): string {
  const base = SUPABASE_URL.endsWith("/") ? SUPABASE_URL : `${SUPABASE_URL}/`;
  return base;
}

async function ownerHeaders(): Promise<Headers | Response> {
  const session = await readFreshKioskSession();
  if (!session) return json(401, { error: "Unauthorized" });
  return new Headers({
    Authorization: `Bearer ${session.accessToken}`,
    apikey: SUPABASE_PUBLISHABLE_KEY,
    Accept: "application/json",
    "Content-Type": "application/json",
  });
}

function errorMessage(text: string, fallback: string): string {
  try {
    const body = JSON.parse(text) as {
      message?: unknown;
      error?: unknown;
      code?: unknown;
    };
    if (body.code === "PGRST205") {
      return "Kiosk save is not available yet. The pending-sessions table is not on Wolf.";
    }
    if (typeof body.message === "string" && body.message.length > 0) return body.message;
    if (typeof body.error === "string" && body.error.length > 0) return body.error;
  } catch {
    // Not JSON.
  }
  return fallback;
}

async function deletePending(headers: Headers, id: string): Promise<void> {
  const target = new URL("rest/v1/kiosk_pending_sessions", supabaseOrigin());
  target.searchParams.set("id", `eq.${id}`);
  await fetch(target, {
    method: "DELETE",
    headers: new Headers({
      ...Object.fromEntries(headers.entries()),
      Prefer: "return=minimal",
    }),
  });
}

export async function submitKioskSession(
  request: Request,
  body: unknown,
): Promise<Response> {
  const headers = await ownerHeaders();
  if (headers instanceof Response) return headers;

  const parsed = parseKioskSubmitBody(body);
  if (!parsed.ok) return json(400, { error: parsed.error });

  const memberTarget = new URL("rest/v1/members", supabaseOrigin());
  memberTarget.searchParams.set(
    "select",
    "id,gym_id,display_name,teamup_email,teamup_roster_id,deleted_at",
  );
  memberTarget.searchParams.set("id", `eq.${parsed.request.memberId}`);
  memberTarget.searchParams.set("deleted_at", "is.null");
  const memberRes = await fetch(memberTarget, { headers });
  const memberText = await memberRes.text();
  if (!memberRes.ok) {
    return json(memberRes.status, { error: errorMessage(memberText, "Could not load that member.") });
  }
  const memberRows = JSON.parse(memberText) as Array<KioskNameRow & { id: string; gym_id: string }>;
  const member = memberRows[0];
  if (!member || !hasResolvedKioskName(member)) {
    return json(404, { error: "Member not found" });
  }

  const exerciseIds = parsed.request.payload.exercises.map((exercise) => exercise.exerciseId);
  const exerciseTarget = new URL("rest/v1/exercises", supabaseOrigin());
  exerciseTarget.searchParams.set("select", "id,name,is_active,deleted_at");
  exerciseTarget.searchParams.set("id", `in.(${exerciseIds.join(",")})`);
  const exerciseRes = await fetch(exerciseTarget, { headers });
  const exerciseText = await exerciseRes.text();
  if (!exerciseRes.ok) {
    return json(exerciseRes.status, {
      error: errorMessage(exerciseText, "Could not load exercises."),
    });
  }
  const exerciseRows = JSON.parse(exerciseText) as Array<{
    id: string;
    name: string;
    is_active: boolean;
    deleted_at: string | null;
  }>;
  const byId = new Map(exerciseRows.map((row) => [row.id, row]));
  for (const id of exerciseIds) {
    const row = byId.get(id);
    if (!row || row.deleted_at) return json(404, { error: "Exercise not found" });
    if (!row.is_active) return json(400, { error: "Exercise is not active" });
  }

  const token = newKioskToken();
  const tokenHash = await hashKioskToken(token);
  const pendingId = crypto.randomUUID();
  const insertTarget = new URL("rest/v1/kiosk_pending_sessions", supabaseOrigin());
  const insertRes = await fetch(insertTarget, {
    method: "POST",
    headers: new Headers({
      ...Object.fromEntries(headers.entries()),
      Prefer: "return=minimal",
    }),
    body: JSON.stringify({
      id: pendingId,
      gym_id: member.gym_id,
      member_id: member.id,
      session_date: parsed.request.session.date,
      notes: parsed.request.session.notes,
      calories_burned: parsed.request.session.calories_burned,
      payload: parsed.request.payload,
      token_hash: tokenHash,
    }),
  });
  if (!insertRes.ok) {
    const text = await insertRes.text();
    return json(insertRes.status, {
      error: errorMessage(text, "Could not store the kiosk log."),
    });
  }

  const resendKey = runtimeEnv("RESEND_API_KEY");
  const origin = new URL(request.url).origin;
  if (!resendKey) {
    await deletePending(headers, pendingId);
    return json(503, { error: "Confirmation email is not configured" });
  }

  const confirmUrl = `${origin}/kiosk/confirm?token=${encodeURIComponent(token)}`;
  const exercises: KioskEmailExercise[] = parsed.request.payload.exercises.map((exercise) => {
    const set = exercise.sets[0]!;
    return {
      name: byId.get(exercise.exerciseId)?.name ?? "Exercise",
      weight: set.weight,
      reps: set.reps,
      time_seconds: set.time_seconds,
      distance: set.distance,
    };
  });
  const copy = buildKioskConfirmEmail({
    displayName: member.display_name!.trim(),
    sessionDate: parsed.request.session.date,
    exercises,
    confirmUrl,
  });
  const resendRes = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: REMINDER_FROM,
      to: [member.teamup_email!.trim()],
      subject: copy.subject,
      text: copy.text,
      html: copy.html,
    }),
  });
  if (!resendRes.ok) {
    await deletePending(headers, pendingId);
    return json(502, { error: "Could not send the confirmation email" });
  }

  return json(200, { ok: true });
}

/** Confirm writes a live session. Submit does not. */
export async function confirmKioskPending(token: string): Promise<Response> {
  const tokenHash = await hashKioskToken(token.trim());
  const target = new URL("rest/v1/rpc/commit_kiosk_pending", supabaseOrigin());
  return await fetch(target, {
    method: "POST",
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${SUPABASE_PUBLISHABLE_KEY}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({ p_token_hash: tokenHash }),
  });
}
