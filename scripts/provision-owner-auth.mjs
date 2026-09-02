#!/usr/bin/env node
/**
 * One-time owner Auth provisioning — no TeamUp, no broker.
 *
 * Creates (or updates) two dedicated Supabase Auth users with
 * app_metadata { member_id, gym_id, app_role: "owner" }, then
 * generateLink + verifyOtp SERVER-SIDE to obtain sessions.
 *
 * Ground truth (do not skip):
 * - owner_surface_grants only reads JWT claims gym_id + app_role.
 * - The Edge wrapper also requires top-level member_id + gym_id UUIDs.
 *   Auth JWTs get those via custom_access_token_hook from app_metadata,
 *   so all three fields must be set here — not app_role alone.
 * - member_id values are dedicated UUIDs. They are NOT inserted into
 *   public.members (that would show Lee/Steve on gym-wide owner lists).
 *
 * Usage:
 *   OWNER_LEE_EMAIL=... OWNER_STEVE_EMAIL=... node scripts/provision-owner-auth.mjs
 *
 * Reads supabase/.env.local and member-surface .env.local (same as other
 * prove scripts). Writes scripts/.owner-auth.json (gitignored).
 * Prints no access/refresh tokens.
 */

import { createClient } from "@supabase/supabase-js";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const STATE_PATH = join(__dirname, ".owner-auth.json");

const WOLF_GYM_ID = "0abc9301-b048-40f5-8bdc-9bb389916b59";
const LEE_MEMBER_ID = "e1111111-1111-4111-8111-111111111111";
const STEVE_MEMBER_ID = "e2222222-2222-4222-8222-222222222222";

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
    throw new Error(
      "Missing GYMPERF_SUPABASE_URL / SERVICE_ROLE_KEY / GYMPERF_SUPABASE_PUBLISHABLE_KEY",
    );
  }
  return { url, serviceRole, anon };
}

function decodeJwt(token) {
  const [, payload] = token.split(".");
  const json = Buffer.from(
    payload.replace(/-/g, "+").replace(/_/g, "/"),
    "base64",
  ).toString("utf8");
  return JSON.parse(json);
}

function claimSummary(claims) {
  return {
    app_role: claims.app_role ?? null,
    gym_id: claims.gym_id ?? null,
    member_id: claims.member_id ?? null,
    role: claims.role ?? null,
    has_app_metadata_app_role: Boolean(claims.app_metadata?.app_role),
  };
}

async function findUserByEmail(admin, email) {
  const { data, error } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  if (error) throw error;
  return data.user ?? null;
}

async function upsertOwnerUser(admin, { email, memberId, gymId }) {
  const expectedMeta = {
    member_id: memberId,
    gym_id: gymId,
    app_role: "owner",
  };

  let user = await findUserByEmail(admin, email);
  if (!user) {
    const created = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
      app_metadata: expectedMeta,
    });
    if (created.error) throw created.error;
    user = created.data.user;
  } else {
    const meta = user.app_metadata ?? {};
    if (
      meta.member_id !== expectedMeta.member_id ||
      meta.gym_id !== expectedMeta.gym_id ||
      meta.app_role !== expectedMeta.app_role
    ) {
      const updated = await admin.auth.admin.updateUserById(user.id, {
        app_metadata: expectedMeta,
      });
      if (updated.error) throw updated.error;
      user = updated.data.user;
    }
  }

  if (!user) throw new Error(`Auth user missing after upsert for ${email}`);
  return user;
}

async function establishSession(admin, anon, email) {
  const link = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  if (link.error) throw link.error;
  const tokenHash = link.data.properties?.hashed_token;
  if (!tokenHash) throw new Error("generateLink did not return hashed_token");

  const verified = await anon.auth.verifyOtp({
    type: "email",
    token_hash: tokenHash,
  });
  if (verified.error) throw verified.error;
  const session = verified.data.session;
  if (!session?.access_token || !session.refresh_token) {
    throw new Error("verifyOtp returned no session tokens");
  }
  return {
    accessToken: session.access_token,
    refreshToken: session.refresh_token,
    expiresAt:
      session.expires_at ??
      Math.floor(Date.now() / 1000) + (session.expires_in ?? 3600),
  };
}

