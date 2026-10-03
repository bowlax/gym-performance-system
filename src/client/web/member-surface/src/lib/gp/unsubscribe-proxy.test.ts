import { describe, expect, test } from "bun:test";
import {
  performUnsubscribe,
  proxyUnsubscribePost,
  unsubscribeMessageForResponse,
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

describe("unsubscribeMessageForResponse", () => {
  test("maps known statuses to member-facing copy", () => {
    expect(unsubscribeMessageForResponse(200, "")).toContain("unsubscribed");
    expect(unsubscribeMessageForResponse(400, "")).toContain("invalid");
    expect(unsubscribeMessageForResponse(503, "")).toContain("not configured");
  });

  test("falls back to the upstream HTML paragraph for other statuses", () => {
    expect(
      unsubscribeMessageForResponse(
        502,
        "<html><body><p>Upstream hiccup</p></body></html>",
      ),
    ).toBe("Upstream hiccup");
  });
});

describe("performUnsubscribe", () => {
  const supabaseUrl = "https://proj.supabase.co";
  const supabasePublishableKey = "anon-key";

  test("returns ok + confirmation copy when upstream succeeds", async () => {
    let upstreamUrl = "";
    const result = await performUnsubscribe("tok", {
      supabaseUrl,
      supabasePublishableKey,
      fetchImpl: async (input, init) => {
        upstreamUrl = String(input);
        expect(init?.method).toBe("GET");
        expect((init?.headers as Record<string, string>).apikey).toBe(
          supabasePublishableKey,
        );
        return new Response(
          "<!DOCTYPE html><html><body><p>You are unsubscribed</p></body></html>",
          {
            status: 200,
            headers: { "Content-Type": "text/plain; charset=UTF-8" },
          },
        );
      },
    });

    expect(upstreamUrl).toBe(
      "https://proj.supabase.co/functions/v1/log-reminders/unsubscribe?token=tok",
    );
    expect(result).toEqual({
      ok: true,
      status: 200,
      message:
        "You are unsubscribed from session reminder emails. You can turn them back on in Settings.",
    });
  });

  test("returns invalid-link copy for 400", async () => {
    const result = await performUnsubscribe("bad", {
      supabaseUrl,
      supabasePublishableKey,
      fetchImpl: async () =>
        new Response("<p>This unsubscribe link is invalid or has expired.</p>", {
          status: 400,
        }),
    });
    expect(result.ok).toBe(false);
    expect(result.status).toBe(400);
    expect(result.message).toContain("invalid");
  });
});

describe("proxyUnsubscribePost", () => {
  test("proxies one-click POST JSON without rewriting Content-Type", async () => {
    const response = await proxyUnsubscribePost(
      new Request("https://member.test/reminders/unsubscribe?token=tok", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "List-Unsubscribe=One-Click",
      }),
      {
        supabaseUrl: "https://proj.supabase.co",
        supabasePublishableKey: "anon",
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
