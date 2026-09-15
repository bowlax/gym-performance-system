/**
 * HTTP-level tests for the token-broker router.
 * These exercise handleBrokerRequest / handlePost — not helper booleans —
 * so stub-token rejection cannot regress to a decode throw → 500/502.
 */
import { assertEquals } from "jsr:@std/assert@1";
import { SignJWT } from "jsr:@panva/jose@6";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { verifyOAuthState } from "../_shared/teamup-oauth.ts";
import { handleOwnerMemberNamesRequest } from "../owner-member-names/handler.ts";
import {
  isLoopbackSupabaseUrl,
  onlyIfLoopback,
  tombstoneIsolatedGymTree,
} from "../_shared/test-isolated-gym-teardown.ts";
import { handleBrokerRequest, handlePost } from "./handler.ts";

const STUB_POST_BODY = JSON.stringify({
  teamupToken: "stub-token",
  deviceMemberId: "aaaaaaaa-0000-0000-0000-000000000001",
  surface: "ios",
});

function oauthConfiguredEnvGet(name: string): string | undefined {
  const values: Record<string, string> = {
    TEAMUP_OAUTH_CLIENT_ID: "client",
    TEAMUP_OAUTH_CLIENT_SECRET: "secret",
    TEAMUP_OAUTH_REDIRECT_URI:
      "https://broker.example/functions/v1/token-broker?oauth=callback",
    TEAMUP_OAUTH_PROVIDER_ID: "5404319",
    OAUTH_STATE_SECRET: "test-oauth-state-secret",
    TEAMUP_OAUTH_ALLOWED_RETURN_URLS_IOS: "gymperformance://connect",
  };
  return values[name];
}

async function authorizeStateReturnUrl(
  url: string,
): Promise<{ returnUrl: string | null; surface: string }> {
  const redirect = new URL(url);
  const state = redirect.searchParams.get("state");
  if (!state) {
    throw new Error("authorize redirect did not contain OAuth state");
  }
  const decoded = await verifyOAuthState(state, "test-oauth-state-secret");
  return { returnUrl: decoded.returnUrl, surface: decoded.surface };
}

Deno.test(
  "HTTP POST stub-token with OAuth configured returns 403 via handlePost (no decode/mint)",
  async () => {
    const originalGet = Deno.env.get.bind(Deno.env);
    Deno.env.get = oauthConfiguredEnvGet;
    try {
      const res = await handlePost(
        new Request("http://localhost/functions/v1/token-broker", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: STUB_POST_BODY,
        }),
      );
      assertEquals(res.status, 403);
      const body = await res.json() as { error?: string };
      assertEquals(
        body.error,
        "stub-token is not accepted when TeamUp OAuth is configured. Use the OAuth authorize flow.",
      );
    } finally {
      Deno.env.get = originalGet;
    }
  },
);

Deno.test(
  "HTTP POST stub-token with OAuth configured returns 403 via handleBrokerRequest router",
  async () => {
    const originalGet = Deno.env.get.bind(Deno.env);
    Deno.env.get = oauthConfiguredEnvGet;
    try {
      const res = await handleBrokerRequest(
        new Request("http://localhost/functions/v1/token-broker", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: STUB_POST_BODY,
        }),
      );
      assertEquals(res.status, 403);
      const body = await res.json() as { error?: string };
      assertEquals(
        body.error?.includes("stub-token is not accepted") ?? false,
        true,
      );
    } finally {
      Deno.env.get = originalGet;
    }
  },
);

Deno.test(
  "HTTP GET authorize keeps exact iOS callback when allowlisted",
  async () => {
    const originalGet = Deno.env.get.bind(Deno.env);
    Deno.env.get = oauthConfiguredEnvGet;
    try {
      const res = await handleBrokerRequest(
        new Request(
          "http://localhost/functions/v1/token-broker?oauth=authorize&deviceMemberId=aaaaaaaa-0000-0000-0000-000000000001&surface=ios&returnUrl=gymperformance%3A%2F%2Fconnect",
        ),
      );
      assertEquals(res.status, 302);
      const location = res.headers.get("Location");
      assertEquals(typeof location, "string");
      const state = await authorizeStateReturnUrl(location!);
      assertEquals(state.surface, "ios");
      assertEquals(state.returnUrl, "gymperformance://connect");
    } finally {
      Deno.env.get = originalGet;
    }
  },
);

