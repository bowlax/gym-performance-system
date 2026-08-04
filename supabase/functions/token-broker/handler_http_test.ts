/**
 * HTTP-level tests for the token-broker router.
 * These exercise handleBrokerRequest / handlePost — not helper booleans —
 * so stub-token rejection cannot regress to a decode throw → 500/502.
 */
import { assertEquals } from "jsr:@std/assert@1";
import { verifyOAuthState } from "../_shared/teamup-oauth.ts";
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
