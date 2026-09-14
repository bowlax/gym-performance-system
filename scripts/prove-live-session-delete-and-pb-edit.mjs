#!/usr/bin/env node
/**
 * Live HTTP proof for delete-session + update-manual-pb against the hosted
 * project. Hits the deployed URLs (not in-process handlers). Uses a throwaway
 * gym so Wolf member data is never touched. Prints no tokens.
 *
 * Reads supabase/.env.local + member-surface .env.local.
 */
import { createClient } from "@supabase/supabase-js";
import { randomUUID } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { isolatedGymWipeSql, runLinkedSql } from "./lib/run-linked-sql.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");

function loadEnvFile(path) {
  if (!existsSync(path)) return {};
  const out = {};
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) continue;
    const i = trimmed.indexOf("=");
    out[trimmed.slice(0, i)] = trimmed.slice(i + 1).trim().replace(/^["']|["']$/g, "");
  }
  return out;
}

function env() {
  const sb = loadEnvFile(join(ROOT, "supabase/.env.local"));
  const web = loadEnvFile(join(ROOT, "src/client/web/member-surface/.env.local"));
  const url = (web.GYMPERF_SUPABASE_URL || sb.SUPABASE_URL || "").replace(/\/$/, "");
  const serviceRole = sb.SERVICE_ROLE_KEY;
  const anon = web.GYMPERF_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !serviceRole || !anon) {
    throw new Error("Missing GYMPERF_SUPABASE_URL / SERVICE_ROLE_KEY / GYMPERF_SUPABASE_PUBLISHABLE_KEY");
  }
  if (!url.includes("ivrsxhuktebvypgtfoww")) {
    throw new Error(`Refusing to run: URL is not the live project (${url})`);
  }
  return { url, serviceRole, anon };
}

