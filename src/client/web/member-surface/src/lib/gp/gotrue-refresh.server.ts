/**
 * GoTrue refresh_token grant — same HTTP contract as iOS GoTrueTokenRefresher.
 *
 * POST {supabaseURL}/auth/v1/token?grant_type=refresh_token
 * Body: { refresh_token }
 * Headers: apikey + Authorization Bearer publishable key
 *
 * GoTrue rotates refresh_token on each successful refresh — callers MUST
 * persist the new pair.
 */

import type { GoTrueRefreshedSession } from "./auth-session";

export type { GoTrueRefreshedSession };

export class GoTrueRefreshError extends Error {
  readonly status: number;

  constructor(message: string, status = 0) {
    super(message);
    this.name = "GoTrueRefreshError";
    this.status = status;
  }
}

export async function refreshGoTrueSession(params: {
  refreshToken: string;
  supabaseUrl: string;
  publishableKey: string;
  fetchImpl?: typeof fetch;
  nowSeconds?: number;
}): Promise<GoTrueRefreshedSession> {
  const fetchImpl = params.fetchImpl ?? fetch;
  const nowSeconds = params.nowSeconds ?? Math.floor(Date.now() / 1000);

  const url = new URL("auth/v1/token", ensureTrailingSlash(params.supabaseUrl));
  url.searchParams.set("grant_type", "refresh_token");

  const response = await fetchImpl(url.toString(), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: params.publishableKey,
      Authorization: `Bearer ${params.publishableKey}`,
    },
    body: JSON.stringify({ refresh_token: params.refreshToken }),
  });

  const text = await response.text();
  if (!response.ok) {
    throw new GoTrueRefreshError(
      `GoTrue refresh failed (HTTP ${response.status}): ${text}`,
      response.status,
    );
  }

  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new GoTrueRefreshError("GoTrue refresh returned non-JSON body");
  }

  if (typeof json !== "object" || json === null) {
    throw new GoTrueRefreshError("GoTrue refresh returned invalid JSON");
  }

  const record = json as Record<string, unknown>;
  const accessToken = record.access_token;
  const refreshToken = record.refresh_token;

  if (typeof accessToken !== "string" || accessToken.length === 0) {
    throw new GoTrueRefreshError("Refresh response missing access_token");
  }
  if (typeof refreshToken !== "string" || refreshToken.length === 0) {
    throw new GoTrueRefreshError("Refresh response missing refresh_token");
  }

  let expiresAt: number;
  if (typeof record.expires_at === "number" && Number.isFinite(record.expires_at)) {
    expiresAt = record.expires_at;
  } else if (typeof record.expires_at === "string" && record.expires_at.length > 0) {
    expiresAt = Number(record.expires_at);
  } else if (typeof record.expires_in === "number" && Number.isFinite(record.expires_in)) {
    expiresAt = nowSeconds + record.expires_in;
  } else {
    throw new GoTrueRefreshError("Refresh response missing expiry");
  }

  if (!Number.isFinite(expiresAt) || expiresAt <= 0) {
    throw new GoTrueRefreshError("Refresh response had invalid expiry");
  }

  return { accessToken, refreshToken, expiresAt };
}

function ensureTrailingSlash(url: string): string {
  return url.endsWith("/") ? url : `${url}/`;
}
