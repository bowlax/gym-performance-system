#!/usr/bin/env node
/**
 * Phase A / #17 — prove Custom Access Token Hook against a synthetic Auth user.
 *
 * Usage:
 *   node scripts/prove-custom-access-token-hook.mjs create
 *   node scripts/prove-custom-access-token-hook.mjs session [--label baseline|after-hook|after-disable]
 *   node scripts/prove-custom-access-token-hook.mjs rls
 *   node scripts/prove-custom-access-token-hook.mjs refresh
 *
 * Reads:
 *   supabase/.env.local  (SERVICE_ROLE_KEY)
 *   src/client/web/member-surface/.env.local  (GYMPERF_SUPABASE_URL, GYMPERF_SUPABASE_PUBLISHABLE_KEY)
 *
 * State file: scripts/.synthetic-auth-user.json (gitignored via scripts/.gitignore if present)
 */

import { createClient } from "@supabase/supabase-js";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const STATE_PATH = join(__dirname, ".synthetic-auth-user.json");

const WOLF_GYM_ID = "0abc9301-b048-40f5-8bdc-9bb389916b59";
// Disposable test member — not necessarily a real members row for create/session;
// RLS proof creates/adopts a matching members + sessions row under service role.
const TEST_MEMBER_ID = "a1111111-1111-4111-8111-111111111111";
const APP_ROLE = "member";
const SYNTHETIC_EMAIL = "phase-a-hook-proof@gymperf.synthetic";

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
    throw new Error("Missing GYMPERF_SUPABASE_URL / SERVICE_ROLE_KEY / GYMPERF_SUPABASE_PUBLISHABLE_KEY");
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

