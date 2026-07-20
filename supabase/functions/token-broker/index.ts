/**
 * Token Broker — Supabase Edge Function
 *
 * Exchanges a TeamUp access token (plus device member UUID and surface) for a
 * Supabase session JWT carrying member_id, gym_id, and app_role claims for RLS.
 *
 * Paths:
 *   - Unconfigured / stub-token POST: hand-minted HS256 `{ token }` (unchanged).
 *   - Configured + real TeamUp JWT or OAuth callback: create-or-find Auth user,
 *     generateLink → verifyOtp, return `{ access_token, refresh_token, expires_at,
 *     token }` (ES256). Requires Custom Access Token Hook enabled so app_metadata
 *     is promoted to top-level claims.
 *
 * When TeamUp OAuth env vars are set, also exposes GET authorize/callback
 * routes for backend-driven OAuth (authorization code + PKCE). Without those
 * vars, only the existing POST stub path is available.
 *
 * Required environment variables (set via `supabase secrets set` or `.env` for local serve):
 *   SUPABASE_URL        — project API URL (provided automatically on hosted runtime)
 *   SERVICE_ROLE_KEY    — service role secret key (bypasses RLS for member create/adopt)
 *   JWT_SIGNING_SECRET  — JWT signing secret (Settings → API → JWT Secret)
 *
 * Optional TeamUp OAuth (all required together to enable the real OAuth path):
 *   TEAMUP_OAUTH_CLIENT_ID
 *   TEAMUP_OAUTH_CLIENT_SECRET
 *   TEAMUP_OAUTH_REDIRECT_URI
 *   TEAMUP_OAUTH_PROVIDER_ID
 *   TEAMUP_OAUTH_SUCCESS_REDIRECT_URI (optional; returnUrl query param must match origin)
 *   TEAMUP_OAUTH_SCOPE (optional; default read_write provider:<PROVIDER_ID>)
 *   TEAMUP_OAUTH_AUTHORIZE_URL / TEAMUP_OAUTH_TOKEN_URL (optional overrides)
 *
 * Note: custom secrets must not use the SUPABASE_ prefix — the hosted runtime
 * reserves that prefix and rejects custom secrets named with it.
 *
 * Local development:
 *   npm install
 *   supabase start
 *   supabase functions serve token-broker --no-verify-jwt --env-file supabase/.env.local
 *
 * Deploy (manual):
 *   supabase link --project-ref <PROJECT_REF>
 *   supabase secrets set --env-file supabase/.env.production
 *   supabase functions deploy token-broker --no-verify-jwt
 */

import { createClient, type SupabaseClient, type User } from "jsr:@supabase/supabase-js@2";
import { SignJWT } from "jsr:@panva/jose@6";
import {
  appendSessionToReturnUrl,
  appendTokenToReturnUrl,
  buildTeamUpAuthorizeUrl,
  decodeTeamUpAccessToken,
  exchangeTeamUpAuthorizationCode,
  generatePkceCodeVerifier,
  parseOAuthCallbackParams,
  pkceCodeChallengeS256,
  readTeamUpOAuthConfig,
  resolveOAuthGetRoute,
  resolveOAuthReturnUrl,
  shouldUseStubTeamUpPath,
  signOAuthState,
  stubTeamUpVerification,
  verifyOAuthState,
  type TeamUpVerificationResult,
} from "../_shared/teamup-oauth.ts";

// Minimal schema types for compile-time checking without a generated Database type.
interface GymRow {
  id: string;
}

interface MemberRow {
  id: string;
  auth_user_id: string | null;
}

type ServiceClient = SupabaseClient;

/** Issued session: Auth path returns the full pair; stub returns token only. */
type IssuedSession =
  | {
    kind: "hs256";
    token: string;
  }
  | {
    kind: "auth";
    accessToken: string;
    refreshToken: string;
    expiresAt: number;
  };

const AUTH_EMAIL_DOMAIN = "auth.gymperf.local";

