/**
 * Member confirmation of a kiosk pending log.
 *
 * The email link carries the raw confirm secret. Wolf stores only its SHA-256
 * hex digest. The page posts that digest to commit_kiosk_pending as the
 * signed-in member. There is no select policy on kiosk_pending_sessions.
 */

export const KIOSK_CONFIRM_INVALID_MESSAGE = "This confirmation link is not valid.";

const TOKEN = /^[A-Za-z0-9_-]{20,}$/;
const RETURN_PATH = /^\/kiosk\/confirm\?token=[A-Za-z0-9_-]{20,}$/;
const STORAGE_KEY = "gp.kioskConfirmReturn";

export interface CommitKioskPendingResult {
  sessionId: string;
  memberId: string;
  date: string;
}

export function isKioskConfirmToken(token: string | null | undefined): token is string {
  return typeof token === "string" && TOKEN.test(token);
}

/** Same-origin return path. Anything else is rejected. */
export function kioskConfirmReturnPath(token: string): string | null {
  if (!isKioskConfirmToken(token)) return null;
  const path = `/kiosk/confirm?token=${token}`;
  return RETURN_PATH.test(path) ? path : null;
}

export function tokenFromKioskConfirmReturn(path: string): string | null {
  if (!RETURN_PATH.test(path)) return null;
  return path.slice("/kiosk/confirm?token=".length);
}

export function stashKioskConfirmReturn(token: string): void {
  if (typeof sessionStorage === "undefined") return;
  const path = kioskConfirmReturnPath(token);
  if (!path) return;
  sessionStorage.setItem(STORAGE_KEY, path);
}

/**
 * Read the stashed return path and remove it.
 * Only `/kiosk/confirm?token=<base64url of 20+ chars>` is returned.
 */
export function takeKioskConfirmReturn(): string | null {
  if (typeof sessionStorage === "undefined") return null;
  const raw = sessionStorage.getItem(STORAGE_KEY);
  sessionStorage.removeItem(STORAGE_KEY);
  if (typeof raw === "string" && RETURN_PATH.test(raw)) return raw;
  return null;
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function rpcUrl(supabaseUrl: string): string {
  return `${supabaseUrl.replace(/\/$/, "")}/rest/v1/rpc/commit_kiosk_pending`;
}

async function serverMessage(response: Response): Promise<string> {
  const text = await response.text();
  if (!text) return `Could not confirm this session (${response.status}).`;
  try {
    const json = JSON.parse(text) as { message?: unknown; error?: unknown };
    if (typeof json.message === "string" && json.message.length > 0) return json.message;
    if (typeof json.error === "string" && json.error.length > 0) return json.error;
  } catch {
    // Response was not JSON; show the body.
  }
  return text;
}

function parseCommitResult(value: unknown): CommitKioskPendingResult {
  if (!value || typeof value !== "object") {
    throw new Error("The server did not confirm this session.");
  }
  const row = value as Record<string, unknown>;
  if (
    typeof row.sessionId !== "string" ||
    typeof row.memberId !== "string" ||
    typeof row.date !== "string"
  ) {
    throw new Error("The server did not confirm this session.");
  }
  return { sessionId: row.sessionId, memberId: row.memberId, date: row.date };
}

/**
 * POST commit_kiosk_pending as the signed-in member.
 * Refuses to call PostgREST without the member access token.
 */
export async function commitKioskPending(params: {
  accessToken: string;
  rawToken: string;
  supabaseUrl: string;
  publishableKey: string;
  fetchImpl?: typeof fetch;
}): Promise<CommitKioskPendingResult> {
  if (!params.accessToken) {
    throw new Error("Sign in on the member app to confirm this session.");
  }
  if (!isKioskConfirmToken(params.rawToken)) {
    throw new Error(KIOSK_CONFIRM_INVALID_MESSAGE);
  }
  if (!params.supabaseUrl || !params.publishableKey) {
    throw new Error("Supabase is not configured.");
  }

  const p_token_hash = await sha256Hex(params.rawToken);
  const response = await (params.fetchImpl ?? fetch)(rpcUrl(params.supabaseUrl), {
    method: "POST",
    headers: {
      Authorization: `Bearer ${params.accessToken}`,
      apikey: params.publishableKey,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({ p_token_hash }),
  });

  if (!response.ok) {
    throw new Error(await serverMessage(response));
  }

  return parseCommitResult(await response.json());
}
