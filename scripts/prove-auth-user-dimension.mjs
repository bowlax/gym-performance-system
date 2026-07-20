#!/usr/bin/env node
/**
 * Phase C / #17 — prove Auth-user dimension (create-or-find + session + refresh).
 *
 * Simulates the broker Auth path against a synthetic TeamUp customer ID.
 * Does NOT set TEAMUP_OAUTH_* env vars. Does NOT call the Edge Function Auth path.
 *
 * Also confirms the live stub POST still returns { token } HS256 when OAuth
 * is unconfigured on the project.
 *
 * Usage:
 *   node scripts/prove-auth-user-dimension.mjs
 *
 * Precondition: Custom Access Token Hook ENABLED in the dashboard
 * (Authentication → Hooks → Custom Access Token → public.custom_access_token_hook).
 */

import { createClient } from "@supabase/supabase-js";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRemoteJWKSet, jwtVerify, decodeJwt } from "jose";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const STATE_PATH = join(__dirname, ".auth-user-dimension-proof.json");

const WOLF_GYM_ID = "0abc9301-b048-40f5-8bdc-9bb389916b59";
const SYNTHETIC_CUSTOMER_ID = "PHASE-C-CUSTOMER-001";
const MEMBER_ID = "c3333333-3333-4333-8333-333333333333";
const APP_ROLE = "member";

function syntheticAuthEmail(customerId) {
  const local = String(customerId).replace(/[^a-zA-Z0-9_-]/g, "_");
  return `teamup-${local}@auth.gymperf.local`;
}

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
  const serviceRole = sb.SERVICE_ROLE_KEY;
  const anon = web.GYMPERF_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !serviceRole || !anon) {
    throw new Error("Missing URL / SERVICE_ROLE_KEY / publishable key");
  }
  return { url, serviceRole, anon };
}

function adminClient() {
  const { url, serviceRole } = env();
  return createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function anonClient() {
  const { url, anon } = env();
  return createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function claimSummary(claims) {
  return {
    sub: claims.sub,
    role: claims.role,
    alg_hint: claims.alg,
    member_id: claims.member_id ?? null,
    gym_id: claims.gym_id ?? null,
    app_role: claims.app_role ?? null,
    app_metadata: claims.app_metadata ?? null,
  };
}

async function ensureMember(admin) {
  const email = syntheticAuthEmail(SYNTHETIC_CUSTOMER_ID);
  const app_metadata = {
    member_id: MEMBER_ID,
    gym_id: WOLF_GYM_ID,
    app_role: APP_ROLE,
  };

  const { error: upsertErr } = await admin.from("members").upsert(
    {
      id: MEMBER_ID,
      gym_id: WOLF_GYM_ID,
      teamup_customer_id: SYNTHETIC_CUSTOMER_ID,
      display_name: "Phase C Auth-user Proof",
    },
    { onConflict: "id" },
  );
  if (upsertErr) throw upsertErr;

  const { data: row, error: readErr } = await admin
    .from("members")
    .select("id, auth_user_id")
    .eq("id", MEMBER_ID)
    .single();
  if (readErr) throw readErr;

  let user;
  if (row.auth_user_id) {
    const got = await admin.auth.admin.getUserById(row.auth_user_id);
    if (got.error) throw got.error;
    user = got.data.user;
    const updated = await admin.auth.admin.updateUserById(user.id, { app_metadata });
    if (updated.error) throw updated.error;
    user = updated.data.user;
    console.log("Reused Auth user via members.auth_user_id");
  } else {
    const created = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
      app_metadata,
    });
    if (created.error) {
      // Race / prior run: adopt by generateLink
      if (!/already|registered|exists/i.test(created.error.message ?? "")) {
        throw created.error;
      }
      const link = await admin.auth.admin.generateLink({ type: "magiclink", email });
      if (link.error) throw link.error;
      user = link.data.user;
      const updated = await admin.auth.admin.updateUserById(user.id, { app_metadata });
      if (updated.error) throw updated.error;
      user = updated.data.user;
      console.log("Adopted existing Auth user by email after create conflict");
    } else {
      user = created.data.user;
      console.log("Created Auth user");
    }

    const { error: linkErr } = await admin
      .from("members")
      .update({ auth_user_id: user.id })
      .eq("id", MEMBER_ID);
    if (linkErr) throw linkErr;
  }

  return { user, email, app_metadata };
}

async function establishSession(admin, anon, email) {
  const link = await admin.auth.admin.generateLink({ type: "magiclink", email });
  if (link.error) throw link.error;
  const tokenHash = link.data.properties?.hashed_token;
  if (!tokenHash) throw new Error("missing hashed_token");

  const verified = await anon.auth.verifyOtp({ type: "email", token_hash: tokenHash });
  if (verified.error) throw verified.error;
  const session = verified.data.session;
  if (!session?.access_token || !session.refresh_token) {
    throw new Error("verifyOtp returned incomplete session");
  }
  return session;
}

