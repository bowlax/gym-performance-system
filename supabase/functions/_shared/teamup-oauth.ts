/**
 * TeamUp OAuth 2.0 helpers (authorization code + PKCE).
 *
 * Identity-only: access tokens are decoded for claims and not persisted.
 * See https://docs.goteamup.com/guides/oauth
 */

import { SignJWT, jwtVerify } from "jsr:@panva/jose@6";

export type TeamUpMode = "customer" | "provider";

export interface TeamUpVerificationResult {
  teamupCustomerId: string;
  providerId: string;
  mode: TeamUpMode;
}

export interface TeamUpOAuthConfig {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  providerId: string;
  scope: string;
  authorizeUrl: string;
  tokenUrl: string;
  successRedirectUri: string | null;
}

export interface OAuthStatePayload {
  deviceMemberId: string;
  surface: string;
  codeVerifier: string;
  returnUrl: string | null;
}

const DEFAULT_AUTHORIZE_URL =
  "https://goteamup.com/api/v2/auth/oauth/authorize";
const DEFAULT_TOKEN_URL = "https://goteamup.com/api/v2/auth/oauth/token";
const OAUTH_STATE_AUDIENCE = "teamup-oauth-state";
const OAUTH_STATE_TTL_SECONDS = 10 * 60;

const STUB_TEAMUP_TOKEN = "stub-token";

export function isStubTeamUpToken(token: string): boolean {
  return token === STUB_TEAMUP_TOKEN;
}

export function stubTeamUpVerification(
  providerId = "5404319",
): TeamUpVerificationResult {
  return {
    teamupCustomerId: "TEST-CUSTOMER-001",
    providerId,
    mode: "customer",
  };
}

function envOptional(name: string): string | undefined {
  const value = Deno.env.get(name)?.trim();
  return value && value.length > 0 ? value : undefined;
}

export function readTeamUpOAuthConfig(): TeamUpOAuthConfig | null {
  const clientId = envOptional("TEAMUP_OAUTH_CLIENT_ID");
  const clientSecret = envOptional("TEAMUP_OAUTH_CLIENT_SECRET");
  const redirectUri = envOptional("TEAMUP_OAUTH_REDIRECT_URI");
  const providerId = envOptional("TEAMUP_OAUTH_PROVIDER_ID");

  if (!clientId || !clientSecret || !redirectUri || !providerId) {
    return null;
  }

  const scopeOverride = envOptional("TEAMUP_OAUTH_SCOPE");
  const scope = scopeOverride ?? `read_write provider:${providerId}`;

  return {
    clientId,
    clientSecret,
    redirectUri,
    providerId,
    scope,
    authorizeUrl: envOptional("TEAMUP_OAUTH_AUTHORIZE_URL") ??
      DEFAULT_AUTHORIZE_URL,
    tokenUrl: envOptional("TEAMUP_OAUTH_TOKEN_URL") ?? DEFAULT_TOKEN_URL,
    successRedirectUri: envOptional("TEAMUP_OAUTH_SUCCESS_REDIRECT_URI") ??
      null,
  };
}

export function isTeamUpOAuthConfigured(): boolean {
  return readTeamUpOAuthConfig() !== null;
}

/**
 * Whether the broker should take the stub TeamUp + HS256 session path.
 *
 * Boundary (explicit):
 * - OAuth **unconfigured** (local/dev): always stub — HS256 mint allowed.
 * - OAuth **configured** (deployed prod): never stub — callers must refuse
 *   `stub-token` before verification; no production-reachable HS256 mint.
 */
export function shouldUseStubTeamUpPath(teamupToken: string): boolean {
  if (isTeamUpOAuthConfigured()) {
    return false;
  }
  // Unconfigured: any POST uses stub identity (including stub-token).
  void teamupToken;
  return true;
}

/**
 * True when a stub-token POST must be rejected (OAuth is live / production).
 */
export function isStubTokenRejectedWhenOAuthConfigured(teamupToken: string): boolean {
  return isTeamUpOAuthConfigured() && isStubTeamUpToken(teamupToken);
}

/**
 * TeamUp appends `?code=&state=` even when redirect_uri already has
 * `?oauth=callback`, producing `?oauth=callback?code=…&state=…`.
 * In that form `oauth` parses as `callback?code=…`, not `callback`.
 */
