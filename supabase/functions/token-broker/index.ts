/**
 * Token Broker — Supabase Edge Function
 *
 * Exchanges a TeamUp access token (plus device member UUID and surface) for a
 * Supabase JWT carrying member_id, gym_id, and app_role claims for RLS.
 *
 * Required environment variables (set via `supabase secrets set` or `.env` for local serve):
 *   SUPABASE_URL        — project API URL (provided automatically on hosted runtime)
 *   SERVICE_ROLE_KEY    — service role secret key (bypasses RLS for member create/adopt)
 *   JWT_SIGNING_SECRET  — JWT signing secret (Settings → API → JWT Secret)
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

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { SignJWT } from "jsr:@panva/jose@6";

// Minimal schema types for compile-time checking without a generated Database type.
interface GymRow {
  id: string;
}

interface MemberRow {
  id: string;
}

type ServiceClient = SupabaseClient;

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type Surface = "ios" | "memberWeb" | "coachWeb" | "ownerWeb";
type AppRole = "member" | "coach" | "owner";
type TeamUpMode = "customer" | "provider";

interface TeamUpVerificationResult {
  teamupCustomerId: string;
  providerId: string;
  mode: TeamUpMode;
}

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

/**
 * TODO: Replace with a real call to TeamUp's API once API access is available.
 * Must verify the token, extract customer ID, provider/gym ID, and auth mode.
 */
async function verifyTeamUpToken(
  _token: string,
): Promise<TeamUpVerificationResult> {
  return {
    teamupCustomerId: "TEST-CUSTOMER-001",
    providerId: "5404319",
    mode: "customer",
  };
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
): Promise<string> {
  const { data: existing, error: lookupError } = await supabase
    .from("members")
    .select("id")
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
    return existingMember.id;
  }

  const { data: created, error: insertError } = await supabase
    .from("members")
    .insert({
      id: deviceMemberId,
      gym_id: gymId,
      teamup_customer_id: teamupCustomerId,
    })
    .select("id")
    .single();

  if (insertError) {
    logSupabaseError("createOrAdoptMember.insert", insertError);
    throw insertError;
  }

  return (created as MemberRow).id;
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
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
    const role = surfaceToRole(request.surface);

    if (verification.mode === "customer" && isStaffSurface(request.surface)) {
      return jsonResponse(
        { error: "TeamUp customer token cannot access staff surfaces" },
        403,
      );
    }

    const supabase = createServiceClient();
    const gymId = await lookupGymId(supabase, verification.providerId);

    if (!gymId) {
      return jsonResponse({ error: "Gym not found for TeamUp provider" }, 404);
    }

    const memberId = await createOrAdoptMember(
      supabase,
      gymId,
      verification.teamupCustomerId,
      request.deviceMemberId,
    );

    const token = await mintSupabaseJwt(memberId, gymId, role);

    return jsonResponse({ token }, 200);
  } catch (error) {
    logCaughtError(error);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
