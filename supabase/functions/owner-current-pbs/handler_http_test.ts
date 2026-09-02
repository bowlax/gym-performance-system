/**
 * HTTP-level tests for owner-current-pbs.
 *
 * Routing tests always run against handleOwnerCurrentPBsRequest (the same
 * function Deno.serve wires in index.ts).
 *
 * RLS tests POST that handler with signed JWTs against a live PostgREST.
 * They are not helper-boolean tests: member vs owner is decided by the
 * owner_surface_grants policy the handler queries, then by gym-wide
 * derivation.
 */
import { assertEquals, assert } from "jsr:@std/assert@1";
import { SignJWT } from "jsr:@panva/jose@6";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleOwnerCurrentPBsRequest } from "./handler.ts";
import { derivePBs } from "../_shared/pb-derivation.ts";
import { todayUtcDateString } from "../_shared/member-edge.ts";

const ENDPOINT = "http://localhost/functions/v1/owner-current-pbs";

Deno.test("HTTP GET owner-current-pbs returns 405 via the served handler", async () => {
  const res = await handleOwnerCurrentPBsRequest(
    new Request(ENDPOINT, { method: "GET" }),
  );
  assertEquals(res.status, 405);
  const body = await res.json() as { error?: string };
  assertEquals(body.error, "Method not allowed");
});

Deno.test("HTTP POST owner-current-pbs without Authorization returns 401", async () => {
  const res = await handleOwnerCurrentPBsRequest(
    new Request(ENDPOINT, { method: "POST" }),
  );
  assertEquals(res.status, 401);
  const body = await res.json() as { error?: string };
  assertEquals(body.error, "Unauthorized");
});

Deno.test("HTTP OPTIONS owner-current-pbs returns 200 via the served handler", async () => {
  const res = await handleOwnerCurrentPBsRequest(
    new Request(ENDPOINT, { method: "OPTIONS" }),
  );
  assertEquals(res.status, 200);
});

interface LiveEnv {
  url: string;
  anonKey: string;
  serviceRoleKey: string;
  jwtSecret: string;
}

function liveEnv(): LiveEnv | null {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const jwtSecret = Deno.env.get("JWT_SIGNING_SECRET");
  if (!url || !anonKey || !serviceRoleKey || !jwtSecret) {
    return null;
  }
  return { url, anonKey, serviceRoleKey, jwtSecret };
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

function postWithToken(token: string): Request {
  return new Request(ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: "{}",
  });
}

type OwnerPBRow = {
  member_id: string;
  teamup_customer_id: string | null;
  exercise_id: string;
  exercise_name: string;
  value: number;
  reps: number | null;
  achieved_at: string | null;
};

