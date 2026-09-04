import { describe, expect, test } from "bun:test";
import { authorizeBotKey, timingSafeEqual } from "./bot-auth";
import { handleOwnerFetch, handleOwnerScheduled, type OwnerApiEnv } from "./owner-api-handlers";
import {
  isValidOwnerSessionData,
  readSealedOwnerSession,
  sessionNeedsRefresh,
  unsealOwnerSession,
  writeSealedOwnerSession,
  type OwnerSessionData,
} from "./session-store";
import { refreshGoTrueSession } from "./gotrue-refresh";

const BOT_KEY = "k".repeat(32) + "-bot";
const SESSION_SECRET = "s".repeat(32) + "-session-secret";
const REFRESH_TOKEN = "owner-refresh-token-value";
const ACCESS_TOKEN = "owner-access-token-value";

function memoryKv(initial: Record<string, string> = {}) {
  const data = { ...initial };
  return {
    get: async (key: string) => data[key] ?? null,
    put: async (key: string, value: string) => {
      data[key] = value;
    },
    snapshot: () => ({ ...data }),
  };
}

async function makeEnv(
  session: OwnerSessionData | null,
): Promise<OwnerApiEnv & { kv: ReturnType<typeof memoryKv> }> {
  const kv = memoryKv();
  if (session) {
    await writeSealedOwnerSession(kv, SESSION_SECRET, session);
  }
  return {
    OWNER_BOT_KEY: BOT_KEY,
    OWNER_SESSION_SECRET: SESSION_SECRET,
    OWNER_SESSION: kv,
    SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
    kv,
  };
}