export function syntheticAuthEmail(teamupCustomerId: string): string {
  const local = teamupCustomerId.replace(/[^a-zA-Z0-9_-]/g, "_");
  return `teamup-${local}@${AUTH_EMAIL_DOMAIN}`;
}

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type Surface = "ios" | "memberWeb" | "coachWeb" | "ownerWeb";
type AppRole = "member" | "coach" | "owner";

interface TokenBrokerRequest {
  teamupToken: string;
  deviceMemberId: string;
  surface: Surface;
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const SURFACES: readonly Surface[] = [
  "ios",
  "memberWeb",
  "coachWeb",
  "ownerWeb",
];

const JWT_LIFETIME_SECONDS = 60 * 60;

interface PostgrestErrorLike {
  message?: string;
  name?: string;
  stack?: string;
  details?: string;
  hint?: string;
  code?: string;
}

function logSupabaseError(
  context: string,
  error: PostgrestErrorLike,
): void {
  console.error(`token-broker supabase ${context} error message:`, error.message);
  if (error.details) {
    console.error(`token-broker supabase ${context} error details:`, error.details);
  }
  if (error.hint) {
    console.error(`token-broker supabase ${context} error hint:`, error.hint);
  }
  if (error.code) {
    console.error(`token-broker supabase ${context} error code:`, error.code);
  }
}

function logCaughtError(error: unknown): void {
  console.error("token-broker failed");

  if (error instanceof Error) {
    console.error("token-broker error name:", error.name);
    console.error("token-broker error message:", error.message);
    if (error.stack) {
      console.error("token-broker error stack:", error.stack);
    }
    return;
  }

  if (typeof error === "object" && error !== null) {
    const record = error as PostgrestErrorLike;
    if (record.message) {
      console.error("token-broker error message:", record.message);
    }
    if (record.name) {
      console.error("token-broker error name:", record.name);
    }
    if (record.stack) {
      console.error("token-broker error stack:", record.stack);
    }
    if (record.details) {
      console.error("token-broker supabase error details:", record.details);
    }
    if (record.hint) {
      console.error("token-broker supabase error hint:", record.hint);
    }
    if (record.code) {
      console.error("token-broker supabase error code:", record.code);
    }
    if (!record.message && !record.name && !record.details && !record.code) {
      try {
        console.error("token-broker error value:", JSON.stringify(error));
      } catch {
        console.error("token-broker error value:", String(error));
      }
    }
    return;
  }

  console.error("token-broker error value:", String(error));
}

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function redirectResponse(location: string, status = 302): Response {
  return new Response(null, {
    status,
    headers: { ...corsHeaders, Location: location },
  });
}

function isSurface(value: string): value is Surface {
  return (SURFACES as readonly string[]).includes(value);
}

function parseRequestBody(body: unknown): TokenBrokerRequest | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }

  const record = body as Record<string, unknown>;
  const teamupToken = record.teamupToken;
  const deviceMemberId = record.deviceMemberId;
  const surface = record.surface;

  if (typeof teamupToken !== "string" || teamupToken.length === 0) {
    return null;
  }

  if (
    typeof deviceMemberId !== "string" ||
    !UUID_PATTERN.test(deviceMemberId)
  ) {
    return null;
  }

  if (typeof surface !== "string" || !isSurface(surface)) {
    return null;
  }

  return { teamupToken, deviceMemberId, surface };
}

function parseOAuthAuthorizeParams(
  url: URL,
): { deviceMemberId: string; surface: Surface; returnUrl: string | null } | null {
  const deviceMemberId = url.searchParams.get("deviceMemberId");
  const surface = url.searchParams.get("surface");
  const returnUrl = url.searchParams.get("returnUrl");

  if (!deviceMemberId || !UUID_PATTERN.test(deviceMemberId)) {
    return null;
  }
  if (!surface || !isSurface(surface)) {
    return null;
  }

  return {
    deviceMemberId,
    surface,
    returnUrl: returnUrl && returnUrl.length > 0 ? returnUrl : null,
  };
}

