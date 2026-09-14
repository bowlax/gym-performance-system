#!/usr/bin/env node
/**
 * Privileged cleanup for #17 synthetic Auth-user proof rows in Wolf gym.
 *
 * Does NOT use PostgREST service_role.delete() (no GRANT DELETE).
 * Table wipe: `npx supabase db query --linked`.
 * Auth users: GoTrue admin deleteUser (not a table GRANT).
 *
 * Usage:
 *   node scripts/cleanup-synthetic-auth-proof.mjs
 */
import { createClient } from "@supabase/supabase-js";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { runLinkedSql, WOLF_GYM_ID } from "./lib/run-linked-sql.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");

const HOOK_MEMBER_ID = "a1111111-1111-4111-8111-111111111111";
const PHASE_C_MEMBER_ID = "c3333333-3333-4333-8333-333333333333";
const HOOK_SESSION_ID = "b2222222-2222-4222-8222-222222222222";
const SYNTHETIC_EMAILS = [
  "phase-a-hook-proof@gymperf.synthetic",
  "teamup-PHASE-C-CUSTOMER-001@auth.gymperf.local",
];

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
  if (!url || !serviceRole) {
    throw new Error("Missing GYMPERF_SUPABASE_URL / SERVICE_ROLE_KEY");
  }
  return { url, serviceRole };
}

const sql = `begin;
delete from sets
where gym_id = '${WOLF_GYM_ID}'::uuid
  and exercise_entry_id in (
    select ee.id
    from exercise_entries ee
    join sessions s on s.id = ee.session_id
    where s.gym_id = '${WOLF_GYM_ID}'::uuid
      and (
        s.id = '${HOOK_SESSION_ID}'::uuid
        or s.member_id in ('${HOOK_MEMBER_ID}'::uuid, '${PHASE_C_MEMBER_ID}'::uuid)
      )
  );
delete from exercise_entries
where gym_id = '${WOLF_GYM_ID}'::uuid
  and session_id in (
    select id from sessions
    where gym_id = '${WOLF_GYM_ID}'::uuid
      and (
        id = '${HOOK_SESSION_ID}'::uuid
        or member_id in ('${HOOK_MEMBER_ID}'::uuid, '${PHASE_C_MEMBER_ID}'::uuid)
      )
  );
delete from personal_bests
where gym_id = '${WOLF_GYM_ID}'::uuid
  and member_id in ('${HOOK_MEMBER_ID}'::uuid, '${PHASE_C_MEMBER_ID}'::uuid);
delete from exercise_resets
where gym_id = '${WOLF_GYM_ID}'::uuid
  and member_id in ('${HOOK_MEMBER_ID}'::uuid, '${PHASE_C_MEMBER_ID}'::uuid);
delete from sessions
where gym_id = '${WOLF_GYM_ID}'::uuid
  and (
    id = '${HOOK_SESSION_ID}'::uuid
    or member_id in ('${HOOK_MEMBER_ID}'::uuid, '${PHASE_C_MEMBER_ID}'::uuid)
  );
delete from members
where gym_id = '${WOLF_GYM_ID}'::uuid
  and id in ('${HOOK_MEMBER_ID}'::uuid, '${PHASE_C_MEMBER_ID}'::uuid)
  and teamup_customer_id in ('SYNTHETIC-HOOK-PROOF', 'PHASE-C-CUSTOMER-001');
commit;
`;

const { url, serviceRole } = env();
const admin = createClient(url, serviceRole, {
  auth: { persistSession: false, autoRefreshToken: false },
});

runLinkedSql(ROOT, sql, "wipe-wolf-synthetics");

const leftover = await admin
  .from("members")
  .select("id, teamup_customer_id")
  .in("id", [HOOK_MEMBER_ID, PHASE_C_MEMBER_ID]);
if (leftover.error) {
  throw new Error(`verify members: ${leftover.error.message}`);
}
if ((leftover.data ?? []).length > 0) {
  throw new Error(
    `linked SQL did not remove synthetic members: ${JSON.stringify(leftover.data)}`,
  );
}

const leftoverSession = await admin
  .from("sessions")
  .select("id")
  .eq("id", HOOK_SESSION_ID);
if (leftoverSession.error) {
  throw new Error(`verify session: ${leftoverSession.error.message}`);
}
if ((leftoverSession.data ?? []).length > 0) {
  throw new Error("linked SQL did not remove hook-proof session");
}

const list = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
if (list.error) throw list.error;
const emails = new Set(SYNTHETIC_EMAILS.map((e) => e.toLowerCase()));
for (const user of list.data.users || []) {
  if (!user.email || !emails.has(user.email.toLowerCase())) continue;
  const deleted = await admin.auth.admin.deleteUser(user.id);
  if (deleted.error) {
    throw new Error(`auth deleteUser ${user.email}: ${deleted.error.message}`);
  }
  console.log("deleted Auth user", user.email);
}

console.log("synthetic auth-proof rows wiped via linked SQL");
