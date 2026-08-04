/**
 * Pure auth-session helpers shared by server routes and tests.
 * No cookie/ALS imports here — keep this runnable without a request context.
 */

export const AUTH_SESSION_COOKIE = "gp_auth";
export const DEVICE_MEMBER_ID_COOKIE = "gp_device_member_id";

/** Refresh when access token expires within this window (matches iOS skew). */
export const REFRESH_SKEW_SECONDS = 60;

export interface AuthSessionData {
  accessToken: string;
  refreshToken: string;
  /** Unix seconds */
  expiresAt: number;
  /** Unix seconds */
  issuedAt: number;
}

export interface SessionJsonResponse {
  token: string;
  expiresAt: number;
}

/** Shape returned by GoTrue refresh_token grant (iOS GoTrueTokenRefresher). */
export interface GoTrueRefreshedSession {
  accessToken: string;
  refreshToken: string;
  /** Unix seconds */
  expiresAt: number;
}

export function parseCallbackSessionParams(url: URL): AuthSessionData | null {
  const accessToken =
    url.searchParams.get("access_token") ?? url.searchParams.get("token");
  const refreshToken = url.searchParams.get("refresh_token");
  const expiresRaw = url.searchParams.get("expires_at");

  if (!accessToken || accessToken.length === 0) return null;
  if (!refreshToken || refreshToken.length === 0) return null;
  if (!expiresRaw) return null;

  const expiresAt = Number(expiresRaw);
  if (!Number.isFinite(expiresAt) || expiresAt <= 0) return null;

  return {
    accessToken,
    refreshToken,
    expiresAt,
    issuedAt: Math.floor(Date.now() / 1000),
  };
}

export function sessionNeedsRefresh(
  expiresAt: number | undefined,
  nowSeconds: number = Math.floor(Date.now() / 1000),
): boolean {
  if (expiresAt == null || !Number.isFinite(expiresAt)) return true;
  return expiresAt - REFRESH_SKEW_SECONDS <= nowSeconds;
}

export function isValidAuthSessionData(
  data: Partial<AuthSessionData> | null | undefined,
): data is AuthSessionData {
  if (!data) return false;
  return (
    typeof data.accessToken === "string" &&
    data.accessToken.length > 0 &&
    typeof data.refreshToken === "string" &&
    data.refreshToken.length > 0 &&
    typeof data.expiresAt === "number" &&
    Number.isFinite(data.expiresAt) &&
    typeof data.issuedAt === "number" &&
    Number.isFinite(data.issuedAt)
  );
}

export function toSessionJson(data: AuthSessionData): SessionJsonResponse {
  return {
    token: data.accessToken,
    expiresAt: data.expiresAt,
  };
}

/** Ensure Location has no auth tokens (defense in depth for redirect checks). */
export function assertCleanRedirectLocation(location: string): void {
  const url = new URL(location, "https://example.invalid");
  for (const key of ["access_token", "refresh_token", "token", "expires_at"]) {
    if (url.searchParams.has(key)) {
      throw new Error(`Redirect Location must not include ${key}`);
    }
  }
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function isDeviceMemberId(value: string | null | undefined): boolean {
  return typeof value === "string" && UUID_RE.test(value);
}

export function buildBrokerAuthorizeUrl(params: {
  brokerBaseUrl: string;
  deviceMemberId: string;
  returnUrl: string;
  surface?: string;
}): string {
  const url = new URL(params.brokerBaseUrl);
  url.searchParams.set("oauth", "authorize");
  url.searchParams.set("deviceMemberId", params.deviceMemberId);
  url.searchParams.set("surface", params.surface ?? "memberWeb");
  url.searchParams.set("returnUrl", params.returnUrl);
  return url.toString();
}
