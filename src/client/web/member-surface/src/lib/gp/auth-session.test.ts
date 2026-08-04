import { describe, expect, test } from "bun:test";
import {
  assertCleanRedirectLocation,
  buildBrokerAuthorizeUrl,
  isDeviceMemberId,
  parseCallbackSessionParams,
  sessionNeedsRefresh,
  toSessionJson,
  type AuthSessionData,
} from "./auth-session";
import {
  assertSessionJsonSafe,
  handleAuthSessionGet,
  handleOAuthCallback,
  type AuthSessionStore,
} from "./auth-handlers";
import { refreshGoTrueSession } from "./gotrue-refresh.server";
import {
  getOrCreateDeviceMemberId,
  readDeviceMemberIdFromCookie,
} from "./device-member-id";

function memoryStore(initial: AuthSessionData | null = null): AuthSessionStore & {
  snapshot: () => AuthSessionData | null;
} {
  let data = initial;
  return {
    read: async () => data,
    write: async (next) => {
      data = next;
    },
    clear: async () => {
      data = null;
    },
    snapshot: () => data,
  };
}

describe("parseCallbackSessionParams", () => {
  test("accepts access_token + refresh_token + expires_at", () => {
    const url = new URL(
      "https://example.com/auth/callback?access_token=at&refresh_token=rt&expires_at=1700000000",
    );
    const session = parseCallbackSessionParams(url);
    expect(session?.accessToken).toBe("at");
    expect(session?.refreshToken).toBe("rt");
    expect(session?.expiresAt).toBe(1700000000);
  });

  test("accepts token alias for access_token", () => {
    const url = new URL(
      "https://example.com/auth/callback?token=at&refresh_token=rt&expires_at=1700000000",
    );
    expect(parseCallbackSessionParams(url)?.accessToken).toBe("at");
  });

  test("rejects missing refresh_token", () => {
    const url = new URL(
      "https://example.com/auth/callback?access_token=at&expires_at=1700000000",
    );
    expect(parseCallbackSessionParams(url)).toBeNull();
  });
});

describe("handleOAuthCallback", () => {
  test("sets session and redirects clean (no tokens in Location)", async () => {
    const store = memoryStore();
    const request = new Request(
      "https://gymperf-member-web.7r2t2gzhkq.workers.dev/auth/callback?access_token=access-1&refresh_token=refresh-1&expires_at=9999999999",
    );
    const response = await handleOAuthCallback(request, store);

    expect(response.status).toBe(302);
    const location = response.headers.get("Location");
    expect(location).toBe("/");
    assertCleanRedirectLocation(location!);
    expect(location).not.toContain("access_token");
    expect(location).not.toContain("refresh_token");
    expect(location).not.toContain("token=");

    const written = store.snapshot();
    expect(written?.accessToken).toBe("access-1");
    expect(written?.refreshToken).toBe("refresh-1");
    expect(written?.expiresAt).toBe(9999999999);
  });

  test("returns 400 when params missing", async () => {
    const store = memoryStore();
    const response = await handleOAuthCallback(
      new Request("https://example.com/auth/callback?access_token=only"),
      store,
    );
    expect(response.status).toBe(400);
    expect(store.snapshot()).toBeNull();
  });
});