Deno.test(
  "HTTP GET authorize drops non-allowlisted iOS callback",
  async () => {
    const originalGet = Deno.env.get.bind(Deno.env);
    Deno.env.get = oauthConfiguredEnvGet;
    try {
      const res = await handleBrokerRequest(
        new Request(
          "http://localhost/functions/v1/token-broker?oauth=authorize&deviceMemberId=aaaaaaaa-0000-0000-0000-000000000001&surface=ios&returnUrl=gymperf%3A%2F%2Fconnect",
        ),
      );
      assertEquals(res.status, 302);
      const location = res.headers.get("Location");
      assertEquals(typeof location, "string");
      const state = await authorizeStateReturnUrl(location!);
      assertEquals(state.surface, "ios");
      assertEquals(state.returnUrl, null);
    } finally {
      Deno.env.get = originalGet;
    }
  },
);

Deno.test(
  "HTTP GET authorize drops memberWeb callback when memberWeb allowlist is empty",
  async () => {
    const originalGet = Deno.env.get.bind(Deno.env);
    Deno.env.get = oauthConfiguredEnvGet;
    try {
      const res = await handleBrokerRequest(
        new Request(
          "http://localhost/functions/v1/token-broker?oauth=authorize&deviceMemberId=aaaaaaaa-0000-0000-0000-000000000001&surface=memberWeb&returnUrl=https%3A%2F%2Fapp.example%2Fauth%2Fcallback",
        ),
      );
      assertEquals(res.status, 302);
      const location = res.headers.get("Location");
      assertEquals(typeof location, "string");
      const state = await authorizeStateReturnUrl(location!);
      assertEquals(state.surface, "memberWeb");
      assertEquals(state.returnUrl, null);
    } finally {
      Deno.env.get = originalGet;
    }
  },
);

Deno.test(
  "HTTP GET authorize rejects unknown surface",
  async () => {
    const originalGet = Deno.env.get.bind(Deno.env);
    Deno.env.get = oauthConfiguredEnvGet;
    try {
      const res = await handleBrokerRequest(
        new Request(
          "http://localhost/functions/v1/token-broker?oauth=authorize&deviceMemberId=aaaaaaaa-0000-0000-0000-000000000001&surface=unknown&returnUrl=gymperformance%3A%2F%2Fconnect",
        ),
      );
      assertEquals(res.status, 400);
      const body = await res.json() as { error?: string };
      assertEquals(
        body.error,
        "Invalid authorize request. Expected deviceMemberId (UUID), surface (ios | memberWeb | coachWeb | ownerWeb), optional returnUrl.",
      );
    } finally {
      Deno.env.get = originalGet;
    }
  },
);

Deno.test(
  "HTTP GET authorize rejects missing surface",
  async () => {
    const originalGet = Deno.env.get.bind(Deno.env);
    Deno.env.get = oauthConfiguredEnvGet;
    try {
      const res = await handleBrokerRequest(
        new Request(
          "http://localhost/functions/v1/token-broker?oauth=authorize&deviceMemberId=aaaaaaaa-0000-0000-0000-000000000001&returnUrl=gymperformance%3A%2F%2Fconnect",
        ),
      );
      assertEquals(res.status, 400);
      const body = await res.json() as { error?: string };
      assertEquals(
        body.error,
        "Invalid authorize request. Expected deviceMemberId (UUID), surface (ios | memberWeb | coachWeb | ownerWeb), optional returnUrl.",
      );
    } finally {
      Deno.env.get = originalGet;
    }
  },
);

interface LiveEnv {
  url: string;
  anonKey: string;
  serviceRoleKey: string;
  jwtSecret: string;
}

/** Documented local `supabase start` JWT secret. Loopback PostgREST uses this. */
const LOCAL_SUPABASE_JWT_SECRET =
  "super-secret-jwt-token-with-at-least-32-characters-long";

