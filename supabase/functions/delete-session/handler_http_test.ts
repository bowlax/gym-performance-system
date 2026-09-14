/**
 * HTTP-level tests for delete-session.
 *
 * Routing tests always run against handleDeleteSessionRequest.
 * Live tests POST that handler with a signed member JWT, then confirm the
 * cascade tombstone is visible to the same PostgREST filters the web board /
 * history / heatmap use, and to owner-current-pbs / owner-pb-frequency.
 */
import { assertEquals, assert } from "jsr:@std/assert@1";
import { SignJWT } from "jsr:@panva/jose@6";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleDeleteSessionRequest } from "./handler.ts";
import { handleOwnerCurrentPBsRequest } from "../owner-current-pbs/handler.ts";
import { handleOwnerPbFrequencyRequest } from "../owner-pb-frequency/handler.ts";
import {
  onlyIfLoopback,
  tombstoneIsolatedGymTree,
} from "../_shared/test-isolated-gym-teardown.ts";

const ENDPOINT = "http://localhost/functions/v1/delete-session";

Deno.test("HTTP GET delete-session returns 405 via the served handler", async () => {
  const res = await handleDeleteSessionRequest(
    new Request(ENDPOINT, { method: "GET" }),
  );
  assertEquals(res.status, 405);
  const body = await res.json() as { error?: string };
  assertEquals(body.error, "Method not allowed");
});

Deno.test("HTTP POST delete-session without Authorization returns 401", async () => {
  const res = await handleDeleteSessionRequest(
    new Request(ENDPOINT, { method: "POST" }),
  );
  assertEquals(res.status, 401);
  const body = await res.json() as { error?: string };
  assertEquals(body.error, "Unauthorized");
});

Deno.test("HTTP OPTIONS delete-session returns 200 via the served handler", async () => {
  const res = await handleDeleteSessionRequest(
    new Request(ENDPOINT, { method: "OPTIONS" }),
  );
  assertEquals(res.status, 200);
});

