#!/usr/bin/env node
/**
 * Live GoTrue refresh proof for the owner session store.
 * Same contract as iOS GoTrueTokenRefresher / member-web refreshGoTrueSession:
 * POST /auth/v1/token?grant_type=refresh_token, persist rotated refresh_token.
 *
 * Requires scripts/.owner-auth.json from provision-owner-auth.mjs.
 * Does not print tokens.
 *
 * Usage:
 *   node scripts/prove-owner-session-refresh.mjs
 */

import { decodeJwt } from "jose";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const STATE_PATH = join(__dirname, ".owner-auth.json");

function loadEnvFile(path) {
  if (!existsSync(path)) return {};
  const out = {};
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) continue;
    const i = trimmed.indexOf("=");
    out[trimmed.slice(0, i)] = trimmed.slice(i + 1).trim().replace(/^['"]|['"]$/g, "");
  }
  return out;
}

function env() {
  const sb = loadEnvFile(join(ROOT, "supabase/.env.local"));
  const web = loadEnvFile(join(ROOT, "src/client/web/member-surface/.env.local"));
  const url = web.GYMPERF_SUPABASE_URL || sb.SUPABASE_URL;
  const anon = web.GYMPERF_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !anon) {
    throw new Error("Missing GYMPERF_SUPABASE_URL / GYMPERF_SUPABASE_PUBLISHABLE_KEY");
  }
  return { url, anon };
}

async function refresh(url, anon, refreshToken) {
  const tokenUrl = new URL("auth/v1/token", url.endsWith("/") ? url : `${url}/`);
  tokenUrl.searchParams.set("grant_type", "refresh_token");
  const res = await fetch(tokenUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: anon,
      Authorization: `Bearer ${anon}`,
    },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  const json = await res.json();
  if (!res.ok) {
    throw new Error(`GoTrue refresh HTTP ${res.status}`);
  }
  if (typeof json.access_token !== "string" || typeof json.refresh_token !== "string") {
    throw new Error("Refresh response missing tokens");
  }
  return json;
}

async function assertClaims(_url, accessToken, expected) {
  const claims = decodeJwt(accessToken);
  if (claims.app_role !== "owner") {
    throw new Error("refreshed JWT missing top-level app_role=owner");
  }
  if (claims.gym_id !== expected.gymId) {
    throw new Error("refreshed JWT gym_id mismatch");
  }
  if (claims.member_id !== expected.memberId) {
    throw new Error("refreshed JWT member_id mismatch");
  }
}

async function main() {
  if (!existsSync(STATE_PATH)) {
    throw new Error("Run provision-owner-auth.mjs first");
  }
  const state = JSON.parse(readFileSync(STATE_PATH, "utf8"));
  const lee = state.users?.lee;
  if (!lee?.refreshToken) {
    throw new Error("Lee session missing from .owner-auth.json");
  }

  const { url, anon } = env();
  const oldRefresh = lee.refreshToken;
  const first = await refresh(url, anon, oldRefresh);
  if (first.refresh_token === oldRefresh) {
    throw new Error("GoTrue did not rotate refresh_token");
  }
  await assertClaims(url, first.access_token, lee);

  const second = await refresh(url, anon, first.refresh_token);
  await assertClaims(url, second.access_token, lee);

  await new Promise((resolve) => setTimeout(resolve, 21_000));
  const reuse = await fetch(
    new URL("auth/v1/token?grant_type=refresh_token", url.endsWith("/") ? url : `${url}/`),
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anon,
        Authorization: `Bearer ${anon}`,
      },
      body: JSON.stringify({ refresh_token: oldRefresh }),
    },
  );
  if (reuse.ok) {
    throw new Error("Expected old refresh_token to be rejected after rotation");
  }

  lee.refreshToken = second.refresh_token;
  lee.expiresAt = second.expires_at ?? lee.expiresAt;
  writeFileSync(STATE_PATH, `${JSON.stringify(state, null, 2)}\n`);
  console.log("Owner session refresh: rotated twice, claims still owner, parent rejected.");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : "refresh proof failed");
  process.exit(1);
});