function isJwtApiKey(value: string): boolean {
  return value.split(".").length === 3;
}

async function mintLocalRoleKey(
  secret: string,
  role: "anon" | "service_role",
): Promise<string> {
  return await new SignJWT({ role })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer("supabase-demo")
    .setExpirationTime("10y")
    .sign(new TextEncoder().encode(secret));
}

async function liveEnv(): Promise<LiveEnv | null> {
  const url = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("API_URL") ??
    "http://127.0.0.1:54321";
  const bounded = onlyIfLoopback({ url });
  if (!bounded) return null;

  const jwtSecret = Deno.env.get("JWT_SECRET") ?? LOCAL_SUPABASE_JWT_SECRET;
  const configuredAnon = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("ANON_KEY");
  const configuredService = Deno.env.get("SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  const anonKey = configuredAnon && isJwtApiKey(configuredAnon)
    ? configuredAnon
    : await mintLocalRoleKey(jwtSecret, "anon");
  const serviceRoleKey = configuredService && isJwtApiKey(configuredService)
    ? configuredService
    : await mintLocalRoleKey(jwtSecret, "service_role");

  return {
    url: bounded.url,
    anonKey,
    serviceRoleKey,
    jwtSecret,
  };
}

function makeFakeTeamUpJwt(claims: Record<string, unknown>): string {
  const json = JSON.stringify(claims);
  const bytes = new TextEncoder().encode(json);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  const payload = btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
  const header = btoa(JSON.stringify({ alg: "none", typ: "JWT" }))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
  return `${header}.${payload}.signature`;
}

async function mintOwnerJwt(
  secret: string,
  gymId: string,
  ownerId: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  return await new SignJWT({
    sub: ownerId,
    role: "authenticated",
    app_role: "owner",
    member_id: ownerId,
    gym_id: gymId,
  })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer("supabase")
    .setAudience("authenticated")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(new TextEncoder().encode(secret));
}

async function connectWithJwtName(
  teamupToken: string,
  deviceMemberId: string,
): Promise<Response> {
  return await handleBrokerRequest(
    new Request("http://localhost/functions/v1/token-broker", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        teamupToken,
        deviceMemberId,
        surface: "memberWeb",
      }),
    }),
  );
}

async function assertConnectOk(res: Response, label: string): Promise<void> {
  const body = await res.text();
  if (res.status !== 200) {
    throw new Error(`${label} HTTP ${res.status}: ${body}`);
  }
}