function decodeJwt(token) {
  const [, payload] = token.split(".");
  return JSON.parse(
    Buffer.from(payload.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8"),
  );
}

function must(label, { error, data }) {
  if (error) throw new Error(`${label}: ${error.message}`);
  return data;
}

async function postFn(url, name, token, body) {
  const res = await fetch(`${url}/functions/v1/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = { raw: text.slice(0, 400) };
  }
  return { status: res.status, json };
}

async function establishSession(admin, anon, email) {
  const link = await admin.auth.admin.generateLink({ type: "magiclink", email });
  if (link.error) throw link.error;
  const tokenHash = link.data.properties?.hashed_token;
  if (!tokenHash) throw new Error("generateLink did not return hashed_token");
  const verified = await anon.auth.verifyOtp({ type: "email", token_hash: tokenHash });
  if (verified.error) throw verified.error;
  const session = verified.data.session;
  if (!session?.access_token) throw new Error("verifyOtp returned no access_token");
  return session.access_token;
}

async function createAuthUser(admin, { email, memberId, gymId, appRole }) {
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
    app_metadata: { member_id: memberId, gym_id: gymId, app_role: appRole },
  });
  if (created.error) throw created.error;
  return created.data.user;
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

async function main() {
  const { url, serviceRole, anon } = env();
  const admin = createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const anonClient = createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const stamp = Date.now().toString(36);
  const gymId = randomUUID();
  const memberId = randomUUID();
  const ownerId = randomUUID();
  const pressId = randomUUID();
  const squatId = randomUUID();
  const delSession = randomUUID();
  const keepSession = randomUUID();
  const delEntry = randomUUID();
  const keepEntry = randomUUID();
  const delSet = randomUUID();
  const keepSet = randomUUID();
  const squatSession = randomUUID();
  const squatEntry = randomUUID();
  const squatSet = randomUUID();
  const manualId = randomUUID();
  const memberEmail = `live-parity-member-${stamp}@gymperf.synthetic`;
  const ownerEmail = `live-parity-owner-${stamp}@gymperf.synthetic`;
  let memberUserId = null;
  let ownerUserId = null;

  console.log("live_url", url);
  console.log("isolated_gym", gymId);

  try {
    must(
      "gyms",
      await admin.from("gyms").insert({
        id: gymId,
        teamup_provider_id: `live-parity-${stamp}`,
        name: "Live Parity Proof Gym",
      }),
    );
    must(
      "members",
      await admin.from("members").insert([
        {
          id: memberId,
          gym_id: gymId,
          teamup_customer_id: `LIVE-PARITY-${stamp}`,
          display_name: "Live Parity Member",
        },
        {
          id: ownerId,
          gym_id: gymId,
          teamup_customer_id: `LIVE-PARITY-OWNER-${stamp}`,
          display_name: "Live Parity Owner",
        },
      ]),
    );
    must(
      "exercises",
      await admin.from("exercises").insert([
        {
          id: pressId,
          gym_id: gymId,
          name: "Live Parity Press",
          category: "pbExercise",
          measurement_type: "weightAndReps",
          pb_rule: "heaviestWeightAtReps",
          target_reps: 5,
          display_order: 1,
          is_active: true,
        },
        {
          id: squatId,
          gym_id: gymId,
          name: "Live Parity Squat",
          category: "pbExercise",
          measurement_type: "weightAndReps",
          pb_rule: "heaviestWeightAtReps",
          target_reps: 5,
          display_order: 2,
          is_active: true,
        },
      ]),
    );
    must(
      "sessions",
      await admin.from("sessions").insert([
        { id: delSession, gym_id: gymId, member_id: memberId, date: "2026-07-15" },
        { id: keepSession, gym_id: gymId, member_id: memberId, date: "2026-06-01" },
        { id: squatSession, gym_id: gymId, member_id: memberId, date: "2026-07-01" },
      ]),
    );
    must(
      "entries",
      await admin.from("exercise_entries").insert([
        { id: delEntry, gym_id: gymId, session_id: delSession, exercise_id: pressId },
        { id: keepEntry, gym_id: gymId, session_id: keepSession, exercise_id: pressId },
        { id: squatEntry, gym_id: gymId, session_id: squatSession, exercise_id: squatId },
      ]),
    );
    must(
      "sets",
      await admin.from("sets").insert([
        { id: delSet, gym_id: gymId, exercise_entry_id: delEntry, weight: 200, reps: 5 },
        { id: keepSet, gym_id: gymId, exercise_entry_id: keepEntry, weight: 80, reps: 5 },
        { id: squatSet, gym_id: gymId, exercise_entry_id: squatEntry, weight: 100, reps: 5 },
      ]),
    );
    must(
      "manual",
      await admin.from("personal_bests").insert({
        id: manualId,
        gym_id: gymId,
        member_id: memberId,
        exercise_id: squatId,
        set_id: null,
        weight: 80,
        reps: 5,
        achieved_at: "2026-06-01",
        entry_type: "manualEntry",
      }),
    );

    const memberUser = await createAuthUser(admin, {
      email: memberEmail,
      memberId,
      gymId,
      appRole: "member",
    });
    memberUserId = memberUser.id;
    const ownerUser = await createAuthUser(admin, {
      email: ownerEmail,
      memberId: ownerId,
      gymId,
      appRole: "owner",
    });
    ownerUserId = ownerUser.id;

    const memberToken = await establishSession(admin, anonClient, memberEmail);
    const ownerToken = await establishSession(admin, anonClient, ownerEmail);
    const memberClaims = decodeJwt(memberToken);
    const ownerClaims = decodeJwt(ownerToken);
    assert(memberClaims.member_id === memberId, `member JWT member_id=${memberClaims.member_id}`);
    assert(memberClaims.app_role === "member", `member JWT app_role=${memberClaims.app_role}`);
    assert(ownerClaims.app_role === "owner", `owner JWT app_role=${ownerClaims.app_role}`);
    assert(ownerClaims.gym_id === gymId, `owner JWT gym_id=${ownerClaims.gym_id}`);
    console.log("auth_ok", {
      member_role: memberClaims.app_role,
      owner_role: ownerClaims.app_role,
      alg_hint: memberToken.split(".").length === 3 ? "jwt" : "unexpected",
    });

    const beforeOwner = await postFn(url, "owner-current-pbs", ownerToken, {});
    assert(beforeOwner.status === 200, `owner-current-pbs before HTTP ${beforeOwner.status} ${JSON.stringify(beforeOwner.json)}`);
    const beforePress = (beforeOwner.json.currentPBs ?? []).find((r) => r.exercise_id === pressId);
    assert(beforePress?.value === 200, `before press current=${JSON.stringify(beforePress)}`);
    console.log("before_delete_press_current", beforePress.value);

    const foreign = await postFn(url, "delete-session", ownerToken, { sessionId: delSession });
    // owner JWT is a different member_id — should 404
    assert(foreign.status === 404, `foreign delete expected 404 got ${foreign.status} ${JSON.stringify(foreign.json)}`);

    const deleted = await postFn(url, "delete-session", memberToken, { sessionId: delSession });
    assert(deleted.status === 200, `delete-session HTTP ${deleted.status} ${JSON.stringify(deleted.json)}`);
    assert(deleted.json.deleted?.id === delSession, `delete body ${JSON.stringify(deleted.json)}`);
    console.log("delete_session_http", deleted.status);

    const sessionRow = must(
      "session row",
      await admin.from("sessions").select("deleted_at, updated_at").eq("id", delSession).single(),
    );
    const entryRow = must(
      "entry row",
      await admin.from("exercise_entries").select("deleted_at, updated_at").eq("id", delEntry).single(),
    );
    const setRow = must(
      "set row",
      await admin.from("sets").select("deleted_at, updated_at").eq("id", delSet).single(),
    );
    assert(sessionRow.deleted_at, "session not tombstoned");
    assert(entryRow.deleted_at, "entry not tombstoned");
    assert(setRow.deleted_at, "set not tombstoned");
    console.log("cascade_tombstones", {
      session: Boolean(sessionRow.deleted_at),
      entry: Boolean(entryRow.deleted_at),
      set: Boolean(setRow.deleted_at),
    });

    const memberClient = createClient(url, anon, {
      global: { headers: { Authorization: `Bearer ${memberToken}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const history = must(
      "history",
      await memberClient.from("sessions").select("id").is("deleted_at", null),
    );
    const historyIds = (history ?? []).map((r) => r.id);
    assert(!historyIds.includes(delSession), "deleted session still in live history filter");
    assert(historyIds.includes(keepSession), "kept session missing from history");

    const afterOwner = await postFn(url, "owner-current-pbs", ownerToken, {});
    assert(afterOwner.status === 200, `owner-current-pbs after HTTP ${afterOwner.status}`);
    const afterPress = (afterOwner.json.currentPBs ?? []).find((r) => r.exercise_id === pressId);
    assert(afterPress?.value === 80, `after press current=${JSON.stringify(afterPress)}`);
    console.log("after_delete_press_current", afterPress.value, afterPress.achieved_at);

    const freq = await postFn(url, "owner-pb-frequency", ownerToken, {
      from: "2026-07-01",
      to: "2026-07-31",
    });
    assert(freq.status === 200, `owner-pb-frequency HTTP ${freq.status} ${JSON.stringify(freq.json)}`);
    const pressHits = (freq.json.members ?? []).flatMap((m) => m.hits ?? []).filter(
      (h) => h.exercise_id === pressId,
    );
    assert(
      pressHits.every((h) => h.achieved_at !== "2026-07-15"),
      `frequency still has deleted session hit ${JSON.stringify(pressHits)}`,
    );
    console.log("frequency_july_press_hits", pressHits.map((h) => h.achieved_at));

    const weaker = await postFn(url, "update-manual-pb", memberToken, {
      exerciseId: squatId,
      personalBestId: manualId,
      weight: 90,
      reps: 5,
      time_seconds: null,
      distance: null,
      achievedAt: "2026-06-01",
    });
    assert(weaker.status === 200, `update weaker HTTP ${weaker.status} ${JSON.stringify(weaker.json)}`);
    assert(weaker.json.personalBest?.id === manualId, "id changed on weaker update");
    assert(weaker.json.personalBest?.weight === 90, "weaker weight not saved");

    const stillSquat = await postFn(url, "owner-current-pbs", ownerToken, {});
    const squatCurrent = (stillSquat.json.currentPBs ?? []).find((r) => r.exercise_id === squatId);
    assert(squatCurrent?.value === 100, `weaker edit should leave session current, got ${JSON.stringify(squatCurrent)}`);
    console.log("weaker_edit_keeps_session_current", squatCurrent.value);

    const undate = await postFn(url, "update-manual-pb", memberToken, {
      exerciseId: squatId,
      personalBestId: manualId,
      weight: 130,
      reps: 5,
      time_seconds: null,
      distance: null,
      achievedAt: null,
    });
    assert(undate.status === 200, `undate HTTP ${undate.status} ${JSON.stringify(undate.json)}`);
    assert(undate.json.personalBest?.id === manualId, "id changed on undate");
    assert(undate.json.personalBest?.achieved_at == null, "achieved_at not cleared");
    const afterUndate = await postFn(url, "owner-current-pbs", ownerToken, {});
    const squatAfterUndate = (afterUndate.json.currentPBs ?? []).find((r) => r.exercise_id === squatId);
    assert(squatAfterUndate?.value === 100, `undated 130 should not be current, got ${JSON.stringify(squatAfterUndate)}`);
    console.log("dated_to_undated_current_stays", squatAfterUndate.value);

    const redate = await postFn(url, "update-manual-pb", memberToken, {
      exerciseId: squatId,
      personalBestId: manualId,
      weight: 130,
      reps: 5,
      time_seconds: null,
      distance: null,
      achievedAt: "2026-08-15",
    });
    assert(redate.status === 200, `redate HTTP ${redate.status} ${JSON.stringify(redate.json)}`);
    assert(redate.json.personalBest?.id === manualId, "id changed on redate");
    assert(redate.json.personalBest?.achieved_at === "2026-08-15", "date not set");
    const afterRedate = await postFn(url, "owner-current-pbs", ownerToken, {});
    const squatAfterRedate = (afterRedate.json.currentPBs ?? []).find((r) => r.exercise_id === squatId);
    assert(squatAfterRedate?.value === 130, `redated 130 should be current, got ${JSON.stringify(squatAfterRedate)}`);
    console.log("undated_to_dated_becomes_current", squatAfterRedate.value, squatAfterRedate.achieved_at);

    const stored = must(
      "stored manual",
      await admin.from("personal_bests").select("id, weight, achieved_at, deleted_at").eq("id", manualId).single(),
    );
    assert(stored.id === manualId && stored.weight === 130 && stored.deleted_at == null, JSON.stringify(stored));
    console.log("PASS live delete-session cascade + update-manual-pb in-place edit");
  } finally {
    try {
      if (memberUserId) await admin.auth.admin.deleteUser(memberUserId);
      if (ownerUserId) await admin.auth.admin.deleteUser(ownerUserId);
    } catch (e) {
      console.error("auth cleanup warning", e instanceof Error ? e.message : e);
    }
    // service_role has no GRANT DELETE. Hard-wipe via linked SQL and verify
    // the gym is gone — a leftover must fail this proof, not print cleanup_done.
    runLinkedSql(ROOT, isolatedGymWipeSql(gymId), "wipe-live-parity-gym");
    const leftover = await admin.from("gyms").select("id").eq("id", gymId);
    if (leftover.error) {
      throw new Error(`cleanup verify gyms: ${leftover.error.message}`);
    }
    if ((leftover.data ?? []).length > 0) {
      throw new Error(
        `linked SQL did not remove isolated gym ${gymId}. ` +
          "Do not treat PostgREST .delete() as cleanup.",
      );
    }
    console.log("cleanup_done");
  }
}

main().catch((e) => {
  console.error("FAIL", e instanceof Error ? e.message : e);
  process.exit(1);
});