function assertOwnerClaims(accessToken, expected) {
  const claims = decodeJwt(accessToken);
  const summary = claimSummary(claims);
  const problems = [];
  if (summary.app_role !== "owner") {
    problems.push(`app_role is ${JSON.stringify(summary.app_role)} (hook off?)`);
  }
  if (summary.gym_id !== expected.gymId) {
    problems.push(`gym_id is ${JSON.stringify(summary.gym_id)}`);
  }
  if (summary.member_id !== expected.memberId) {
    problems.push(`member_id is ${JSON.stringify(summary.member_id)}`);
  }
  if (summary.role !== "authenticated") {
    problems.push(`role is ${JSON.stringify(summary.role)}`);
  }
  if (problems.length > 0) {
    throw new Error(
      `JWT claims not owner-ready: ${problems.join("; ")}. ` +
        `Custom Access Token Hook must be enabled.`,
    );
  }
  return summary;
}

async function confirmGrant(url, anon, accessToken) {
  const res = await fetch(`${url.replace(/\/$/, "")}/rest/v1/owner_surface_grants?select=gym_id`, {
    headers: {
      apikey: anon,
      Authorization: `Bearer ${accessToken}`,
      Accept: "application/json",
    },
  });
  const body = await res.json();
  if (!res.ok) {
    throw new Error(`owner_surface_grants HTTP ${res.status}`);
  }
  if (!Array.isArray(body) || body.length !== 1) {
    throw new Error(
      `owner_surface_grants returned ${Array.isArray(body) ? body.length : "non-array"} rows`,
    );
  }
  return body[0].gym_id;
}

async function main() {
  const leeEmail = process.env.OWNER_LEE_EMAIL?.trim();
  const steveEmail = process.env.OWNER_STEVE_EMAIL?.trim();
  if (!leeEmail || !steveEmail) {
    throw new Error("Set OWNER_LEE_EMAIL and OWNER_STEVE_EMAIL");
  }

  const { url, serviceRole, anon } = env();
  const admin = createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const anonClient = createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const people = [
    { label: "lee", email: leeEmail, memberId: LEE_MEMBER_ID, gymId: WOLF_GYM_ID },
    { label: "steve", email: steveEmail, memberId: STEVE_MEMBER_ID, gymId: WOLF_GYM_ID },
  ];

  const state = {
    gymId: WOLF_GYM_ID,
    createdAt: new Date().toISOString(),
    users: {},
  };

  for (const person of people) {
    const user = await upsertOwnerUser(admin, person);
    const session = await establishSession(admin, anonClient, person.email);
    const claims = assertOwnerClaims(session.accessToken, person);
    const grantGymId = await confirmGrant(url, anon, session.accessToken);
    if (grantGymId !== WOLF_GYM_ID) {
      throw new Error(`grant gym_id mismatch: ${grantGymId}`);
    }

    state.users[person.label] = {
      authUserId: user.id,
      email: person.email,
      memberId: person.memberId,
      gymId: person.gymId,
      expiresAt: session.expiresAt,
      refreshToken: session.refreshToken,
      claims,
    };

    console.log(
      `${person.label}: auth user ${user.id} — JWT app_role=owner, grant row present`,
    );
  }

  writeFileSync(STATE_PATH, `${JSON.stringify(state, null, 2)}\n`);
  console.log(`Wrote ${STATE_PATH} (gitignored). Tokens are in that file only.`);
  console.log(
    "Next: seal Lee's session into OWNER_SESSION KV (see src/client/web/owner-api/README.md).",
  );
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : "provision failed");
  process.exit(1);
});