Deno.test({
  name: "HTTP POST connect writes JWT name onto members.display_name and reconnect overwrites",
  ignore: !isLoopbackSupabaseUrl(
    Deno.env.get("SUPABASE_URL") ?? Deno.env.get("API_URL") ??
      "http://127.0.0.1:54321",
  ),
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const env = await liveEnv();
    if (!env) throw new Error("live env disappeared");

    const originalGet = Deno.env.get.bind(Deno.env);
    Deno.env.get = (name: string) => {
      if (name === "SUPABASE_URL") return env.url;
      if (name === "SUPABASE_ANON_KEY") return env.anonKey;
      if (name === "SUPABASE_PUBLISHABLE_KEY") return env.anonKey;
      if (name === "GYMPERF_SUPABASE_PUBLISHABLE_KEY") return env.anonKey;
      if (name === "SERVICE_ROLE_KEY") return env.serviceRoleKey;
      if (name === "JWT_SIGNING_SECRET") return env.jwtSecret;
      if (name === "TEAMUP_OAUTH_CLIENT_ID") return "client";
      if (name === "TEAMUP_OAUTH_CLIENT_SECRET") return "secret";
      if (name === "TEAMUP_OAUTH_REDIRECT_URI") {
        return "https://broker.example/functions/v1/token-broker?oauth=callback";
      }
      if (name === "TEAMUP_OAUTH_PROVIDER_ID") return "5404319";
      return originalGet(name);
    };

    const admin = createClient(env.url, env.serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const gymId = crypto.randomUUID();
    const deviceMemberId = crypto.randomUUID();
    const ownerCaller = crypto.randomUUID();
    const providerId = String(
      1_000_000_000 + (Number.parseInt(gymId.slice(0, 8), 16) % 100_000_000),
    );
    const teamupCustomerId = `jwt-name-${gymId.slice(0, 8)}`;
    let authUserId: string | null = null;

    let testError: unknown;
    try {
      const gymInsert = await admin.from("gyms").insert({
        id: gymId,
        teamup_provider_id: providerId,
        name: "JWT Name Connect Gym",
      });
      if (gymInsert.error) throw gymInsert.error;

      const firstToken = makeFakeTeamUpJwt({
        sub: teamupCustomerId,
        email: "ignored@example.com",
        name: "Lee Ball",
        scope: `read_write provider:${providerId}`,
      });
      const firstRes = await connectWithJwtName(firstToken, deviceMemberId);
      await assertConnectOk(firstRes, "first connect");

      const firstRow = await admin
        .from("members")
        .select("id, display_name, auth_user_id, teamup_customer_id")
        .eq("gym_id", gymId)
        .eq("teamup_customer_id", teamupCustomerId)
        .is("deleted_at", null)
        .single();
      if (firstRow.error) throw firstRow.error;
      assertEquals(firstRow.data.display_name, "Lee Ball");
      assertEquals(firstRow.data.id, deviceMemberId);
      authUserId = typeof firstRow.data.auth_user_id === "string"
        ? firstRow.data.auth_user_id
        : null;

      const ownerToken = await mintOwnerJwt(env.jwtSecret, gymId, ownerCaller);
      const namesRes = await handleOwnerMemberNamesRequest(
        new Request("http://localhost/functions/v1/owner-member-names", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ownerToken}`,
            "Content-Type": "application/json",
          },
          body: "{}",
        }),
      );
      assertEquals(namesRes.status, 200);
      const namesBody = await namesRes.json() as {
        members: Array<{ member_id: string; display_name: string }>;
      };
      assertEquals(namesBody.members.length, 1);
      assertEquals(namesBody.members[0]?.display_name, "Lee Ball");

      const reconnectToken = makeFakeTeamUpJwt({
        sub: teamupCustomerId,
        name: "Ada Lovelace",
        scope: `read_write provider:${providerId}`,
      });
      const reconnectRes = await connectWithJwtName(
        reconnectToken,
        crypto.randomUUID(),
      );
      await assertConnectOk(reconnectRes, "reconnect");

      const secondRow = await admin
        .from("members")
        .select("id, display_name")
        .eq("gym_id", gymId)
        .eq("teamup_customer_id", teamupCustomerId)
        .is("deleted_at", null)
        .single();
      if (secondRow.error) throw secondRow.error;
      assertEquals(secondRow.data.id, deviceMemberId);
      assertEquals(secondRow.data.display_name, "Ada Lovelace");

      const namelessToken = makeFakeTeamUpJwt({
        sub: teamupCustomerId,
        scope: `read_write provider:${providerId}`,
      });
      const namelessRes = await connectWithJwtName(
        namelessToken,
        deviceMemberId,
      );
      await assertConnectOk(namelessRes, "nameless reconnect");

      const thirdRow = await admin
        .from("members")
        .select("display_name")
        .eq("id", deviceMemberId)
        .single();
      if (thirdRow.error) throw thirdRow.error;
      assertEquals(thirdRow.data.display_name, "Ada Lovelace");
    } catch (error) {
      testError = error;
    } finally {
      try {
        if (!authUserId) {
          const leftover = await admin
            .from("members")
            .select("auth_user_id")
            .eq("gym_id", gymId);
          const ids = (leftover.data ?? [])
            .map((row) => row.auth_user_id)
            .filter((id): id is string => typeof id === "string");
          authUserId = ids[0] ?? null;
        }
        if (authUserId) {
          await admin.auth.admin.deleteUser(authUserId);
        }
        await tombstoneIsolatedGymTree(admin, [gymId]);
      } catch (cleanupError) {
        testError ??= cleanupError;
      } finally {
        Deno.env.get = originalGet;
      }
    }
    if (testError) throw testError;
  },
});

