/**
 * Gym kiosk log.
 *
 * POST /kiosk-log            owner JWT — list resolved names, or store a pending log and email a confirm link.
 * GET  /kiosk-log/confirm    public token — commit that pending row as one normal session.
 *
 * Pending rows live in kiosk_pending_sessions. Confirm calls commit_kiosk_pending,
 * which inserts sessions / exercise_entries / sets and deletes the pending row.
 * Nothing here writes a session before that click, and the token does not expire.
 */

import { fetchOwnerSurfaceGrant } from "../_shared/edge-pb-reads.ts";
import {
  buildKioskConfirmEmail,
  hashKioskToken,
  hasResolvedKioskName,
  newKioskToken,
  parseKioskSubmitBody,
  type KioskEmailExercise,
  type KioskNameRow,
} from "../_shared/kiosk-pending.ts";
import { REMINDER_FROM } from "../_shared/log-reminder-copy.ts";
import {
  corsHeaders,
  createServiceRoleClient,
  createUserClient,
  decodeJwtClaims,
  jsonResponse,
  logCaughtError,
} from "../_shared/member-edge.ts";

export interface KioskLogDeps {
  fetchImpl?: typeof fetch;
  token?: () => string;
}

interface MemberCandidate extends KioskNameRow {
  id: string;
}

function isConfirmPath(url: URL): boolean {
  return url.pathname.endsWith("/confirm");
}

async function requireOwnerGym(req: Request): Promise<{ gymId: string } | Response> {
  const authHeader = req.headers.get("Authorization");
  const claims = decodeJwtClaims(authHeader);
  if (!claims || !authHeader) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }
  try {
    const gymId = await fetchOwnerSurfaceGrant(createUserClient(authHeader));
    if (!gymId) return jsonResponse({ error: "Forbidden" }, 403);
    return { gymId };
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: "Unauthorized" }, 401);
  }
}

async function listResolvedMembers(gymId: string): Promise<Response> {
  const service = createServiceRoleClient();
  const { data, error } = await service
    .from("members")
    .select("id, display_name, teamup_email, teamup_roster_id, deleted_at")
    .eq("gym_id", gymId)
    .is("deleted_at", null);
  if (error) throw error;

  const members = ((data ?? []) as MemberCandidate[])
    .filter((row) => hasResolvedKioskName(row))
    .map((row) => ({
      member_id: row.id,
      display_name: row.display_name!.trim(),
    }))
    .sort((left, right) => left.display_name.localeCompare(right.display_name));

  return jsonResponse({ members }, 200);
}

async function loadMember(gymId: string, memberId: string): Promise<MemberCandidate | null> {
  const service = createServiceRoleClient();
  const { data, error } = await service
    .from("members")
    .select("id, display_name, teamup_email, teamup_roster_id, deleted_at")
    .eq("id", memberId)
    .eq("gym_id", gymId)
    .is("deleted_at", null)
    .maybeSingle();
  if (error) throw error;
  return (data as MemberCandidate | null) ?? null;
}

async function assertExercisesInGym(
  gymId: string,
  exerciseIds: string[],
): Promise<Map<string, { name: string }> | Response> {
  const service = createServiceRoleClient();
  const { data, error } = await service
    .from("exercises")
    .select("id, name, gym_id, is_active, deleted_at")
    .in("id", exerciseIds);
  if (error) throw error;
  const byId = new Map<string, { name: string; gym_id: string; is_active: boolean; deleted_at: string | null }>();
  for (const row of data ?? []) {
    const record = row as {
      id: string;
      name: string;
      gym_id: string;
      is_active: boolean;
      deleted_at: string | null;
    };
    byId.set(record.id, record);
  }
  const names = new Map<string, { name: string }>();
  for (const id of exerciseIds) {
    const row = byId.get(id);
    if (!row || row.deleted_at) {
      return jsonResponse({ error: "Exercise not found" }, 404);
    }
    if (row.gym_id !== gymId) {
      return jsonResponse({ error: "Exercise not in member gym" }, 403);
    }
    if (!row.is_active) {
      return jsonResponse({ error: "Exercise is not active" }, 400);
    }
    names.set(id, { name: row.name });
  }
  return names;
}

function rpcStatus(error: { message?: string; code?: string }): Response {
  const message = typeof error.message === "string" && error.message.length > 0
    ? error.message
    : "Internal server error";
  const pt = /^PT(\d{3})$/.exec(error.code ?? "");
  if (pt) {
    const status = Number(pt[1]);
    if (status >= 400 && status < 600) {
      return jsonResponse({ error: message }, status);
    }
  }
  if (message === "Pending log not found" || message === "Member not found") {
    return jsonResponse({ error: message }, 404);
  }
  return jsonResponse({ error: "Internal server error" }, 500);
}

