/**
 * HTTP-level tests for the token-broker router.
 * These exercise handleBrokerRequest / handlePost — not helper booleans —
 * so stub-token rejection cannot regress to a decode throw → 500/502.
 */
import { assertEquals } from "jsr:@std/assert@1";
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
    TEAMUP_OAUTH_REDIRECT_URI: "https://broker.example/callback",
    TEAMUP_OAUTH_PROVIDER_ID: "5404319",
  };
  return values[name];
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
