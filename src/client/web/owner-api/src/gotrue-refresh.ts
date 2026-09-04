/**
 * GoTrue refresh_token grant — same HTTP contract as iOS GoTrueTokenRefresher
 * and member-web gotrue-refresh.server.ts.
 *
 * POST {supabaseURL}/auth/v1/token?grant_type=refresh_token
 * Body: { refresh_token }
 *
 * GoTrue rotates refresh_token on each successful refresh — callers MUST
 * persist the new pair. Error messages never include response bodies.
 */

export interface GoTrueRefreshedSession {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
}

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
    body: JSON.stringify({
      grant_type: "refresh_token",
      refresh_token: params.refreshToken,
    }),
  });

  const text = await response.text();
  if (!response.ok) {
    throw new GoTrueRefreshError(
      `GoTrue refresh failed (${safeGoTrueErrorDetail(response.status, text)})`,
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

  console.log(
    `GoTrue refresh HTTP 200 keys=${Object.keys(record).join(",")} expires_at:${typeof record.expires_at} expires_in:${typeof record.expires_in} refresh_len=${refreshToken.length}`,
  );

  // GoTrue has already rotated refresh_token. Persist even if expiry fields
  // are missing or oddly typed — throwing here burns the session in KV.
  const expiresAt = resolveExpiry(record, nowSeconds);
  return { accessToken, refreshToken, expiresAt };
}

function asFiniteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.length > 0) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

function resolveExpiry(record: Record<string, unknown>, nowSeconds: number): number {
  let expiresAt = asFiniteNumber(record.expires_at);
  if (expiresAt != null && expiresAt > 1e12) {
    expiresAt = Math.floor(expiresAt / 1000);
  }
  if (expiresAt != null && expiresAt > 0) return expiresAt;

  const expiresIn = asFiniteNumber(record.expires_in);
  if (expiresIn != null) return nowSeconds + expiresIn;

  console.warn(
    `GoTrue refresh missing expiry (expires_at:${typeof record.expires_at}, expires_in:${typeof record.expires_in}); defaulting to 3600s`,
  );
  return nowSeconds + 3600;
}

function safeGoTrueErrorDetail(status: number, text: string): string {
  try {
    const errBody = JSON.parse(text) as Record<string, unknown>;
    const error =
      typeof errBody.error === "string" && /^[a-z_]+$/.test(errBody.error)
        ? errBody.error
        : "";
    const code = typeof errBody.error_code === "string" ? errBody.error_code : "";
    const parts = [
      `HTTP ${status}`,
      error ? `error=${error}` : null,
      code ? `error_code=${code}` : null,
    ].filter((part): part is string => part != null);
    return parts.join(" ");
  } catch {
    return `HTTP ${status} non-json`;
  }
}

function ensureTrailingSlash(url: string): string {
  return url.endsWith("/") ? url : `${url}/`;
}