describe("handleAuthSessionGet", () => {
  test("no cookie -> 401", async () => {
    const response = await handleAuthSessionGet({
      store: memoryStore(),
      refresh: async () => {
        throw new Error("should not refresh");
      },
    });
    expect(response.status).toBe(401);
    const body = await response.json();
    expect(body).not.toHaveProperty("refresh_token");
  });

  test("valid unexpired access token -> returns token only", async () => {
    const now = 1_700_000_000;
    const store = memoryStore({
      accessToken: "live-at",
      refreshToken: "secret-rt",
      expiresAt: now + 3600,
      issuedAt: now,
    });
    const response = await handleAuthSessionGet({
      store,
      nowSeconds: now,
      refresh: async () => {
        throw new Error("should not refresh");
      },
    });
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body).toEqual({ token: "live-at", expiresAt: now + 3600 });
    assertSessionJsonSafe(body);
    expect(JSON.stringify(body)).not.toContain("secret-rt");
    expect(JSON.stringify(body)).not.toContain("refresh");
  });

  test("expired cookie with valid refresh -> rotates refresh_token in cookie, returns new access", async () => {
    const now = 1_700_000_000;
    const store = memoryStore({
      accessToken: "old-at",
      refreshToken: "old-rt",
      expiresAt: now - 10,
      issuedAt: now - 4000,
    });

    const response = await handleAuthSessionGet({
      store,
      nowSeconds: now,
      refresh: async (refreshToken) => {
        expect(refreshToken).toBe("old-rt");
        return {
          accessToken: "new-at",
          refreshToken: "rotated-rt",
          expiresAt: now + 3600,
        };
      },
    });

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body).toEqual({ token: "new-at", expiresAt: now + 3600 });
    assertSessionJsonSafe(body);
    expect(JSON.stringify(body)).not.toContain("rotated-rt");
    expect(JSON.stringify(body)).not.toContain("old-rt");

    const cookie = store.snapshot();
    expect(cookie?.accessToken).toBe("new-at");
    expect(cookie?.refreshToken).toBe("rotated-rt");
  });

  test("refresh failure clears cookie and returns 401", async () => {
    const now = 1_700_000_000;
    const store = memoryStore({
      accessToken: "old-at",
      refreshToken: "bad-rt",
      expiresAt: now - 10,
      issuedAt: now - 4000,
    });
    const response = await handleAuthSessionGet({
      store,
      nowSeconds: now,
      refresh: async () => {
        throw new Error("invalid refresh");
      },
    });
    expect(response.status).toBe(401);
    expect(store.snapshot()).toBeNull();
  });
});

describe("toSessionJson / sessionNeedsRefresh", () => {
  test("never exposes refresh_token", () => {
    const json = toSessionJson({
      accessToken: "a",
      refreshToken: "must-not-leak",
      expiresAt: 1,
      issuedAt: 1,
    });
    assertSessionJsonSafe(json);
    expect(JSON.stringify(json)).not.toContain("must-not-leak");
  });

  test("refresh skew matches 60s", () => {
    expect(sessionNeedsRefresh(1000, 939)).toBe(false);
    expect(sessionNeedsRefresh(1000, 940)).toBe(true);
  });
});

describe("deviceMemberId", () => {
  test("reads persisted UUID from cookie", () => {
    const id = "550e8400-e29b-41d4-a716-446655440000";
    expect(readDeviceMemberIdFromCookie(`gp_device_member_id=${id}`)).toBe(id);
    expect(isDeviceMemberId(id)).toBe(true);
  });

  test("generates once and persists via write callback", () => {
    let written = "";
    const first = getOrCreateDeviceMemberId("", (id) => {
      written = id;
    });
    expect(isDeviceMemberId(first)).toBe(true);
    expect(written).toBe(first);
    const second = getOrCreateDeviceMemberId(
      `gp_device_member_id=${first}`,
      () => {
        throw new Error("should not rewrite");
      },
    );
    expect(second).toBe(first);
  });
});

describe("buildBrokerAuthorizeUrl", () => {
  test("includes surface memberWeb and returnUrl", () => {
    const url = buildBrokerAuthorizeUrl({
      brokerBaseUrl: "https://example.supabase.co/functions/v1/token-broker",
      deviceMemberId: "550e8400-e29b-41d4-a716-446655440000",
      returnUrl:
        "https://gymperf-member-web.7r2t2gzhkq.workers.dev/auth/callback",
    });
    const parsed = new URL(url);
    expect(parsed.searchParams.get("oauth")).toBe("authorize");
    expect(parsed.searchParams.get("surface")).toBe("memberWeb");
    expect(parsed.searchParams.get("returnUrl")).toBe(
      "https://gymperf-member-web.7r2t2gzhkq.workers.dev/auth/callback",
    );
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
        expect(init?.method).toBe("POST");
        const body = JSON.parse(String(init?.body));
        expect(body.refresh_token).toBe("old");
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
});
