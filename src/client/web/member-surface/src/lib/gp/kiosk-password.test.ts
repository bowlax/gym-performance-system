import { describe, expect, test } from "bun:test";
import { AUTH_SESSION_COOKIE } from "./auth-session";
import {
  KIOSK_SESSION_COOKIE,
  KIOSK_SESSION_MAX_AGE_SECONDS,
} from "./kiosk-session";
import {
  appRoleFromAccessToken,
  KioskLoginError,
  signInOwnerWithPassword,
} from "./kiosk-password";

function jwt(payload: Record<string, unknown>): string {
  const body = btoa(JSON.stringify(payload))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
  return `eyJhbGciOiJub25lIn0.${body}.sig`;
}

describe("kiosk owner login", () => {
  test("cookie is separate from the member session and lasts 400 days", () => {
    expect(KIOSK_SESSION_COOKIE).toBe("gp_kiosk");
    expect(KIOSK_SESSION_COOKIE).not.toBe(AUTH_SESSION_COOKIE);
    expect(KIOSK_SESSION_MAX_AGE_SECONDS).toBe(60 * 60 * 24 * 400);
  });

  test("accepts an owner password grant and rejects a member token", async () => {
    const ownerToken = jwt({ app_role: "owner" });
    const memberToken = jwt({ app_role: "member" });
    expect(appRoleFromAccessToken(ownerToken)).toBe("owner");

    const session = await signInOwnerWithPassword({
      email: "lee@example.com",
      password: "secret",
      supabaseUrl: "https://example.supabase.co",
      publishableKey: "anon",
      nowSeconds: 1_700_000_000,
      fetchImpl: async (input) => {
        expect(String(input)).toContain("grant_type=password");
        return new Response(
          JSON.stringify({
            access_token: ownerToken,
            refresh_token: "refresh-token-value",
            expires_in: 3600,
          }),
          { status: 200 },
        );
      },
    });
    expect(session.accessToken).toBe(ownerToken);
    expect(session.expiresAt).toBe(1_700_003_600);

    await expect(
      signInOwnerWithPassword({
        email: "member@example.com",
        password: "secret",
        supabaseUrl: "https://example.supabase.co",
        publishableKey: "anon",
        fetchImpl: async () =>
          new Response(
            JSON.stringify({
              access_token: memberToken,
              refresh_token: "refresh-token-value",
              expires_in: 3600,
            }),
            { status: 200 },
          ),
      }),
    ).rejects.toMatchObject({ status: 403, name: "KioskLoginError" });

    await expect(
      signInOwnerWithPassword({
        email: "lee@example.com",
        password: "nope",
        supabaseUrl: "https://example.supabase.co",
        publishableKey: "anon",
        fetchImpl: async () => new Response("{}", { status: 400 }),
      }),
    ).rejects.toBeInstanceOf(KioskLoginError);
  });
});