function decodeJwt(token) {
  const [, payload] = token.split(".");
  const json = Buffer.from(payload.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8");
  return JSON.parse(json);
}

function claimSummary(claims) {
  return {
    sub: claims.sub,
    role: claims.role,
    aud: claims.aud,
    exp: claims.exp,
    iat: claims.iat,
    iss: claims.iss,
    aal: claims.aal,
    session_id: claims.session_id,
    email: claims.email,
    phone: claims.phone,
    is_anonymous: claims.is_anonymous,
    member_id: claims.member_id ?? null,
    gym_id: claims.gym_id ?? null,
    app_role: claims.app_role ?? null,
    app_metadata: claims.app_metadata ?? null,
  };
}

function assertBaseline(claims, label) {
  const topLevelPresent =
    claims.member_id != null || claims.gym_id != null || claims.app_role != null;
  const meta = claims.app_metadata || {};
  console.log(`\n[${label}] claim summary:`);
  console.log(JSON.stringify(claimSummary(claims), null, 2));
  if (topLevelPresent) {
    console.error(`\nFAIL [${label}]: expected NO top-level member_id/gym_id/app_role (hook should be off).`);
    process.exitCode = 1;
    return false;
  }
  if (meta.member_id !== TEST_MEMBER_ID || meta.gym_id !== WOLF_GYM_ID || meta.app_role !== APP_ROLE) {
    console.error(`\nFAIL [${label}]: app_metadata missing expected values.`);
    process.exitCode = 1;
    return false;
  }
  if (claims.role !== "authenticated") {
    console.error(`\nFAIL [${label}]: role is ${claims.role}, expected authenticated.`);
    process.exitCode = 1;
    return false;
  }
  console.log(`\nPASS [${label}]: top-level custom claims ABSENT; app_metadata present; role=authenticated.`);
  return true;
}

function assertHooked(claims, label) {
  console.log(`\n[${label}] claim summary:`);
  console.log(JSON.stringify(claimSummary(claims), null, 2));
  const ok =
    claims.member_id === TEST_MEMBER_ID &&
    claims.gym_id === WOLF_GYM_ID &&
    claims.app_role === APP_ROLE &&
    claims.role === "authenticated" &&
    !!claims.sub &&
    !!claims.exp &&
    !!claims.aud;
  if (!ok) {
    console.error(`\nFAIL [${label}]: expected top-level member_id/gym_id/app_role + role=authenticated + base claims.`);
    process.exitCode = 1;
    return false;
  }
  console.log(`\nPASS [${label}]: top-level claims present; role=authenticated; base claims survived.`);
  return true;
}

function loadState() {
  if (!existsSync(STATE_PATH)) {
    throw new Error(`No state at ${STATE_PATH}. Run: node scripts/prove-custom-access-token-hook.mjs create`);
  }
  return JSON.parse(readFileSync(STATE_PATH, "utf8"));
}

function saveState(state) {
  writeFileSync(STATE_PATH, JSON.stringify(state, null, 2) + "\n");
}

async function cmdCreate() {
  const admin = adminClient();
  const app_metadata = {
    member_id: TEST_MEMBER_ID,
    gym_id: WOLF_GYM_ID,
    app_role: APP_ROLE,
  };

  // Idempotent: reuse existing synthetic email if present
  const list = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (list.error) throw list.error;
  let user = (list.data.users || []).find((u) => u.email === SYNTHETIC_EMAIL);

  if (user) {
    const updated = await admin.auth.admin.updateUserById(user.id, {
      app_metadata,
      email_confirm: true,
    });
    if (updated.error) throw updated.error;
    user = updated.data.user;
    console.log("Reused existing synthetic user and refreshed app_metadata.");
  } else {
    const created = await admin.auth.admin.createUser({
      email: SYNTHETIC_EMAIL,
      email_confirm: true,
      app_metadata,
    });
    if (created.error) throw created.error;
    user = created.data.user;
    console.log("Created synthetic Auth user.");
  }

  // Ensure members row exists for RLS proof (service role)
  const { error: memberErr } = await admin.from("members").upsert(
    {
      id: TEST_MEMBER_ID,
      gym_id: WOLF_GYM_ID,
      teamup_customer_id: "SYNTHETIC-HOOK-PROOF",
      display_name: "Phase A Hook Proof",
    },
    { onConflict: "id" },
  );
  if (memberErr) throw memberErr;

  // Seed one session owned by that member for RLS SELECT proof
  const sessionId = "b2222222-2222-4222-8222-222222222222";
  const { error: sessErr } = await admin.from("sessions").upsert(
    {
      id: sessionId,
      gym_id: WOLF_GYM_ID,
      member_id: TEST_MEMBER_ID,
      date: "2026-07-20",
      notes: "synthetic hook proof session",
    },
    { onConflict: "id" },
  );
  if (sessErr) throw sessErr;

  const state = {
    authUserId: user.id,
    email: SYNTHETIC_EMAIL,
    memberId: TEST_MEMBER_ID,
    gymId: WOLF_GYM_ID,
    appRole: APP_ROLE,
    proofSessionId: sessionId,
    createdAt: new Date().toISOString(),
  };
  saveState(state);
  console.log(JSON.stringify(state, null, 2));
  console.log(`\nAuth user id: ${user.id}`);
  console.log(`State written to ${STATE_PATH}`);
}

async function issueSession() {
  const state = loadState();
  const admin = adminClient();
  const anon = anonClient();

  const link = await admin.auth.admin.generateLink({
    type: "magiclink",
    email: state.email,
  });
  if (link.error) throw link.error;

  const props = link.data.properties || {};
  const tokenHash = props.hashed_token;
  if (!tokenHash) {
    throw new Error(
      `generateLink did not return hashed_token. Keys: ${Object.keys(props).join(", ")}`,
    );
  }

  const verified = await anon.auth.verifyOtp({
    type: "email",
    token_hash: tokenHash,
  });
  if (verified.error) throw verified.error;

  const session = verified.data.session;
  if (!session?.access_token) throw new Error("verifyOtp returned no access_token");

  return {
    state,
    accessToken: session.access_token,
    refreshToken: session.refresh_token,
    claims: decodeJwt(session.access_token),
    session,
  };
}

async function cmdSession(label = "session") {
  const { accessToken, refreshToken, claims, state } = await issueSession();
  const next = {
    ...state,
    lastLabel: label,
    lastAccessToken: accessToken,
    lastRefreshToken: refreshToken,
    lastIssuedAt: new Date().toISOString(),
  };
  saveState(next);

  if (label === "baseline" || label === "after-disable") {
    assertBaseline(claims, label);
  } else if (label === "after-hook" || label === "after-refresh") {
    assertHooked(claims, label);
  } else {
    console.log(`\n[${label}] claim summary:`);
    console.log(JSON.stringify(claimSummary(claims), null, 2));
  }
}

async function cmdRls() {
  const state = loadState();
  if (!state.lastAccessToken) {
    throw new Error("No lastAccessToken in state. Run session first.");
  }
  const { url, anon } = env();
  const res = await fetch(
    `${url}/rest/v1/sessions?select=id,member_id,gym_id,notes&member_id=eq.${state.memberId}`,
    {
      headers: {
        apikey: anon,
        Authorization: `Bearer ${state.lastAccessToken}`,
      },
    },
  );
  const body = await res.json();
  console.log(`RLS GET sessions status=${res.status}`);
  console.log(JSON.stringify(body, null, 2));

  if (!res.ok) {
    console.error("FAIL: PostgREST request failed.");
    process.exitCode = 1;
    return;
  }
  if (!Array.isArray(body) || body.length < 1) {
    console.error("FAIL: expected at least one session row for the synthetic member_id.");
    process.exitCode = 1;
    return;
  }
  const foreign = body.filter((r) => r.member_id !== state.memberId);
  if (foreign.length) {
    console.error("FAIL: RLS returned rows for another member_id.");
    process.exitCode = 1;
    return;
  }
  console.log("PASS: RLS scoped sessions to JWT member_id.");
}

async function cmdRefresh() {
  const state = loadState();
  if (!state.lastRefreshToken) {
    throw new Error("No lastRefreshToken. Run session --label after-hook first.");
  }
  const anon = anonClient();
  const refreshed = await anon.auth.refreshSession({
    refresh_token: state.lastRefreshToken,
  });
  if (refreshed.error) throw refreshed.error;
  const session = refreshed.data.session;
  if (!session?.access_token) throw new Error("refresh returned no access_token");

  const claims = decodeJwt(session.access_token);
  saveState({
    ...state,
    lastLabel: "after-refresh",
    lastAccessToken: session.access_token,
    lastRefreshToken: session.refresh_token,
    lastIssuedAt: new Date().toISOString(),
  });

  if (!assertHooked(claims, "after-refresh")) {
    console.error("\nSTOP: refresh did not re-inject top-level claims.");
    process.exit(1);
  }
}

function usage() {
  console.log(`Usage:
  node scripts/prove-custom-access-token-hook.mjs create
  node scripts/prove-custom-access-token-hook.mjs session --label baseline|after-hook|after-disable|after-refresh
  node scripts/prove-custom-access-token-hook.mjs rls
  node scripts/prove-custom-access-token-hook.mjs refresh`);
}

const [cmd, ...rest] = process.argv.slice(2);
let label = "session";
for (let i = 0; i < rest.length; i++) {
  if (rest[i] === "--label") label = rest[i + 1] || label;
}

try {
  if (cmd === "create") await cmdCreate();
  else if (cmd === "session") await cmdSession(label);
  else if (cmd === "rls") await cmdRls();
  else if (cmd === "refresh") await cmdRefresh();
  else usage();
} catch (err) {
  console.error(err);
  process.exit(1);
}