Deno.test({
  name: "HTTP POST member JWT is refused; owner JWT returns gym-wide derived current PBs only",
  ignore: liveEnv() == null,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const env = liveEnv();
    if (!env) {
      throw new Error("live env disappeared");
    }

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
    const exerciseId = crypto.randomUUID();
    const sessionA = crypto.randomUUID();
    const sessionB = crypto.randomUUID();
    const entryA = crypto.randomUUID();
    const entryB = crypto.randomUUID();
    const setA = crypto.randomUUID();
    const setB = crypto.randomUUID();
    const resetA = crypto.randomUUID();
    const providerId = `owner-pb-test-${gymId.slice(0, 8)}`;

    try {
      const gymInsert = await admin.from("gyms").insert({
        id: gymId,
        teamup_provider_id: providerId,
        name: "Owner PB Test Gym",
      });
      if (gymInsert.error) throw gymInsert.error;

      const membersInsert = await admin.from("members").insert([
        {
          id: memberA,
          gym_id: gymId,
          teamup_customer_id: "TU-A",
          display_name: "Member A",
        },
        {
          id: memberB,
          gym_id: gymId,
          teamup_customer_id: "TU-B",
          display_name: "Member B",
        },
        {
          id: memberCaller,
          gym_id: gymId,
          teamup_customer_id: "TU-CALLER",
          display_name: "Member Caller",
        },
        {
          id: ownerCaller,
          gym_id: gymId,
          teamup_customer_id: "TU-OWNER",
          display_name: "Owner Caller",
        },
      ]);
      if (membersInsert.error) throw membersInsert.error;

      const exerciseInsert = await admin.from("exercises").insert({
        id: exerciseId,
        gym_id: gymId,
        name: "Test Press",
        category: "pbExercise",
        measurement_type: "weightAndReps",
        pb_rule: "heaviestWeightAtReps",
        target_reps: 5,
        display_order: 1,
        is_active: true,
      });
      if (exerciseInsert.error) throw exerciseInsert.error;

      const sessionInsert = await admin.from("sessions").insert([
        {
          id: sessionA,
          gym_id: gymId,
          member_id: memberA,
          date: "2026-01-15",
        },
        {
          id: sessionB,
          gym_id: gymId,
          member_id: memberB,
          date: "2026-07-01",
        },
      ]);
      if (sessionInsert.error) throw sessionInsert.error;

      const entryInsert = await admin.from("exercise_entries").insert([
        {
          id: entryA,
          gym_id: gymId,
          session_id: sessionA,
          exercise_id: exerciseId,
        },
        {
          id: entryB,
          gym_id: gymId,
          session_id: sessionB,
          exercise_id: exerciseId,
        },
      ]);
      if (entryInsert.error) throw entryInsert.error;

      const setInsert = await admin.from("sets").insert([
        {
          id: setA,
          gym_id: gymId,
          exercise_entry_id: entryA,
          weight: 100,
          reps: 5,
        },
        {
          id: setB,
          gym_id: gymId,
          exercise_entry_id: entryB,
          weight: 80,
          reps: 5,
        },
      ]);
      if (setInsert.error) throw setInsert.error;

      const resetInsert = await admin.from("exercise_resets").insert({
        id: resetA,
        gym_id: gymId,
        member_id: memberA,
        exercise_id: exerciseId,
        reset_at: "2026-06-01",
      });
      if (resetInsert.error) throw resetInsert.error;

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

      const memberRes = await handleOwnerCurrentPBsRequest(
        postWithToken(memberToken),
      );
      assertEquals(memberRes.status, 403);
      const memberBody = await memberRes.json() as { error?: string; currentPBs?: unknown };
      assertEquals(memberBody.error, "Forbidden");
      assertEquals(memberBody.currentPBs, undefined);

      const ownerRes = await handleOwnerCurrentPBsRequest(
        postWithToken(ownerToken),
      );
      assertEquals(ownerRes.status, 200);
      const ownerBody = await ownerRes.json() as {
        currentPBs: OwnerPBRow[];
        sessions?: unknown;
        sets?: unknown;
        exercise_entries?: unknown;
      };

      assertEquals(ownerBody.sessions, undefined);
      assertEquals(ownerBody.sets, undefined);
      assertEquals(ownerBody.exercise_entries, undefined);
      assertEquals(Array.isArray(ownerBody.currentPBs), true);

      const keys = new Set(
        ownerBody.currentPBs.flatMap((row) => Object.keys(row)),
      );
      assertEquals(keys.has("sessions"), false);
      assertEquals(keys.has("sets"), false);
      assertEquals(keys.has("exercise_entries"), false);

      const expectedA = derivePBs({
        rule: "heaviestWeightAtReps",
        records: [{
          id: setA,
          achievedAt: "2026-01-15",
          weight: 100,
          reps: 5,
          time: null,
          distance: null,
          entryKind: "set",
        }],
        staleness: { enabled: false, periods: 2, unit: "quarters" },
        resetAt: "2026-06-01",
        evaluatedAt: todayUtcDateString(),
      });
      const expectedB = derivePBs({
        rule: "heaviestWeightAtReps",
        records: [{
          id: setB,
          achievedAt: "2026-07-01",
          weight: 80,
          reps: 5,
          time: null,
          distance: null,
          entryKind: "set",
        }],
        staleness: { enabled: false, periods: 2, unit: "quarters" },
        resetAt: null,
        evaluatedAt: todayUtcDateString(),
      });

      assertEquals(expectedA.currentPB, null);
      assertEquals(expectedB.currentPB?.weight, 80);

      const byMember = new Map(
        ownerBody.currentPBs.map((row) => [row.member_id, row]),
      );
      assertEquals(byMember.has(memberA), false);
      const rowB = byMember.get(memberB);
      assert(rowB != null, "owner payload must include member B current PB");
      assertEquals(rowB.teamup_customer_id, "TU-B");
      assertEquals(rowB.exercise_id, exerciseId);
      assertEquals(rowB.exercise_name, "Test Press");
      assertEquals(rowB.value, 80);
      assertEquals(rowB.reps, 5);
      assertEquals(rowB.achieved_at, "2026-07-01");
      assertEquals(ownerBody.currentPBs.length, 1);
    } finally {
      Deno.env.get = originalGet;
    }
  },
});