Deno.test("HTTP POST delete-session with invalid body returns 400", async () => {
  const res = await handleDeleteSessionRequest(
    new Request(ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: "Bearer eyJhbGciOiJub25lIn0.eyJtZW1iZXJfaWQiOiIwMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDAiLCJneW1faWQiOiIwMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEifQ.",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({}),
    }),
  );
  assertEquals(res.status, 400);
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
  return onlyIfLoopback({ url, anonKey, serviceRoleKey, jwtSecret });
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

Deno.test({
  name: "HTTP POST delete-session cascades tombstones and hides from board, history, owner endpoints",
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
    const memberId = crypto.randomUUID();
    const otherMember = crypto.randomUUID();
    const ownerCaller = crypto.randomUUID();
    const exerciseId = crypto.randomUUID();
    const sessionId = crypto.randomUUID();
    const keepSessionId = crypto.randomUUID();
    const entryId = crypto.randomUUID();
    const keepEntryId = crypto.randomUUID();
    const setId = crypto.randomUUID();
    const keepSetId = crypto.randomUUID();
    const providerId = `del-sess-${gymId.slice(0, 8)}`;

    try {
      const gymInsert = await admin.from("gyms").insert({
        id: gymId,
        teamup_provider_id: providerId,
        name: "Delete Session Gym",
      });
      if (gymInsert.error) throw gymInsert.error;

      const membersInsert = await admin.from("members").insert([
        {
          id: memberId,
          gym_id: gymId,
          teamup_customer_id: "DEL-SESS",
          display_name: "Delete Session Member",
        },
        {
          id: otherMember,
          gym_id: gymId,
          teamup_customer_id: "DEL-SESS-OTHER",
          display_name: "Other Member",
        },
        {
          id: ownerCaller,
          gym_id: gymId,
          teamup_customer_id: "DEL-SESS-OWNER",
          display_name: "Delete Session Owner",
        },
      ]);
      if (membersInsert.error) throw membersInsert.error;

      const exerciseInsert = await admin.from("exercises").insert({
        id: exerciseId,
        gym_id: gymId,
        name: "Delete Session Press",
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
          id: sessionId,
          gym_id: gymId,
          member_id: memberId,
          date: "2026-07-15",
        },
        {
          id: keepSessionId,
          gym_id: gymId,
          member_id: memberId,
          date: "2026-06-01",
        },
      ]);
      if (sessionInsert.error) throw sessionInsert.error;

      const entryInsert = await admin.from("exercise_entries").insert([
        {
          id: entryId,
          gym_id: gymId,
          session_id: sessionId,
          exercise_id: exerciseId,
        },
        {
          id: keepEntryId,
          gym_id: gymId,
          session_id: keepSessionId,
          exercise_id: exerciseId,
        },
      ]);
      if (entryInsert.error) throw entryInsert.error;

      const setInsert = await admin.from("sets").insert([
        {
          id: setId,
          gym_id: gymId,
          exercise_entry_id: entryId,
          weight: 200,
          reps: 5,
        },
        {
          id: keepSetId,
          gym_id: gymId,
          exercise_entry_id: keepEntryId,
          weight: 80,
          reps: 5,
        },
      ]);
      if (setInsert.error) throw setInsert.error;

      const memberToken = await mintJwt(env.jwtSecret, {
        memberId,
        gymId,
        appRole: "member",
      });
      const otherToken = await mintJwt(env.jwtSecret, {
        memberId: otherMember,
        gymId,
        appRole: "member",
      });
      const ownerToken = await mintJwt(env.jwtSecret, {
        memberId: ownerCaller,
        gymId,
        appRole: "owner",
      });

      const beforeOwner = await handleOwnerCurrentPBsRequest(
        new Request("http://localhost/functions/v1/owner-current-pbs", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ownerToken}`,
            "Content-Type": "application/json",
          },
          body: "{}",
        }),
      );
      assertEquals(beforeOwner.status, 200);
      const beforeBody = await beforeOwner.json() as {
        currentPBs: Array<{ value: number; achieved_at: string | null }>;
      };
      assertEquals(beforeBody.currentPBs.length, 1);
      assertEquals(beforeBody.currentPBs[0].value, 200);

      const foreignRes = await handleDeleteSessionRequest(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${otherToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ sessionId }),
        }),
      );
      assertEquals(foreignRes.status, 404);

      const deleteRes = await handleDeleteSessionRequest(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${memberToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ sessionId }),
        }),
      );
      assertEquals(deleteRes.status, 200);
      const deleteBody = await deleteRes.json() as { deleted?: { id?: string } };
      assertEquals(deleteBody.deleted?.id, sessionId);

      const sessionRow = await admin
        .from("sessions")
        .select("id, deleted_at, updated_at")
        .eq("id", sessionId)
        .single();
      if (sessionRow.error) throw sessionRow.error;
      assert(sessionRow.data.deleted_at != null);
      assert(sessionRow.data.updated_at != null);

      const entryRow = await admin
        .from("exercise_entries")
        .select("id, deleted_at, updated_at")
        .eq("id", entryId)
        .single();
      if (entryRow.error) throw entryRow.error;
      assert(entryRow.data.deleted_at != null);
      assert(entryRow.data.updated_at != null);

      const setRow = await admin
        .from("sets")
        .select("id, deleted_at, updated_at")
        .eq("id", setId)
        .single();
      if (setRow.error) throw setRow.error;
      assert(setRow.data.deleted_at != null);
      assert(setRow.data.updated_at != null);

      const keepSession = await admin
        .from("sessions")
        .select("deleted_at")
        .eq("id", keepSessionId)
        .single();
      if (keepSession.error) throw keepSession.error;
      assertEquals(keepSession.data.deleted_at, null);

      const memberClient = createClient(env.url, env.anonKey, {
        global: { headers: { Authorization: `Bearer ${memberToken}` } },
        auth: { autoRefreshToken: false, persistSession: false },
      });

      const history = await memberClient
        .from("sessions")
        .select("id")
        .is("deleted_at", null);
      if (history.error) throw history.error;
      const historyIds = (history.data ?? []).map((row) => row.id);
      assertEquals(historyIds.includes(sessionId), false);
      assertEquals(historyIds.includes(keepSessionId), true);

      const derivation = await memberClient
        .from("exercise_entries")
        .select(
          "id, session:sessions!inner(id), sets(id, weight, deleted_at)",
        )
        .eq("exercise_id", exerciseId)
        .is("deleted_at", null)
        .is("session.deleted_at", null);
      if (derivation.error) throw derivation.error;
      const liveSetWeights: number[] = [];
      for (const row of derivation.data ?? []) {
        for (const set of (row.sets ?? []) as Array<{
          weight?: number | null;
          deleted_at?: string | null;
        }>) {
          if (set.deleted_at != null) continue;
          if (typeof set.weight === "number") liveSetWeights.push(set.weight);
        }
      }
      assertEquals(liveSetWeights, [80]);

      const afterOwner = await handleOwnerCurrentPBsRequest(
        new Request("http://localhost/functions/v1/owner-current-pbs", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ownerToken}`,
            "Content-Type": "application/json",
          },
          body: "{}",
        }),
      );
      assertEquals(afterOwner.status, 200);
      const afterBody = await afterOwner.json() as {
        currentPBs: Array<{ value: number; achieved_at: string | null }>;
      };
      assertEquals(afterBody.currentPBs.length, 1);
      assertEquals(afterBody.currentPBs[0].value, 80);
      assertEquals(afterBody.currentPBs[0].achieved_at, "2026-06-01");

      const frequencyRes = await handleOwnerPbFrequencyRequest(
        new Request("http://localhost/functions/v1/owner-pb-frequency", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ownerToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ from: "2026-07-01", to: "2026-07-31" }),
        }),
      );
      assertEquals(frequencyRes.status, 200);
      const frequencyBody = await frequencyRes.json() as {
        members: Array<{ count: number; hits: Array<{ achieved_at: string | null }> }>;
      };
      assertEquals(frequencyBody.members.length, 0);
    } finally {
      try {
        await tombstoneIsolatedGymTree(admin, [gymId]);
      } finally {
        Deno.env.get = originalGet;
      }
    }
  },
});