export function isOAuthCallbackQueryParam(oauth: string | null): boolean {
  return oauth === "callback" || (oauth?.startsWith("callback?") ?? false);
}

export type OAuthGetRoute = "authorize" | "callback" | "none";

/** Same decision `routeOAuthGet` uses for GET dispatch (testable without Deno.serve). */
export function resolveOAuthGetRoute(url: URL): OAuthGetRoute {
  const oauth = url.searchParams.get("oauth");
  if (oauth === "authorize") {
    return "authorize";
  }
  if (isOAuthCallbackQueryParam(oauth)) {
    return "callback";
  }
  return "none";
}

export interface ParsedOAuthCallbackParams {
  code: string | null;
  state: string | null;
  error: string | null;
  errorDescription: string | null;
}

/**
 * Extract OAuth callback params from both:
 * - clean: `?oauth=callback&code=X&state=Y`
 * - TeamUp mangled: `?oauth=callback?code=X&state=Y` (code nested in oauth)
 */
export function parseOAuthCallbackParams(url: URL): ParsedOAuthCallbackParams {
  const oauth = url.searchParams.get("oauth");
  let code = url.searchParams.get("code");
  const state = url.searchParams.get("state");

  if (!code && oauth && oauth.includes("?")) {
    const nested = new URLSearchParams(oauth.slice(oauth.indexOf("?") + 1));
    code = nested.get("code");
  }

  return {
    code,
    state,
    error: url.searchParams.get("error"),
    errorDescription: url.searchParams.get("error_description"),
  };
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

export function generatePkceCodeVerifier(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}

export async function pkceCodeChallengeS256(
  codeVerifier: string,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(codeVerifier),
  );
  return base64UrlEncode(new Uint8Array(digest));
}

function decodeBase64UrlJson(segment: string): Record<string, unknown> {
  const normalized = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const json = atob(padded);
  const parsed = JSON.parse(json);
  if (typeof parsed !== "object" || parsed === null) {
    throw new Error("JWT payload is not an object");
  }
  return parsed as Record<string, unknown>;
}

export function decodeTeamUpAccessToken(
  accessToken: string,
): TeamUpVerificationResult {
  const parts = accessToken.split(".");
  if (parts.length < 2) {
    throw new Error("TeamUp access token is not a JWT");
  }

  const claims = decodeBase64UrlJson(parts[1]!);
  const sub = claims.sub;
  if (sub === undefined || sub === null) {
    throw new Error("TeamUp access token is missing sub claim");
  }

  const scope = typeof claims.scope === "string" ? claims.scope : "";
  const providerId = parseProviderIdFromScope(scope);
  if (!providerId) {
    throw new Error("TeamUp access token scope is missing provider:<id>");
  }

  return {
    teamupCustomerId: String(sub),
    providerId,
    mode: inferTeamUpModeFromScope(scope),
  };
}

export function parseProviderIdFromScope(scope: string): string | null {
  const match = scope.match(/(?:^|\s)provider:(\d+)(?:\s|$)/);
  return match?.[1] ?? null;
}

export function inferTeamUpModeFromScope(scope: string): TeamUpMode {
  // TeamUp member tokens include provider scope; staff/provider tokens are
  // distinguished later if coach surfaces need a different claim shape.
  if (/\bprovider:\d+\b/.test(scope) && /\bstaff\b/i.test(scope)) {
    return "provider";
  }
  return "customer";
}