function ownerRequest(path: string, init?: RequestInit): Request {
  return new Request(`https://gymperf-owner-api.example${path}`, {
    method: "POST",
    ...init,
    headers: {
      Authorization: `Bearer ${BOT_KEY}`,
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
}

function session(expiresAt: number): OwnerSessionData {
  return {
    accessToken: ACCESS_TOKEN,
    refreshToken: REFRESH_TOKEN,
    expiresAt,
    issuedAt: expiresAt - 3600,
  };
}

function headerAuth(init?: RequestInit): string | undefined {
  const headers = init?.headers;
  if (!headers) return undefined;
  if (headers instanceof Headers) return headers.get("Authorization") ?? undefined;
  if (Array.isArray(headers)) {
    return headers.find(([key]) => key.toLowerCase() === "authorization")?.[1];
  }
  return (headers as Record<string, string>).Authorization;
}

describe("bot key", () => {
  test("missing Authorization is missing", () => {
    expect(
      authorizeBotKey(new Request("https://x/api/owner/current-pbs", { method: "POST" }), BOT_KEY),
    ).toBe("missing");
  });

  test("wrong key is wrong", () => {
    expect(
      authorizeBotKey(
        new Request("https://x/api/owner/current-pbs", {
          method: "POST",
          headers: { Authorization: "Bearer not-the-key-not-the-key-not-the-key" },
        }),
        BOT_KEY,
      ),
    ).toBe("wrong");
  });

  test("timingSafeEqual rejects mismatched lengths", () => {
    expect(timingSafeEqual("abc", "ab")).toBe(false);
    expect(timingSafeEqual(BOT_KEY, BOT_KEY)).toBe(true);
  });
});

describe("handleOwnerFetch HTTP", () => {
  test("missing bot key -> 401 and no secrets in body", async () => {
    const env = await makeEnv(session(9_999_999_999));
    const response = await handleOwnerFetch(
      new Request("https://x/api/owner/current-pbs", { method: "POST" }),
      env,
    );
    expect(response.status).toBe(401);
    const text = await response.text();
    expect(text).not.toContain(BOT_KEY);
    expect(text).not.toContain(REFRESH_TOKEN);
    expect(JSON.parse(text)).toEqual({ error: "Unauthorized" });
  });

  test("wrong bot key -> 403", async () => {
    const env = await makeEnv(session(9_999_999_999));
    const response = await handleOwnerFetch(
      new Request("https://x/api/owner/current-pbs", {
        method: "POST",
        headers: { Authorization: `Bearer ${"z".repeat(40)}` },
      }),
      env,
    );
    expect(response.status).toBe(403);
    const text = await response.text();
    expect(text).not.toContain(BOT_KEY);
    expect(JSON.parse(text)).toEqual({ error: "Forbidden" });
  });

  test("GET is 405 even with a valid bot key", async () => {
    const env = await makeEnv(session(9_999_999_999));
    const response = await handleOwnerFetch(
      new Request("https://x/api/owner/current-pbs", {
        method: "GET",
        headers: { Authorization: `Bearer ${BOT_KEY}` },
      }),
      env,
    );
    expect(response.status).toBe(405);
  });

  test("short refresh token substring in upstream body is not a 502", async () => {
    const shortRefresh = "shorttok12ab";
    const env = await makeEnv({
      accessToken: ACCESS_TOKEN,
      refreshToken: shortRefresh,
      expiresAt: 9_999_999_999,
      issuedAt: 9_999_996_399,
    });
    const response = await handleOwnerFetch(ownerRequest("/api/owner/current-pbs"), env, {
      fetchImpl: async () =>
        new Response(
          JSON.stringify({
            currentPBs: [{ member_id: "m1", note: `name contains ${shortRefresh}` }],
          }),
          { status: 200 },
        ),
    });
    expect(response.status).toBe(200);
    const text = await response.text();
    expect(text).toContain(shortRefresh);
    expect(text).not.toContain(BOT_KEY);
    expect(text).not.toContain(ACCESS_TOKEN);
  });

  test("correct bot key proxies owner-current-pbs", async () => {
    const env = await makeEnv(session(9_999_999_999));
    const response = await handleOwnerFetch(ownerRequest("/api/owner/current-pbs"), env, {
      fetchImpl: async (input) => {
        expect(String(input)).toContain("/functions/v1/owner-current-pbs");
        return new Response(JSON.stringify({ currentPBs: [{ member_id: "m1" }] }), {
          status: 200,
        });
      },
    });
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body).toEqual({ currentPBs: [{ member_id: "m1" }] });
    expect(JSON.stringify(body)).not.toContain(BOT_KEY);
    expect(JSON.stringify(body)).not.toContain(REFRESH_TOKEN);
    expect(JSON.stringify(body)).not.toContain(ACCESS_TOKEN);
  });

  test("correct bot key proxies owner-pb-frequency body", async () => {
    let captured = "";
    const env = await makeEnv(session(9_999_999_999));
    const response = await handleOwnerFetch(
      ownerRequest("/api/owner/pb-frequency", {
        body: JSON.stringify({ period: "this_week" }),
      }),
      env,
      {
        fetchImpl: async (input, init) => {
          expect(String(input)).toContain("/functions/v1/owner-pb-frequency");
          captured = String(init?.body);
          return new Response(JSON.stringify({ members: [] }), { status: 200 });
        },
      },
    );
    expect(response.status).toBe(200);
    expect(JSON.parse(captured)).toEqual({ period: "this_week" });
  });

  test("correct bot key proxies owner-member-names", async () => {
    const env = await makeEnv(session(9_999_999_999));
    const response = await handleOwnerFetch(ownerRequest("/api/owner/members"), env, {
      fetchImpl: async (input) => {
        expect(String(input)).toContain("/functions/v1/owner-member-names");
        return new Response(
          JSON.stringify({ members: [{ member_id: "m1", display_name: "Ada" }] }),
          { status: 200 },
        );
      },
    });
    expect(response.status).toBe(200);
    const body = await response.json() as { members: Array<{ display_name: string }> };
    expect(body.members[0]?.display_name).toBe("Ada");
  });

  test("unprovisioned session -> 503", async () => {
    const env = await makeEnv(null);
    const response = await handleOwnerFetch(ownerRequest("/api/owner/current-pbs"), env);
    expect(response.status).toBe(503);
    const text = await response.text();
    expect(text).not.toContain(BOT_KEY);
    expect(JSON.parse(text)).toEqual({ error: "Owner session not provisioned" });
  });

  test("near-expiry refreshes, rotates refresh_token in KV, returns proxy body only", async () => {
    const now = 1_700_000_000;
    const env = await makeEnv(session(now + 10));
    const response = await handleOwnerFetch(ownerRequest("/api/owner/current-pbs"), env, {
      nowSeconds: now,
      fetchImpl: async (input, init) => {
        const url = String(input);
        if (url.includes("grant_type=refresh_token")) {
          expect(JSON.parse(String(init?.body)).refresh_token).toBe(REFRESH_TOKEN);
          return new Response(
            JSON.stringify({
              access_token: "new-at",
              refresh_token: "rotated-rt",
              expires_in: 3600,
            }),
            { status: 200 },
          );
        }
        expect(headerAuth(init)).toBe("Bearer new-at");
        return new Response(JSON.stringify({ currentPBs: [] }), { status: 200 });
      },
    });
    expect(response.status).toBe(200);
    const text = await response.text();
    expect(text).toBe(JSON.stringify({ currentPBs: [] }));
    expect(text).not.toContain("rotated-rt");
    expect(text).not.toContain(REFRESH_TOKEN);

    const stored = await readSealedOwnerSession(env.kv, SESSION_SECRET);
    expect(stored?.refreshToken).toBe("rotated-rt");
    expect(stored?.accessToken).toBe("new-at");
  });

  test("GoTrue refresh failure is 502 without upstream body or tokens", async () => {
    const now = 1_700_000_000;
    const env = await makeEnv(session(now + 10));
    const response = await handleOwnerFetch(ownerRequest("/api/owner/current-pbs"), env, {
      nowSeconds: now,
      fetchImpl: async () =>
        new Response(JSON.stringify({ error: REFRESH_TOKEN }), { status: 400 }),
    });
    expect(response.status).toBe(502);
    const text = await response.text();
    expect(text).toBe(JSON.stringify({ error: "Owner upstream failed" }));
    expect(text).not.toContain(REFRESH_TOKEN);
    expect(text).not.toContain(BOT_KEY);
  });
});

describe("handleOwnerScheduled", () => {
  test("calls member-names refresh with the stored owner access token", async () => {
    let called = "";
    const env = await makeEnv(session(9_999_999_999));
    await handleOwnerScheduled(env, {
      fetchImpl: async (input) => {
        called = String(input);
        return new Response(JSON.stringify({ members: [] }), { status: 200 });
      },
    });
    expect(called).toContain("/functions/v1/owner-member-names");
    expect(called).toContain("refresh=1");
  });
});

describe("session seal", () => {
  test("round-trips and is not plaintext in KV", async () => {
    const kv = memoryKv();
    const data = session(1_800_000_000);
    await writeSealedOwnerSession(kv, SESSION_SECRET, data);
    const raw = kv.snapshot().lee;
    expect(raw).toBeTruthy();
    expect(raw).not.toContain(REFRESH_TOKEN);
    expect(raw).not.toContain(ACCESS_TOKEN);
    const loaded = await unsealOwnerSession(SESSION_SECRET, raw!);
    expect(loaded).toEqual(data);
    expect(isValidOwnerSessionData(loaded)).toBe(true);
  });

  test("sessionNeedsRefresh matches iOS 60s skew", () => {
    expect(sessionNeedsRefresh(1000, 939)).toBe(false);
    expect(sessionNeedsRefresh(1000, 940)).toBe(true);
  });
});

describe("refreshGoTrueSession", () => {
  test("maps GoTrue JSON and requires rotated refresh_token", async () => {
    const result = await refreshGoTrueSession({
      refreshToken: "old",
      supabaseUrl: "https://example.supabase.co",
      publishableKey: "anon",
      nowSeconds: 1000,
      fetchImpl: async (input, init) => {
        expect(String(input)).toContain("grant_type=refresh_token");
        expect(JSON.parse(String(init?.body)).refresh_token).toBe("old");
        return new Response(
          JSON.stringify({
            access_token: "new-at",
            refresh_token: "new-rt",
            expires_in: 3600,
          }),
          { status: 200 },
        );
      },
    });
    expect(result).toEqual({
      accessToken: "new-at",
      refreshToken: "new-rt",
      expiresAt: 4600,
    });
  });

  test("accepts string expires_in and millisecond expires_at", async () => {
    const stringIn = await refreshGoTrueSession({
      refreshToken: "old",
      supabaseUrl: "https://example.supabase.co",
      publishableKey: "anon",
      nowSeconds: 1000,
      fetchImpl: async () =>
        new Response(
          JSON.stringify({
            access_token: "new-at",
            refresh_token: "new-rt",
            expires_in: "3600",
          }),
          { status: 200 },
        ),
    });
    expect(stringIn.expiresAt).toBe(4600);

    const millis = await refreshGoTrueSession({
      refreshToken: "old",
      supabaseUrl: "https://example.supabase.co",
      publishableKey: "anon",
      nowSeconds: 1000,
      fetchImpl: async () =>
        new Response(
          JSON.stringify({
            access_token: "new-at",
            refresh_token: "new-rt",
            expires_at: 1_700_000_000_000,
          }),
          { status: 200 },
        ),
    });
    expect(millis.expiresAt).toBe(1_700_000_000);
  });

  test("defaults expiry rather than dropping a rotated refresh_token", async () => {
    const result = await refreshGoTrueSession({
      refreshToken: "old",
      supabaseUrl: "https://example.supabase.co",
      publishableKey: "anon",
      nowSeconds: 1000,
      fetchImpl: async () =>
        new Response(
          JSON.stringify({
            access_token: "new-at",
            refresh_token: "new-rt",
          }),
          { status: 200 },
        ),
    });
    expect(result).toEqual({
      accessToken: "new-at",
      refreshToken: "new-rt",
      expiresAt: 4600,
    });
  });
});
