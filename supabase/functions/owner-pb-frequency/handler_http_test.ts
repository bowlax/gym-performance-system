/**
 * HTTP-level tests for owner-pb-frequency.
 *
 * Routing tests always hit handleOwnerPbFrequencyRequest (the served
 * function). RLS + period tests POST that handler with signed JWTs
 * against live PostgREST.
 */
import { assertEquals, assert } from "jsr:@std/assert@1";
import { SignJWT } from "jsr:@panva/jose@6";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  handleOwnerPbFrequencyRequest,
  resolveFrequencyWindow,
} from "./handler.ts";
import { badgeIds } from "../_shared/pb-derivation.ts";

const ENDPOINT = "http://localhost/functions/v1/owner-pb-frequency";

Deno.test("HTTP GET owner-pb-frequency returns 405 via the served handler", async () => {
  const res = await handleOwnerPbFrequencyRequest(
    new Request(ENDPOINT, { method: "GET" }),
  );
  assertEquals(res.status, 405);
});

Deno.test("HTTP POST owner-pb-frequency without Authorization returns 401", async () => {
  const res = await handleOwnerPbFrequencyRequest(
    new Request(ENDPOINT, { method: "POST" }),
  );
  assertEquals(res.status, 401);
});

Deno.test("HTTP OPTIONS owner-pb-frequency returns 200 via the served handler", async () => {
  const res = await handleOwnerPbFrequencyRequest(
    new Request(ENDPOINT, { method: "OPTIONS" }),
  );
  assertEquals(res.status, 200);
});

Deno.test("this_month window is the UTC calendar month containing today", () => {
  const resolved = resolveFrequencyWindow(
    { period: "this_month" },
    "2026-07-15",
  );
  assertEquals(resolved.ok, true);
  if (!resolved.ok) return;
  assertEquals(resolved.window, { from: "2026-07-01", to: "2026-07-31" });
});

Deno.test("this_week window is the ISO week (Mon–Sun) containing today", () => {
  const resolved = resolveFrequencyWindow(
    { period: "this_week" },
    "2026-07-15",
  );
  assertEquals(resolved.ok, true);
  if (!resolved.ok) return;
  assertEquals(resolved.window, { from: "2026-07-13", to: "2026-07-19" });
});

interface LiveEnv {
  url: string;
  anonKey: string;
  serviceRoleKey: string;
  jwtSecret: string;
}

function unquote(value: string): string {
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }
  return value;
}