async function submitPending(
  gymId: string,
  body: unknown,
  deps: KioskLogDeps,
): Promise<Response> {
  const parsed = parseKioskSubmitBody(body);
  if (!parsed.ok) return jsonResponse({ error: parsed.error }, 400);

  const member = await loadMember(gymId, parsed.request.memberId);
  if (!member || !hasResolvedKioskName(member)) {
    return jsonResponse({ error: "Member not found" }, 404);
  }
  const email = member.teamup_email!.trim();

  const exerciseIds = parsed.request.payload.exercises.map((exercise) => exercise.exerciseId);
  const names = await assertExercisesInGym(gymId, exerciseIds);
  if (names instanceof Response) return names;

  const token = (deps.token ?? newKioskToken)();
  const tokenHash = await hashKioskToken(token);
  const pendingId = crypto.randomUUID();
  const service = createServiceRoleClient();
  const inserted = await service.from("kiosk_pending_sessions").insert({
    id: pendingId,
    gym_id: gymId,
    member_id: member.id,
    session_date: parsed.request.session.date,
    notes: parsed.request.session.notes,
    calories_burned: parsed.request.session.calories_burned,
    payload: parsed.request.payload,
    token_hash: tokenHash,
  });
  if (inserted.error) throw inserted.error;

  const origin = Deno.env.get("MEMBER_WEB_ORIGIN")?.trim().replace(/\/$/, "");
  const resendKey = Deno.env.get("RESEND_API_KEY")?.trim();
  if (!origin || !resendKey) {
    await service.from("kiosk_pending_sessions").delete().eq("id", pendingId);
    return jsonResponse({ error: "Confirmation email is not configured" }, 503);
  }

  const confirmUrl = `${origin}/kiosk/confirm?token=${encodeURIComponent(token)}`;
  const exercises: KioskEmailExercise[] = parsed.request.payload.exercises.map((exercise) => {
    const set = exercise.sets[0]!;
    return {
      name: names.get(exercise.exerciseId)?.name ?? "Exercise",
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

  const fetchImpl = deps.fetchImpl ?? fetch;
  const resendRes = await fetchImpl("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: REMINDER_FROM,
      to: [email],
      subject: copy.subject,
      text: copy.text,
      html: copy.html,
    }),
  });
  if (!resendRes.ok) {
    await service.from("kiosk_pending_sessions").delete().eq("id", pendingId);
    return jsonResponse({ error: "Could not send the confirmation email" }, 502);
  }

  return jsonResponse({ ok: true }, 200);
}

async function confirmPending(req: Request): Promise<Response> {
  const token = new URL(req.url).searchParams.get("token")?.trim() ?? "";
  if (!token) return jsonResponse({ error: "Pending log not found" }, 404);
  const tokenHash = await hashKioskToken(token);
  const service = createServiceRoleClient();
  const { data, error } = await service.rpc("commit_kiosk_pending", {
    p_token_hash: tokenHash,
  });
  if (error) return rpcStatus(error);
  const sessionId = (data as { sessionId?: string } | null)?.sessionId ?? null;
  return jsonResponse({ ok: true, sessionId }, 200);
}

export async function handleKioskLogRequest(
  req: Request,
  deps: KioskLogDeps = {},
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const url = new URL(req.url);
  try {
    if (isConfirmPath(url)) {
      if (req.method !== "GET" && req.method !== "POST") {
        return jsonResponse({ error: "Method not allowed" }, 405);
      }
      return await confirmPending(req);
    }

    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    const owner = await requireOwnerGym(req);
    if (owner instanceof Response) return owner;

    let body: unknown = {};
    const contentType = req.headers.get("content-type") ?? "";
    if (contentType.includes("application/json")) {
      try {
        body = await req.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON body" }, 400);
      }
    }

    const action = typeof body === "object" && body !== null
      ? (body as { action?: unknown }).action
      : undefined;
    if (action === "members") return await listResolvedMembers(owner.gymId);
    if (action === "submit") return await submitPending(owner.gymId, body, deps);
    return jsonResponse({ error: "Unknown action" }, 400);
  } catch (error) {
    if (error instanceof Response) return error;
    logCaughtError("kiosk-log", error);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
}