export function buildTeamUpAuthorizeUrl(
  config: TeamUpOAuthConfig,
  params: {
    codeChallenge: string;
    state: string;
    loginHint?: string | null;
  },
): string {
  const url = new URL(config.authorizeUrl);
  url.searchParams.set("client_id", config.clientId);
  url.searchParams.set("redirect_uri", config.redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", config.scope);
  url.searchParams.set("code_challenge", params.codeChallenge);
  url.searchParams.set("code_challenge_method", "S256");
  url.searchParams.set("state", params.state);
  if (params.loginHint) {
    url.searchParams.set("login_hint", params.loginHint);
  }
  return url.toString();
}

export async function signOAuthState(
  payload: OAuthStatePayload,
  signingSecret: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  return await new SignJWT({
    deviceMemberId: payload.deviceMemberId,
    surface: payload.surface,
    codeVerifier: payload.codeVerifier,
    returnUrl: payload.returnUrl,
  })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setAudience(OAUTH_STATE_AUDIENCE)
    .setIssuedAt(now)
    .setExpirationTime(now + OAUTH_STATE_TTL_SECONDS)
    .sign(new TextEncoder().encode(signingSecret));
}

export async function verifyOAuthState(
  stateToken: string,
  signingSecret: string,
): Promise<OAuthStatePayload> {
  const { payload } = await jwtVerify(
    stateToken,
    new TextEncoder().encode(signingSecret),
    { audience: OAUTH_STATE_AUDIENCE },
  );

  const deviceMemberId = payload.deviceMemberId;
  const surface = payload.surface;
  const codeVerifier = payload.codeVerifier;

  if (typeof deviceMemberId !== "string" || deviceMemberId.length === 0) {
    throw new Error("OAuth state is missing deviceMemberId");
  }
  if (typeof surface !== "string" || surface.length === 0) {
    throw new Error("OAuth state is missing surface");
  }
  if (typeof codeVerifier !== "string" || codeVerifier.length === 0) {
    throw new Error("OAuth state is missing codeVerifier");
  }

  const returnUrl = typeof payload.returnUrl === "string"
    ? payload.returnUrl
    : null;

  return { deviceMemberId, surface, codeVerifier, returnUrl };
}

export async function exchangeTeamUpAuthorizationCode(
  config: TeamUpOAuthConfig,
  params: { code: string; codeVerifier: string },
): Promise<string> {
  const body = new URLSearchParams({
    client_id: config.clientId,
    client_secret: config.clientSecret,
    code: params.code,
    redirect_uri: config.redirectUri,
    grant_type: "authorization_code",
    code_verifier: params.codeVerifier,
  });

  const response = await fetch(config.tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(
      `TeamUp token exchange failed (${response.status}): ${text}`,
    );
  }

  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new Error("TeamUp token exchange returned non-JSON body");
  }

  if (typeof json !== "object" || json === null) {
    throw new Error("TeamUp token exchange returned invalid JSON");
  }

  const accessToken = (json as Record<string, unknown>).access_token;
  if (typeof accessToken !== "string" || accessToken.length === 0) {
    throw new Error("TeamUp token exchange response missing access_token");
  }

  return accessToken;
}

export function resolveOAuthReturnUrl(
  config: TeamUpOAuthConfig,
  requestedReturnUrl: string | null,
): string | null {
  if (requestedReturnUrl && isAllowedReturnUrl(config, requestedReturnUrl)) {
    return requestedReturnUrl;
  }
  return config.successRedirectUri;
}

export function isAllowedReturnUrl(
  config: TeamUpOAuthConfig,
  returnUrl: string,
): boolean {
  try {
    const candidate = new URL(returnUrl);
    if (config.successRedirectUri) {
      const allowed = new URL(config.successRedirectUri);
      return candidate.origin === allowed.origin;
    }
    if (candidate.protocol === "http:" || candidate.protocol === "https:") {
      return true;
    }
    // Native app custom URL schemes (e.g. gymperformance://) are valid
    // OAuth redirect targets per RFC 8252 §7.1.
    if (candidate.protocol.length > 1 && candidate.protocol.endsWith(":")) {
      return true;
    }
    return false;
  } catch {
    return false;
  }
}

export function appendTokenToReturnUrl(
  returnUrl: string,
  token: string,
): string {
  const url = new URL(returnUrl);
  url.searchParams.set("token", token);
  return url.toString();
}

/**
 * Auth-path OAuth callback redirect (#17).
 *
 * SECURITY — refresh_token in the query string is a deliberate choice for the
 * iOS ASWebAuthenticationSession callback: the OS delivers the URL to the app
 * process, not into browser history. When the web OAuth return path is built,
 * prefer a URL fragment or a one-time-code exchange instead — a normal browser
 * redirect is where query-string leakage (logs, Referer, history) bites.
 */
export function appendSessionToReturnUrl(
  returnUrl: string,
  session: {
    accessToken: string;
    refreshToken: string;
    expiresAt: number;
  },
): string {
  const url = new URL(returnUrl);
  url.searchParams.set("access_token", session.accessToken);
  url.searchParams.set("refresh_token", session.refreshToken);
  url.searchParams.set("expires_at", String(session.expiresAt));
  // Alias so existing OAuthConnectAuthClient (?token=) keeps working.
  url.searchParams.set("token", session.accessToken);
  return url.toString();
}