async function verifyTeamUpToken(
  token: string,
): Promise<TeamUpVerificationResult> {
  if (shouldUseStubTeamUpPath(token)) {
    const config = readTeamUpOAuthConfig();
    return stubTeamUpVerification(config?.providerId);
  }

  return decodeTeamUpAccessToken(token);
}

function surfaceToRole(surface: Surface): AppRole {
  switch (surface) {
    case "ios":
    case "memberWeb":
      return "member";
    case "coachWeb":
      return "coach";
    case "ownerWeb":
      return "owner";
  }
}

function isStaffSurface(surface: Surface): boolean {
  return surface === "coachWeb" || surface === "ownerWeb";
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function createServiceClient(): ServiceClient {
  const supabaseUrl = requireEnv("SUPABASE_URL");
  const serviceRoleKey = requireEnv("SERVICE_ROLE_KEY");

  return createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

async function lookupGymId(
  supabase: ServiceClient,
  providerId: string,
): Promise<string | null> {
  const { data, error } = await supabase
    .from("gyms")
    .select("id")
    .eq("teamup_provider_id", providerId)
    .is("deleted_at", null)
    .maybeSingle();

  if (error) {
    logSupabaseError("lookupGymId", error);
    throw error;
  }

  const gym = data as GymRow | null;
  return gym?.id ?? null;
}

async function createOrAdoptMember(
  supabase: ServiceClient,
  gymId: string,
  teamupCustomerId: string,
  deviceMemberId: string,
): Promise<MemberRow> {
  const { data: existing, error: lookupError } = await supabase
    .from("members")
    .select("id, auth_user_id")
    .eq("gym_id", gymId)
    .eq("teamup_customer_id", teamupCustomerId)
    .is("deleted_at", null)
    .maybeSingle();

  if (lookupError) {
    logSupabaseError("createOrAdoptMember.lookup", lookupError);
    throw lookupError;
  }

  const existingMember = existing as MemberRow | null;
  if (existingMember?.id) {
    return {
      id: existingMember.id,
      auth_user_id: existingMember.auth_user_id ?? null,
    };
  }

  const { data: created, error: insertError } = await supabase
    .from("members")
    .insert({
      id: deviceMemberId,
      gym_id: gymId,
      teamup_customer_id: teamupCustomerId,
    })
    .select("id, auth_user_id")
    .single();

  if (insertError) {
    logSupabaseError("createOrAdoptMember.insert", insertError);
    throw insertError;
  }

  const createdMember = created as MemberRow;
  return {
    id: createdMember.id,
    auth_user_id: createdMember.auth_user_id ?? null,
  };
}

function appMetadataForMember(
  memberId: string,
  gymId: string,
  appRole: AppRole,
): Record<string, string> {
  return {
    member_id: memberId,
    gym_id: gymId,
    app_role: appRole,
  };
}

function metadataNeedsUpdate(
  user: User,
  expected: Record<string, string>,
): boolean {
  const meta = (user.app_metadata ?? {}) as Record<string, unknown>;
  return (
    meta.member_id !== expected.member_id ||
    meta.gym_id !== expected.gym_id ||
    meta.app_role !== expected.app_role
  );
}

function isUniqueViolation(error: { message?: string; code?: string }): boolean {
  const message = (error.message ?? "").toLowerCase();
  return (
    error.code === "23505" ||
    message.includes("already been registered") ||
    message.includes("already exists") ||
    message.includes("duplicate") ||
    message.includes("unique")
  );
}

async function findAuthUserByEmail(
  supabase: ServiceClient,
  email: string,
): Promise<User | null> {
  // generateLink returns the existing user when the email is already registered,
  // avoiding a full listUsers scan.
  const { data, error } = await supabase.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  if (error) {
    logSupabaseError("findAuthUserByEmail.generateLink", error);
    throw error;
  }
  return data.user ?? null;
}

async function linkAuthUserId(
  supabase: ServiceClient,
  memberId: string,
  authUserId: string,
): Promise<void> {
  const { error } = await supabase
    .from("members")
    .update({ auth_user_id: authUserId })
    .eq("id", memberId)
    .is("auth_user_id", null);

  if (error) {
    if (isUniqueViolation(error)) {
      // Another connect won the race; re-read will adopt.
      return;
    }
    logSupabaseError("linkAuthUserId", error);
    throw error;
  }
}

async function createOrFindAuthUser(
  supabase: ServiceClient,
  member: MemberRow,
  teamupCustomerId: string,
  gymId: string,
  appRole: AppRole,
): Promise<User> {
  const email = syntheticAuthEmail(teamupCustomerId);
  const expectedMeta = appMetadataForMember(member.id, gymId, appRole);

  let user: User | null = null;

  if (member.auth_user_id) {
    const { data, error } = await supabase.auth.admin.getUserById(
      member.auth_user_id,
    );
    if (error) {
      logSupabaseError("createOrFindAuthUser.getUserById", error);
      throw error;
    }
    user = data.user;
  }

  if (!user) {
    const created = await supabase.auth.admin.createUser({
      email,
      email_confirm: true,
      app_metadata: expectedMeta,
    });

    if (created.error) {
      if (!isUniqueViolation(created.error)) {
        logSupabaseError("createOrFindAuthUser.createUser", created.error);
        throw created.error;
      }
      user = await findAuthUserByEmail(supabase, email);
      if (!user) {
        throw new Error(
          `Auth user email conflict for ${email} but user could not be loaded`,
        );
      }
    } else {
      user = created.data.user;
    }

    if (!user) {
      throw new Error("createUser returned no user");
    }

    await linkAuthUserId(supabase, member.id, user.id);

    // Re-read in case a concurrent connect linked a different auth user.
    const { data: refreshed, error: refreshError } = await supabase
      .from("members")
      .select("id, auth_user_id")
      .eq("id", member.id)
      .single();
    if (refreshError) {
      logSupabaseError("createOrFindAuthUser.rereadMember", refreshError);
      throw refreshError;
    }
    const linkedId = (refreshed as MemberRow).auth_user_id;
    if (linkedId && linkedId !== user.id) {
      const { data, error } = await supabase.auth.admin.getUserById(linkedId);
      if (error) {
        logSupabaseError("createOrFindAuthUser.getLinkedUser", error);
        throw error;
      }
      user = data.user;
    } else if (!linkedId) {
      // Update lost the race with a non-null write; force-set if still null.
      const { error: forceError } = await supabase
        .from("members")
        .update({ auth_user_id: user.id })
        .eq("id", member.id);
      if (forceError && !isUniqueViolation(forceError)) {
        logSupabaseError("createOrFindAuthUser.forceLink", forceError);
        throw forceError;
      }
    }
  }

  if (!user) {
    throw new Error("Auth user resolve failed");
  }

  if (metadataNeedsUpdate(user, expectedMeta)) {
    const { data, error } = await supabase.auth.admin.updateUserById(user.id, {
      app_metadata: expectedMeta,
    });
    if (error) {
      logSupabaseError("createOrFindAuthUser.updateMetadata", error);
      throw error;
    }
    user = data.user;
  }

  if (!user) {
    throw new Error("Auth user missing after metadata update");
  }

  return user;
}

function createAnonClient(): ServiceClient {
  const supabaseUrl = requireEnv("SUPABASE_URL");
  // Hosted Edge runtime injects SUPABASE_ANON_KEY; local serve may use the
  // publishable key under the same name or GYMPERF-style env — prefer standard.
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("GYMPERF_SUPABASE_PUBLISHABLE_KEY");
  if (!anonKey) {
    throw new Error(
      "Missing SUPABASE_ANON_KEY (required to verifyOtp for Auth-session issuance)",
    );
  }
  return createClient(supabaseUrl, anonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

async function establishAuthSession(
  service: ServiceClient,
  email: string,
): Promise<{ accessToken: string; refreshToken: string; expiresAt: number }> {
  const link = await service.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  if (link.error) {
    logSupabaseError("establishAuthSession.generateLink", link.error);
    throw link.error;
  }

  const tokenHash = link.data.properties?.hashed_token;
  if (!tokenHash) {
    throw new Error("generateLink did not return hashed_token");
  }

  const anon = createAnonClient();
  const verified = await anon.auth.verifyOtp({
    type: "email",
    token_hash: tokenHash,
  });
  if (verified.error) {
    logSupabaseError("establishAuthSession.verifyOtp", verified.error);
    throw verified.error;
  }

  const session = verified.data.session;
  if (!session?.access_token || !session.refresh_token) {
    throw new Error("verifyOtp returned no session tokens");
  }

  const expiresAt = session.expires_at ??
    Math.floor(Date.now() / 1000) + (session.expires_in ?? JWT_LIFETIME_SECONDS);

  return {
    accessToken: session.access_token,
    refreshToken: session.refresh_token,
    expiresAt,
  };
}

async function mintSupabaseJwt(
  memberId: string,
  gymId: string,
  appRole: AppRole,
): Promise<string> {
  const jwtSecret = requireEnv("JWT_SIGNING_SECRET");
  const now = Math.floor(Date.now() / 1000);

  // PostgREST maps JWT "role" to a Postgres role (authenticated/anon/service_role).
  // App roles (member/coach/owner) live in app_role for RLS policy checks.
  return await new SignJWT({
    sub: memberId,
    role: "authenticated",
    app_role: appRole,
    member_id: memberId,
    gym_id: gymId,
  })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer("supabase")
    .setAudience("authenticated")
    .setIssuedAt(now)
    .setExpirationTime(now + JWT_LIFETIME_SECONDS)
    .sign(new TextEncoder().encode(jwtSecret));
}

async function issueMemberSession(
  verification: TeamUpVerificationResult,
  deviceMemberId: string,
  surface: Surface,
  useAuthSession: boolean,
): Promise<IssuedSession | { error: string; status: number }> {
  const role = surfaceToRole(surface);

  if (verification.mode === "customer" && isStaffSurface(surface)) {
    return {
      error: "TeamUp customer token cannot access staff surfaces",
      status: 403,
    };
  }

  const supabase = createServiceClient();
  const gymId = await lookupGymId(supabase, verification.providerId);

  if (!gymId) {
    return { error: "Gym not found for TeamUp provider", status: 404 };
  }

  const member = await createOrAdoptMember(
    supabase,
    gymId,
    verification.teamupCustomerId,
    deviceMemberId,
  );

  // Stub / unconfigured: hand-mint HS256 (unchanged). Auth path only when
  // TEAMUP_OAUTH_* is configured and the caller is not on stub-token.
  if (!useAuthSession) {
    const token = await mintSupabaseJwt(member.id, gymId, role);
    return { kind: "hs256", token };
  }

  const user = await createOrFindAuthUser(
    supabase,
    member,
    verification.teamupCustomerId,
    gymId,
    role,
  );

  const session = await establishAuthSession(
    supabase,
    user.email ?? syntheticAuthEmail(verification.teamupCustomerId),
  );

  return {
    kind: "auth",
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
    expiresAt: session.expiresAt,
  };
}

function sessionJsonResponse(session: IssuedSession): Response {
  if (session.kind === "hs256") {
    return jsonResponse({ token: session.token }, 200);
  }
  return jsonResponse(
    {
      access_token: session.accessToken,
      refresh_token: session.refreshToken,
      expires_at: session.expiresAt,
      token: session.accessToken,
    },
    200,
  );
}

async function handlePost(req: Request): Promise<Response> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const request = parseRequestBody(body);
  if (!request) {
    return jsonResponse(
      {
        error:
          "Invalid request body. Expected teamupToken (string), deviceMemberId (UUID), surface (ios | memberWeb | coachWeb | ownerWeb).",
      },
      400,
    );
  }

  const verification = await verifyTeamUpToken(request.teamupToken);
  // Auth session only when OAuth is configured AND this is not the stub-token path.
  const useAuthSession = !shouldUseStubTeamUpPath(request.teamupToken);
  const result = await issueMemberSession(
    verification,
    request.deviceMemberId,
    request.surface,
    useAuthSession,
  );

  if ("error" in result) {
    return jsonResponse({ error: result.error }, result.status);
  }

  return sessionJsonResponse(result);
}

async function handleOAuthAuthorize(req: Request): Promise<Response> {
  const config = readTeamUpOAuthConfig();
  if (!config) {
    return jsonResponse({ error: "TeamUp OAuth is not configured" }, 404);
  }

  const params = parseOAuthAuthorizeParams(new URL(req.url));
  if (!params) {
    return jsonResponse(
      {
        error:
          "Invalid authorize request. Expected deviceMemberId (UUID), surface (ios | memberWeb | coachWeb | ownerWeb), optional returnUrl.",
      },
      400,
    );
  }

  const codeVerifier = generatePkceCodeVerifier();
  const codeChallenge = await pkceCodeChallengeS256(codeVerifier);
  const signingSecret = requireEnv("JWT_SIGNING_SECRET");
  const returnUrl = resolveOAuthReturnUrl(config, params.returnUrl);

  const state = await signOAuthState(
    {
      deviceMemberId: params.deviceMemberId,
      surface: params.surface,
      codeVerifier,
      returnUrl,
    },
    signingSecret,
  );

  const authorizeUrl = buildTeamUpAuthorizeUrl(config, {
    codeChallenge,
    state,
  });

  return redirectResponse(authorizeUrl);
}

async function handleOAuthCallback(req: Request): Promise<Response> {
  const config = readTeamUpOAuthConfig();
  if (!config) {
    return jsonResponse({ error: "TeamUp OAuth is not configured" }, 404);
  }

  const url = new URL(req.url);
  const {
    code,
    state: stateToken,
    error: oauthError,
    errorDescription,
  } = parseOAuthCallbackParams(url);
  if (oauthError) {
    const description = errorDescription ??
      "TeamUp authorization was denied";
    return jsonResponse({ error: description }, 400);
  }

  if (!code || !stateToken) {
    return jsonResponse(
      { error: "OAuth callback is missing code or state" },
      400,
    );
  }

  const signingSecret = requireEnv("JWT_SIGNING_SECRET");
  let state;
  try {
    state = await verifyOAuthState(stateToken, signingSecret);
  } catch {
    return jsonResponse({ error: "Invalid or expired OAuth state" }, 400);
  }

  const teamUpAccessToken = await exchangeTeamUpAuthorizationCode(config, {
    code,
    codeVerifier: state.codeVerifier,
  });

  const verification = decodeTeamUpAccessToken(teamUpAccessToken);
  // OAuth callback always uses the Auth-session path (requires OAuth config).
  const result = await issueMemberSession(
    verification,
    state.deviceMemberId,
    state.surface as Surface,
    true,
  );

  if ("error" in result) {
    return jsonResponse({ error: result.error }, result.status);
  }

  const returnUrl = resolveOAuthReturnUrl(config, state.returnUrl);
  if (returnUrl) {
    if (result.kind === "auth") {
      return redirectResponse(
        appendSessionToReturnUrl(returnUrl, {
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
          expiresAt: result.expiresAt,
        }),
      );
    }
    // Defensive: OAuth callback should never be HS256, but keep a fallback.
    return redirectResponse(appendTokenToReturnUrl(returnUrl, result.token));
  }

  return sessionJsonResponse(result);
}

function routeOAuthGet(req: Request): Response | Promise<Response> {
  const route = resolveOAuthGetRoute(new URL(req.url));

  if (route === "authorize") {
    return handleOAuthAuthorize(req);
  }
  if (route === "callback") {
    return handleOAuthCallback(req);
  }

  return jsonResponse({ error: "Method not allowed" }, 405);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method === "GET") {
      return await routeOAuthGet(req);
    }

    if (req.method === "POST") {
      return await handlePost(req);
    }

    return jsonResponse({ error: "Method not allowed" }, 405);
  } catch (error) {
    logCaughtError(error);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
