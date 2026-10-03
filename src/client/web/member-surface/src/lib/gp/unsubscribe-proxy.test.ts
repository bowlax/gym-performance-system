import { describe, expect, test } from "bun:test";
import {
  proxyUnsubscribe,
  unsubscribeResponseContentType,
  unsubscribeUpstreamUrl,
} from "./unsubscribe-proxy";

describe("unsubscribeUpstreamUrl", () => {
  test("targets the log-reminders unsubscribe function with the token", () => {
    expect(
      unsubscribeUpstreamUrl("abc+1", "https://proj.supabase.co"),
    ).toBe(
      "https://proj.supabase.co/functions/v1/log-reminders/unsubscribe?token=abc%2B1",
    );
  });
});

describe("unsubscribeResponseContentType", () => {
  test("forces text/html for GET even when Supabase rewrote upstream to text/plain", () => {
    expect(
      unsubscribeResponseContentType("GET", "text/plain; charset=UTF-8"),
    ).toBe("text/html; charset=utf-8");
  });

  test("forces text/html for HEAD the same way as GET", () => {
    expect(
      unsubscribeResponseContentType("HEAD", "text/plain; charset=UTF-8"),
    ).toBe("text/html; charset=utf-8");
  });

  test("keeps upstream JSON Content-Type for one-click POST", () => {
    expect(
      unsubscribeResponseContentType("POST", "application/json"),
    ).toBe("application/json");
  });
});

describe("proxyUnsubscribe", () => {
  const supabaseUrl = "https://proj.supabase.co";
  const supabasePublishableKey = "anon-key";

  test("GET landing response is HTML even if upstream Content-Type is text/plain", async () => {
    const html =
      "<!DOCTYPE html><html lang=\"en\"><body><p>You are unsubscribed from session reminder emails. You can turn them back on in Settings.</p></body></html>";
    let upstreamUrl = "";

    const response = await proxyUnsubscribe(
      new Request("https://member.test/reminders/unsubscribe?token=tok", {
        method: "GET",
      }),
      {
        supabaseUrl,
        supabasePublishableKey,
        fetchImpl: async (input, init) => {
          upstreamUrl = String(input);
          expect(init?.method).toBe("GET");
          expect((init?.headers as Record<string, string>).apikey).toBe(
            supabasePublishableKey,
          );
          return new Response(html, {
            status: 200,
            headers: { "Content-Type": "text/plain; charset=UTF-8" },
          });
        },
      },
    );

    expect(upstreamUrl).toBe(
      "https://proj.supabase.co/functions/v1/log-reminders/unsubscribe?token=tok",
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toBe(
      "text/html; charset=utf-8",
    );
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(await response.text()).toBe(html);
  });

  test("POST one-click keeps JSON Content-Type from upstream", async () => {
    const response = await proxyUnsubscribe(
      new Request("https://member.test/reminders/unsubscribe?token=tok", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "List-Unsubscribe=One-Click",
      }),
      {
        supabaseUrl,
        supabasePublishableKey,
        fetchImpl: async () =>
          new Response(JSON.stringify({ ok: true }), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
      },
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toBe("application/json");
    expect(await response.json()).toEqual({ ok: true });
  });
});