function assertHookedClaims(claims, label) {
  console.log(`\n[${label}]`, JSON.stringify(claimSummary(claims), null, 2));
  const ok =
    claims.member_id === MEMBER_ID &&
    claims.gym_id === WOLF_GYM_ID &&
    claims.app_role === APP_ROLE &&
    claims.role === "authenticated";
  if (!ok) {
    console.error(
      `\nFAIL [${label}]: expected top-level member_id/gym_id/app_role. Is the Custom Access Token Hook ENABLED?`,
    );
    process.exitCode = 1;
    return false;
  }
  console.log(`PASS [${label}]: top-level claims present; role=authenticated`);
  return true;
}

async function proveAuthPath() {
  const admin = adminClient();
  const anon = anonClient();
  const { user, email } = await ensureMember(admin);

  const session = await establishSession(admin, anon, email);
  const claims = decodeJwt(session.access_token);

  // Confirm ES256 from live JWKS when possible
  try {
    const { url } = env();
    const jwks = createRemoteJWKSet(new URL(`${url}/auth/v1/.well-known/jwks.json`));
    await jwtVerify(session.access_token, jwks);
    console.log("PASS: access_token verifies against project JWKS (ES256)");
  } catch (err) {
    console.warn("WARN: JWKS verify failed:", err.message);
  }

  if (!assertHookedClaims(claims, "after-issue")) {
    return false;
  }
  if (!session.refresh_token) {
    console.error("FAIL: refresh_token missing");
    process.exitCode = 1;
    return false;
  }
  console.log("PASS: refresh_token present");

  const refreshed = await anon.auth.refreshSession({
    refresh_token: session.refresh_token,
  });
  if (refreshed.error) throw refreshed.error;
  const refreshedClaims = decodeJwt(refreshed.data.session.access_token);
  if (!assertHookedClaims(refreshedClaims, "after-refresh")) {
    console.error("STOP: refresh dropped top-level claims");
    process.exitCode = 1;
    return false;
  }

  const state = {
    authUserId: user.id,
    email,
    memberId: MEMBER_ID,
    teamupCustomerId: SYNTHETIC_CUSTOMER_ID,
    gymId: WOLF_GYM_ID,
    provedAt: new Date().toISOString(),
  };
  writeFileSync(STATE_PATH, JSON.stringify(state, null, 2) + "\n");
  console.log(`\nAuth user id: ${user.id}`);
  console.log(`State: ${STATE_PATH}`);
  return true;
}

async function proveStubUnchanged() {
  const { url, anon } = env();
  const brokerUrl = `${url}/functions/v1/token-broker`;
  const res = await fetch(brokerUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${anon}`,
      apikey: anon,
    },
    body: JSON.stringify({
      teamupToken: "stub-token",
      deviceMemberId: "aaaaaaaa-0000-0000-0000-000000000099",
      surface: "memberWeb",
    }),
  });
  const body = await res.json();
  console.log(`\n[stub POST] status=${res.status}`);
  console.log(JSON.stringify({
    keys: Object.keys(body),
    has_token: typeof body.token === "string",
    has_access_token: body.access_token != null,
    has_refresh_token: body.refresh_token != null,
  }));

  if (!res.ok || typeof body.token !== "string") {
    console.error("FAIL: stub POST did not return { token }");
    process.exitCode = 1;
    return;
  }
  if (body.access_token != null || body.refresh_token != null) {
    console.error("FAIL: stub POST unexpectedly returned Auth session fields");
    process.exitCode = 1;
    return;
  }

  const header = JSON.parse(
    Buffer.from(body.token.split(".")[0], "base64url").toString("utf8"),
  );
  if (header.alg !== "HS256") {
    console.error(`FAIL: stub token alg is ${header.alg}, expected HS256`);
    process.exitCode = 1;
    return;
  }
  const claims = decodeJwt(body.token);
  if (claims.member_id == null || claims.app_role == null) {
    console.error("FAIL: stub HS256 token missing hand-minted claims");
    process.exitCode = 1;
    return;
  }
  console.log("PASS: stub path returns { token } HS256 with hand-minted claims (OAuth unconfigured)");
}

console.log("=== Phase C Auth-user dimension proof ===\n");
let authOk = false;
try {
  authOk = (await proveAuthPath()) === true;
} catch (err) {
  console.error("Auth path error:", err);
  process.exitCode = 1;
}
await proveStubUnchanged();
if (!authOk) {
  console.log(
    "\nAuth-path claims check needs the Custom Access Token Hook ENABLED:",
  );
  console.log(
    "  Dashboard → Authentication → Hooks → Custom Access Token → public.custom_access_token_hook",
  );
  console.log("Then re-run: node scripts/prove-auth-user-dimension.mjs");
}
console.log("\n=== done ===");
if (process.exitCode === 1) process.exit(1);
