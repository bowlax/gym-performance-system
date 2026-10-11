import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { LANDING_HTML, serveLandingPage } from "./landing-page";

const publicLandingHtml = readFileSync(
  join(
    dirname(fileURLToPath(import.meta.url)),
    "../../../public/landing/index.html",
  ),
  "utf8",
);

describe("serveLandingPage", () => {
  test("bundled HTML stays in sync with public/landing/index.html", () => {
    expect(LANDING_HTML).toBe(publicLandingHtml);
  });

  test("returns null for unrelated paths", () => {
    expect(serveLandingPage(new Request("https://example.com/"))).toBeNull();
    expect(
      serveLandingPage(new Request("https://example.com/privacy")),
    ).toBeNull();
  });

  test("serves the explanation HTML at /landing and /landing/", async () => {
    for (const path of ["/landing", "/landing/"]) {
      const response = serveLandingPage(
        new Request(`https://example.com${path}?utm=1`),
      );
      expect(response).not.toBeNull();
      expect(response!.status).toBe(200);
      expect(response!.headers.get("content-type")).toBe(
        "text/html; charset=utf-8",
      );
      const body = await response!.text();
      expect(body).toBe(LANDING_HTML);
      expect(body).toContain("GymPerformance - Way of Life Fitness");
      expect(body).toContain('src="/landing/app-icon.png"');
      expect(body).toContain("kiosk app running on the iPad in the gym");
    }
  });

  test("HEAD /landing/ returns headers without a body", async () => {
    const response = serveLandingPage(
      new Request("https://example.com/landing/", { method: "HEAD" }),
    );
    expect(response).not.toBeNull();
    expect(response!.status).toBe(200);
    expect(await response!.text()).toBe("");
  });

  test("ignores non-GET/HEAD methods", () => {
    expect(
      serveLandingPage(
        new Request("https://example.com/landing/", { method: "POST" }),
      ),
    ).toBeNull();
  });
});
