/**
 * Human login for the two dedicated owner Auth users.
 * Email + password via GoTrue. Not the owner-api bot key, and not TeamUp.
 */

import type { AuthSessionData } from "./auth-session";

export class KioskLoginError extends Error {
  readonly status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = "KioskLoginError";
    this.status = status;
  }
}

export function appRoleFromAccessToken(accessToken: string): string | null {
  const part = accessToken.split(".")[1];
  if (!part) return null;
  try {
    const padded = part.replaceAll("-", "+").replaceAll("_", "/") +
      "=".repeat((4 - (part.length % 4)) % 4);
    const payload = JSON.parse(atob(padded)) as { app_role?: unknown };
    return typeof payload.app_role === "string" ? payload.app_role : null;
  } catch {
    return null;
  }
}

export async function signInOwnerWithPassword(params: {
  email: string;
  password: string;
  supabaseUrl: string;
  publishableKey: string;
  fetchImpl?: typeof fetch;
  nowSeconds?: number;
}): Promise<AuthSessionData> {
  const email = params.email.trim();
  const password = params.password;
  if (!email || !password) {
    throw new KioskLoginError("Enter your email and password.", 400);
  }

  const fetchImpl = params.fetchImpl ?? fetch;
  const nowSeconds = params.nowSeconds ?? Math.floor(Date.now() / 1000);
  const url = new URL(
    "auth/v1/token",
    params.supabaseUrl.endsWith("/") ? params.supabaseUrl : `${params.supabaseUrl}/`,
  );
  url.searchParams.set("grant_type", "password");

  const response = await fetchImpl(url.toString(), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: params.publishableKey,
      Authorization: `Bearer ${params.publishableKey}`,
    },
    body: JSON.stringify({ email, password }),
  });

  if (response.status === 400 || response.status === 401) {
    throw new KioskLoginError("Email or password is incorrect.", 401);
  }
  if (!response.ok) {
    throw new KioskLoginError("Could not sign in.", 502);
  }

  const json = await response.json() as Record<string, unknown>;
  const accessToken = json.access_token;
  const refreshToken = json.refresh_token;
  if (typeof accessToken !== "string" || typeof refreshToken !== "string") {
    throw new KioskLoginError("Could not sign in.", 502);
  }
  if (appRoleFromAccessToken(accessToken) !== "owner") {
    throw new KioskLoginError("This login is only for the gym kiosk.", 403);
  }

  let expiresAt = nowSeconds + 3600;
  if (typeof json.expires_at === "number" && Number.isFinite(json.expires_at)) {
    expiresAt = json.expires_at;
  } else if (typeof json.expires_in === "number" && Number.isFinite(json.expires_in)) {
    expiresAt = nowSeconds + json.expires_in;
  }

  return {
    accessToken,
    refreshToken,
    expiresAt,
    issuedAt: nowSeconds,
  };
}
