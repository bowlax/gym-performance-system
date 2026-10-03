import { describe, expect, test } from "bun:test";
import {
  KIOSK_CONFIRM_INVALID_MESSAGE,
  commitKioskPending,
  isKioskConfirmToken,
  kioskConfirmReturnPath,
  sha256Hex,
  stashKioskConfirmReturn,
  takeKioskConfirmReturn,
  tokenFromKioskConfirmReturn,
} from "./kiosk-confirm";

const TOKEN = "abcdefghijklmnopqrst";
const SUPABASE_URL = "https://ivrsxhuktebvypgtfoww.supabase.co";
const PUBLISHABLE = "publishable-key";

function installSessionStorage() {
  const data = new Map<string, string>();
  const storage = {
    getItem: (key: string) => (data.has(key) ? data.get(key)! : null),
    setItem: (key: string, value: string) => {
      data.set(key, value);
    },
    removeItem: (key: string) => {
      data.delete(key);
    },
    clear: () => data.clear(),
    key: () => null,
    get length() {
      return data.size;
    },
  };
  Object.defineProperty(globalThis, "sessionStorage", {
    configurable: true,
    value: storage,
  });
  return data;
}

describe("isKioskConfirmToken", () => {
  test("requires base64url of at least 20 characters", () => {
    expect(isKioskConfirmToken(undefined)).toBe(false);
    expect(isKioskConfirmToken(null)).toBe(false);
    expect(isKioskConfirmToken("")).toBe(false);
    expect(isKioskConfirmToken("a".repeat(19))).toBe(false);
    expect(isKioskConfirmToken(`${TOKEN}=`)).toBe(false);
    expect(isKioskConfirmToken(`${TOKEN}+`)).toBe(false);
    expect(isKioskConfirmToken(`${TOKEN}/`)).toBe(false);
    expect(isKioskConfirmToken(` ${TOKEN}`)).toBe(false);
    expect(isKioskConfirmToken(TOKEN)).toBe(true);
    expect(isKioskConfirmToken(`${TOKEN}_-ZZ`)).toBe(true);
  });
});

describe("kiosk confirm return path", () => {
  test("accepts only the confirm path with a valid token", () => {
    const path = kioskConfirmReturnPath(TOKEN);
    expect(path).toBe(`/kiosk/confirm?token=${TOKEN}`);
    expect(tokenFromKioskConfirmReturn(path!)).toBe(TOKEN);
    expect(kioskConfirmReturnPath("short")).toBeNull();
    expect(tokenFromKioskConfirmReturn("/")).toBeNull();
    expect(tokenFromKioskConfirmReturn(`/kiosk/confirm?token=${TOKEN}&next=/`)).toBeNull();
    expect(
      tokenFromKioskConfirmReturn(
        `https://gymperf-member-web.example/${`kiosk/confirm?token=${TOKEN}`}`,
      ),
    ).toBeNull();
  });

  test("stashes that path and clears it on read, dropping anything else", () => {
    const data = installSessionStorage();
    stashKioskConfirmReturn("nope");
    expect(data.size).toBe(0);

    stashKioskConfirmReturn(TOKEN);
    expect(data.get("gp.kioskConfirmReturn")).toBe(`/kiosk/confirm?token=${TOKEN}`);
    expect(takeKioskConfirmReturn()).toBe(`/kiosk/confirm?token=${TOKEN}`);
    expect(takeKioskConfirmReturn()).toBeNull();

    data.set("gp.kioskConfirmReturn", "/log");
    expect(takeKioskConfirmReturn()).toBeNull();
    expect(data.has("gp.kioskConfirmReturn")).toBe(false);

    data.set("gp.kioskConfirmReturn", `https://evil.example/kiosk/confirm?token=${TOKEN}`);
    expect(takeKioskConfirmReturn()).toBeNull();
  });
});

describe("sha256Hex", () => {
  test("hashes utf-8 to lowercase hex", async () => {
    expect(await sha256Hex("abc")).toBe(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    );
  });
});

describe("commitKioskPending", () => {
  test("posts the digest with the member access token", async () => {
    let called = false;
    const result = await commitKioskPending({
      accessToken: "member-access",
      rawToken: TOKEN,
      supabaseUrl: `${SUPABASE_URL}/`,
      publishableKey: PUBLISHABLE,
      fetchImpl: async (input, init) => {
        called = true;
        expect(String(input)).toBe(`${SUPABASE_URL}/rest/v1/rpc/commit_kiosk_pending`);
        expect(init?.method).toBe("POST");
        const headers = new Headers(init?.headers);
        expect(headers.get("Authorization")).toBe("Bearer member-access");
        expect(headers.get("apikey")).toBe(PUBLISHABLE);
        expect(headers.get("Content-Type")).toBe("application/json");
        const body = JSON.parse(String(init?.body)) as { p_token_hash: string };
        expect(body.p_token_hash).toBe(await sha256Hex(TOKEN));
        expect(body.p_token_hash).not.toBe(TOKEN);
        expect(JSON.stringify(body)).not.toContain(TOKEN);
        return Response.json({
          sessionId: "session-1",
          memberId: "member-1",
          date: "2026-09-24",
        });
      },
    });

    expect(called).toBe(true);
    expect(result).toEqual({
      sessionId: "session-1",
      memberId: "member-1",
      date: "2026-09-24",
    });
  });

  test("does not call PostgREST without a member access token", async () => {
    await expect(
      commitKioskPending({
        accessToken: "",
        rawToken: TOKEN,
        supabaseUrl: SUPABASE_URL,
        publishableKey: PUBLISHABLE,
        fetchImpl: async () => {
          throw new Error("should not fetch");
        },
      }),
    ).rejects.toThrow("Sign in on the member app to confirm this session.");
  });

  test("surfaces the server message", async () => {
    await expect(
      commitKioskPending({
        accessToken: "member-access",
        rawToken: TOKEN,
        supabaseUrl: SUPABASE_URL,
        publishableKey: PUBLISHABLE,
        fetchImpl: async () =>
          Response.json(
            {
              code: "PT403",
              message: "Sign in on the member app to confirm this session",
            },
            { status: 403 },
          ),
      }),
    ).rejects.toThrow("Sign in on the member app to confirm this session");

    await expect(
      commitKioskPending({
        accessToken: "member-access",
        rawToken: TOKEN,
        supabaseUrl: SUPABASE_URL,
        publishableKey: PUBLISHABLE,
        fetchImpl: async () =>
          Response.json({ code: "PT404", message: "Pending log not found" }, { status: 404 }),
      }),
    ).rejects.toThrow("Pending log not found");
  });

  test("rejects a token that is not base64url", async () => {
    await expect(
      commitKioskPending({
        accessToken: "member-access",
        rawToken: "short",
        supabaseUrl: SUPABASE_URL,
        publishableKey: PUBLISHABLE,
        fetchImpl: async () => {
          throw new Error("should not fetch");
        },
      }),
    ).rejects.toThrow(KIOSK_CONFIRM_INVALID_MESSAGE);
  });
});
