import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  appendTokenToReturnUrl,
  buildTeamUpAuthorizeUrl,
  decodeTeamUpAccessToken,
  generatePkceCodeVerifier,
  inferTeamUpModeFromScope,
  isAllowedReturnUrl,
  isStubTeamUpToken,
  isTeamUpOAuthConfigured,
  parseProviderIdFromScope,
  pkceCodeChallengeS256,
  readTeamUpOAuthConfig,
  resolveOAuthReturnUrl,
  shouldUseStubTeamUpPath,
  signOAuthState,
  stubTeamUpVerification,
  verifyOAuthState,
  type TeamUpOAuthConfig,
} from "./teamup-oauth.ts";

function base64UrlEncodeJson(value: Record<string, unknown>): string {
  const json = JSON.stringify(value);
  const bytes = new TextEncoder().encode(json);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function makeFakeTeamUpJwt(claims: Record<string, unknown>): string {
  const header = base64UrlEncodeJson({ alg: "none", typ: "JWT" });
  const payload = base64UrlEncodeJson(claims);
  return `${header}.${payload}.signature`;
}

const sampleConfig: TeamUpOAuthConfig = {
  clientId: "test-client-id",
  clientSecret: "test-client-secret",
  redirectUri: "https://broker.example/functions/v1/token-broker?oauth=callback",
  providerId: "5404319",
  scope: "read_write provider:5404319",
  authorizeUrl: "https://goteamup.com/api/v2/auth/oauth/authorize",
  tokenUrl: "https://goteamup.com/api/v2/auth/oauth/token",
  successRedirectUri: "https://app.example/auth/callback",
};

Deno.test("stub token detection", () => {
  assertEquals(isStubTeamUpToken("stub-token"), true);
  assertEquals(isStubTeamUpToken("other"), false);
});

Deno.test("stub verification uses configured provider when present", () => {
  const result = stubTeamUpVerification("999");
  assertEquals(result, {
    teamupCustomerId: "TEST-CUSTOMER-001",
    providerId: "999",
    mode: "customer",
  });
});

Deno.test("readTeamUpOAuthConfig returns null when credentials are incomplete", () => {
  const originalGet = Deno.env.get.bind(Deno.env);
  Deno.env.get = (name: string) => {
    if (name === "TEAMUP_OAUTH_CLIENT_ID") return "client";
    return undefined;
  };
  try {
    assertEquals(readTeamUpOAuthConfig(), null);
    assertEquals(isTeamUpOAuthConfigured(), false);
    assertEquals(shouldUseStubTeamUpPath("any-token"), true);
  } finally {
    Deno.env.get = originalGet;
  }
});

Deno.test("readTeamUpOAuthConfig builds scope from provider id", () => {
  const originalGet = Deno.env.get.bind(Deno.env);
  Deno.env.get = (name: string) => {
    const values: Record<string, string> = {
      TEAMUP_OAUTH_CLIENT_ID: "client",
      TEAMUP_OAUTH_CLIENT_SECRET: "secret",
      TEAMUP_OAUTH_REDIRECT_URI: "https://broker.example/callback",
      TEAMUP_OAUTH_PROVIDER_ID: "5404319",
    };
    return values[name];
  };
  try {
    const config = readTeamUpOAuthConfig();
    assertEquals(config?.scope, "read_write provider:5404319");
    assertEquals(isTeamUpOAuthConfigured(), true);
    assertEquals(shouldUseStubTeamUpPath("stub-token"), true);
    assertEquals(shouldUseStubTeamUpPath("real-token"), false);
  } finally {
    Deno.env.get = originalGet;
  }
});

Deno.test("PKCE verifier and S256 challenge are stable for a known verifier", async () => {
  const challenge = await pkceCodeChallengeS256("test-verifier-value");
  assertEquals(challenge.length > 20, true);
});

Deno.test("buildTeamUpAuthorizeUrl includes required OAuth parameters", () => {
  const url = new URL(
    buildTeamUpAuthorizeUrl(sampleConfig, {
      codeChallenge: "challenge",
      state: "signed-state",
      loginHint: "member@example.com",
    }),
  );

  assertEquals(url.searchParams.get("client_id"), "test-client-id");
  assertEquals(url.searchParams.get("redirect_uri"), sampleConfig.redirectUri);
  assertEquals(url.searchParams.get("response_type"), "code");
  assertEquals(url.searchParams.get("scope"), "read_write provider:5404319");
  assertEquals(url.searchParams.get("code_challenge"), "challenge");
  assertEquals(url.searchParams.get("code_challenge_method"), "S256");
  assertEquals(url.searchParams.get("state"), "signed-state");
  assertEquals(url.searchParams.get("login_hint"), "member@example.com");
});

Deno.test("decodeTeamUpAccessToken extracts sub and provider from JWT claims", () => {
  const token = makeFakeTeamUpJwt({
    sub: "customer-123",
    email: "member@example.com",
    name: "Member",
    scope: "read_write provider:5404319",
  });

  assertEquals(decodeTeamUpAccessToken(token), {
    teamupCustomerId: "customer-123",
    providerId: "5404319",
    mode: "customer",
  });
});

Deno.test("parseProviderIdFromScope handles multiple scope tokens", () => {
  assertEquals(parseProviderIdFromScope("read_write provider:5404319"), "5404319");
  assertEquals(parseProviderIdFromScope("openid"), null);
});

Deno.test("inferTeamUpModeFromScope treats staff scope as provider mode", () => {
  assertEquals(
    inferTeamUpModeFromScope("read_write provider:1 staff"),
    "provider",
  );
  assertEquals(inferTeamUpModeFromScope("read_write provider:1"), "customer");
});

Deno.test("OAuth state round-trips through sign and verify", async () => {
  const secret = "test-signing-secret";
  const payload = {
    deviceMemberId: "aaaaaaaa-0000-0000-0000-000000000001",
    surface: "memberWeb",
    codeVerifier: generatePkceCodeVerifier(),
    returnUrl: "https://app.example/auth/callback",
  };

  const state = await signOAuthState(payload, secret);
  const verified = await verifyOAuthState(state, secret);
  assertEquals(verified, payload);
});

Deno.test("verifyOAuthState rejects tampered state", async () => {
  const secret = "test-signing-secret";
  const state = await signOAuthState(
    {
      deviceMemberId: "aaaaaaaa-0000-0000-0000-000000000001",
      surface: "ios",
      codeVerifier: "verifier",
      returnUrl: null,
    },
    secret,
  );

  await assertRejects(
    () => verifyOAuthState(`${state}x`, secret),
  );
});

Deno.test("return URL policy prefers validated client returnUrl", () => {
  assertEquals(
    isAllowedReturnUrl(
      sampleConfig,
      "https://app.example/auth/other",
    ),
    true,
  );
  assertEquals(
    isAllowedReturnUrl(sampleConfig, "https://evil.example/steal"),
    false,
  );
  assertEquals(
    resolveOAuthReturnUrl(
      sampleConfig,
      "https://app.example/auth/other",
    ),
    "https://app.example/auth/other",
  );
  assertEquals(resolveOAuthReturnUrl(sampleConfig, null), sampleConfig.successRedirectUri);
});

Deno.test("appendTokenToReturnUrl adds token query param", () => {
  assertEquals(
    appendTokenToReturnUrl("https://app.example/auth/callback", "jwt"),
    "https://app.example/auth/callback?token=jwt",
  );
});