function liveEnv(): LiveEnv | null {
  const url = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("API_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    Deno.env.get("PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const jwtSecret = Deno.env.get("JWT_SIGNING_SECRET") ??
    Deno.env.get("JWT_SECRET");
  if (!url || !anonKey || !serviceRoleKey || !jwtSecret) {
    return null;
  }
  return {
    url: unquote(url),
    anonKey: unquote(anonKey),
    serviceRoleKey: unquote(serviceRoleKey),
    jwtSecret: unquote(jwtSecret),
  };
}

async function mintJwt(
  secret: string,
  claims: { memberId: string; gymId: string; appRole: "member" | "coach" | "owner" },
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  return await new SignJWT({
    sub: claims.memberId,
    role: "authenticated",
    app_role: claims.appRole,
    member_id: claims.memberId,
    gym_id: claims.gymId,
  })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer("supabase")
    .setAudience("authenticated")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(new TextEncoder().encode(secret));
}

function postWithToken(token: string, body: unknown): Request {
  return new Request(ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

type FrequencyRow = {
  member_id: string;
  teamup_customer_id: string | null;
  count: number;
  exercises: string[];
};

Deno.test({
  name:
    "HTTP POST member JWT is refused; owner JWT counts badges in the window only",
  ignore: liveEnv() == null,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const env = liveEnv();
    if (!env) throw new Error("live env disappeared");

    const originalGet = Deno.env.get.bind(Deno.env);
    Deno.env.get = (name: string) => {
      if (name === "SUPABASE_URL") return env.url;
      if (name === "SUPABASE_ANON_KEY") return env.anonKey;
      if (name === "SUPABASE_PUBLISHABLE_KEY") return env.anonKey;
      if (name === "SERVICE_ROLE_KEY") return env.serviceRoleKey;
      if (name === "JWT_SIGNING_SECRET") return env.jwtSecret;
      return originalGet(name);
    };

    const admin = createClient(env.url, env.serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const gymId = crypto.randomUUID();
    const memberA = crypto.randomUUID();
    const memberB = crypto.randomUUID();
    const memberCaller = crypto.randomUUID();
    const ownerCaller = crypto.randomUUID();
    const squatId = crypto.randomUUID();
    const benchId = crypto.randomUUID();
    const providerId = `owner-freq-test-${gymId.slice(0, 8)}`;

    const sessionABefore = crypto.randomUUID();
    const sessionAIn = crypto.randomUUID();
    const sessionATie = crypto.randomUUID();
    const sessionBFirst = crypto.randomUUID();
    const sessionBBench = crypto.randomUUID();
    const sessionBSecond = crypto.randomUUID();

    const entryABefore = crypto.randomUUID();
    const entryAIn = crypto.randomUUID();
    const entryATie = crypto.randomUUID();
    const entryBFirst = crypto.randomUUID();
    const entryBBench = crypto.randomUUID();
    const entryBSecond = crypto.randomUUID();

    const setABefore = crypto.randomUUID();
    const setAIn = crypto.randomUUID();
    const setATie = crypto.randomUUID();
    const setBFirst = crypto.randomUUID();
    const setBBench = crypto.randomUUID();
    const setBSecond = crypto.randomUUID();
    const undatedManual = crypto.randomUUID();

    try {
      const gymInsert = await admin.from("gyms").insert({
        id: gymId,
        teamup_provider_id: providerId,
        name: "Owner Frequency Test Gym",
      });
      if (gymInsert.error) throw gymInsert.error;

      const membersInsert = await admin.from("members").insert([
        {
          id: memberA,
          gym_id: gymId,
          teamup_customer_id: "FREQ-A",
          display_name: "Freq A",
        },
        {
          id: memberB,
          gym_id: gymId,
          teamup_customer_id: "FREQ-B",
          display_name: "Freq B",
        },
        {
          id: memberCaller,
          gym_id: gymId,
          teamup_customer_id: "FREQ-CALLER",
          display_name: "Freq Caller",
        },
        {
          id: ownerCaller,
          gym_id: gymId,
          teamup_customer_id: "FREQ-OWNER",
          display_name: "Freq Owner",
        },
      ]);
      if (membersInsert.error) throw membersInsert.error;

      const exerciseInsert = await admin.from("exercises").insert([
        {
          id: squatId,
          gym_id: gymId,
          name: "Test Squat",
          category: "pbExercise",
          measurement_type: "weightAndReps",
          pb_rule: "heaviestWeightAtReps",
          target_reps: 5,
          display_order: 1,
          is_active: true,
        },
        {
          id: benchId,
          gym_id: gymId,
          name: "Test Bench",
          category: "pbExercise",
          measurement_type: "weightAndReps",
          pb_rule: "heaviestWeightAtReps",
          target_reps: 5,
          display_order: 2,
          is_active: true,
        },
      ]);
      if (exerciseInsert.error) throw exerciseInsert.error;

      const sessionInsert = await admin.from("sessions").insert([
        { id: sessionABefore, gym_id: gymId, member_id: memberA, date: "2026-06-30" },
        { id: sessionAIn, gym_id: gymId, member_id: memberA, date: "2026-07-02" },
        { id: sessionATie, gym_id: gymId, member_id: memberA, date: "2026-07-15" },
        { id: sessionBFirst, gym_id: gymId, member_id: memberB, date: "2026-07-05" },
        { id: sessionBBench, gym_id: gymId, member_id: memberB, date: "2026-07-12" },
        { id: sessionBSecond, gym_id: gymId, member_id: memberB, date: "2026-07-20" },
      ]);
      if (sessionInsert.error) throw sessionInsert.error;

      const entryInsert = await admin.from("exercise_entries").insert([
        { id: entryABefore, gym_id: gymId, session_id: sessionABefore, exercise_id: squatId },
        { id: entryAIn, gym_id: gymId, session_id: sessionAIn, exercise_id: squatId },
        { id: entryATie, gym_id: gymId, session_id: sessionATie, exercise_id: squatId },
        { id: entryBFirst, gym_id: gymId, session_id: sessionBFirst, exercise_id: squatId },
        { id: entryBBench, gym_id: gymId, session_id: sessionBBench, exercise_id: benchId },
        { id: entryBSecond, gym_id: gymId, session_id: sessionBSecond, exercise_id: squatId },
      ]);
      if (entryInsert.error) throw entryInsert.error;

      const setInsert = await admin.from("sets").insert([
        { id: setABefore, gym_id: gymId, exercise_entry_id: entryABefore, weight: 80, reps: 5 },
        { id: setAIn, gym_id: gymId, exercise_entry_id: entryAIn, weight: 90, reps: 5 },
        { id: setATie, gym_id: gymId, exercise_entry_id: entryATie, weight: 90, reps: 5 },
        { id: setBFirst, gym_id: gymId, exercise_entry_id: entryBFirst, weight: 100, reps: 5 },
        { id: setBBench, gym_id: gymId, exercise_entry_id: entryBBench, weight: 70, reps: 5 },
        { id: setBSecond, gym_id: gymId, exercise_entry_id: entryBSecond, weight: 110, reps: 5 },
      ]);
      if (setInsert.error) throw setInsert.error;

      const manualInsert = await admin.from("personal_bests").insert({
        id: undatedManual,
        gym_id: gymId,
        member_id: memberB,
        exercise_id: squatId,
        set_id: null,
        weight: 200,
        reps: 5,
        achieved_at: null,
        entry_type: "manualEntry",
      });
      if (manualInsert.error) throw manualInsert.error;

      const squatRecordsA = [
        { id: setABefore, achievedAt: "2026-06-30", weight: 80, reps: 5 },
        { id: setAIn, achievedAt: "2026-07-02", weight: 90, reps: 5 },
        { id: setATie, achievedAt: "2026-07-15", weight: 90, reps: 5 },
      ];
      const squatRecordsB = [
        { id: setBFirst, achievedAt: "2026-07-05", weight: 100, reps: 5 },
        { id: setBSecond, achievedAt: "2026-07-20", weight: 110, reps: 5 },
        { id: undatedManual, achievedAt: null, weight: 200, reps: 5 },
      ];
      const expectedASquat = badgeIds({
        rule: "heaviestWeightAtReps",
        records: squatRecordsA,
      });
      const expectedBSquat = badgeIds({
        rule: "heaviestWeightAtReps",
        records: squatRecordsB,
      });
      assertEquals(expectedASquat, [setABefore, setAIn]);
      assertEquals(expectedBSquat, [setBFirst, setBSecond]);

      const memberToken = await mintJwt(env.jwtSecret, {
        memberId: memberCaller,
        gymId,
        appRole: "member",
      });
      const ownerToken = await mintJwt(env.jwtSecret, {
        memberId: ownerCaller,
        gymId,
        appRole: "owner",
      });

      const window = { from: "2026-07-01", to: "2026-07-31" };

      const memberRes = await handleOwnerPbFrequencyRequest(
        postWithToken(memberToken, window),
      );
      assertEquals(memberRes.status, 403);
      const memberBody = await memberRes.json() as {
        error?: string;
        members?: unknown;
      };
      assertEquals(memberBody.error, "Forbidden");
      assertEquals(memberBody.members, undefined);

      const ownerRes = await handleOwnerPbFrequencyRequest(
        postWithToken(ownerToken, window),
      );
      assertEquals(ownerRes.status, 200);
      const ownerBody = await ownerRes.json() as {
        period: { from: string; to: string };
        members: FrequencyRow[];
        sessions?: unknown;
        sets?: unknown;
      };
      assertEquals(ownerBody.period, window);
      assertEquals(ownerBody.sessions, undefined);
      assertEquals(ownerBody.sets, undefined);

      assertEquals(ownerBody.members.length, 2);
      assertEquals(ownerBody.members[0].member_id, memberB);
      assertEquals(ownerBody.members[0].teamup_customer_id, "FREQ-B");
      assertEquals(ownerBody.members[0].count, 3);
      assertEquals(ownerBody.members[0].exercises, ["Test Squat", "Test Bench"]);

      assertEquals(ownerBody.members[1].member_id, memberA);
      assertEquals(ownerBody.members[1].teamup_customer_id, "FREQ-A");
      assertEquals(ownerBody.members[1].count, 1);
      assertEquals(ownerBody.members[1].exercises, ["Test Squat"]);

      const keys = new Set(
        ownerBody.members.flatMap((row) => Object.keys(row)),
      );
      assertEquals(keys.has("sessions"), false);
      assertEquals(keys.has("sets"), false);
      assert(ownerBody.members[1].count === 1, "June 30 PB must not count in July");
    } finally {
      Deno.env.get = originalGet;
    }
  },
});
