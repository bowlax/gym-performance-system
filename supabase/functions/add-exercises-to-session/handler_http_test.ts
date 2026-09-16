/**
 * HTTP-level tests for add-exercises-to-session (#27).
 *
 * Routing tests always run. Live tests confirm attach-to-existing, refuse
 * tombstones, all-or-nothing writes, and synced_at stamps for iOS pull.
 */
import { assertEquals, assert } from "jsr:@std/assert@1";
import { SignJWT } from "jsr:@panva/jose@6";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleAddExercisesToSessionRequest } from "./handler.ts";
import {
  onlyIfLoopback,
  tombstoneIsolatedGymTree,
} from "../_shared/test-isolated-gym-teardown.ts";

const ENDPOINT = "http://localhost/functions/v1/add-exercises-to-session";
const MEMBER_JWT =
  "Bearer eyJhbGciOiJub25lIn0.eyJtZW1iZXJfaWQiOiIwMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDAiLCJneW1faWQiOiIwMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEifQ.";

Deno.test("HTTP GET add-exercises-to-session returns 405 via the served handler", async () => {
  const res = await handleAddExercisesToSessionRequest(
    new Request(ENDPOINT, { method: "GET" }),
  );
  assertEquals(res.status, 405);
});

Deno.test("HTTP POST add-exercises-to-session without Authorization returns 401", async () => {
  const res = await handleAddExercisesToSessionRequest(
    new Request(ENDPOINT, { method: "POST" }),
  );
  assertEquals(res.status, 401);
});

Deno.test("HTTP OPTIONS add-exercises-to-session returns 200 via the served handler", async () => {
  const res = await handleAddExercisesToSessionRequest(
    new Request(ENDPOINT, { method: "OPTIONS" }),
  );
  assertEquals(res.status, 200);
});

Deno.test("HTTP POST add-exercises-to-session with invalid body returns 400", async () => {
  const res = await handleAddExercisesToSessionRequest(
    new Request(ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: MEMBER_JWT,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({}),
    }),
  );
  assertEquals(res.status, 400);
});

Deno.test("HTTP POST add-exercises-to-session with empty exercises returns 400", async () => {
  const res = await handleAddExercisesToSessionRequest(
    new Request(ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: MEMBER_JWT,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        sessionId: "00000000-0000-4000-8000-0000000000aa",
        exercises: [],
      }),
    }),
  );
  assertEquals(res.status, 400);
  const body = await res.json() as { error?: string };
  assertEquals(body.error, "At least one exercise is required.");
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
  name: "HTTP POST add-exercises-to-session attaches to a live session, refuses tombstones, rolls back on invalid exercise",
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
    const pressId = crypto.randomUUID();
    const rowId = crypto.randomUUID();
    const sessionId = crypto.randomUUID();
    const tombstoneId = crypto.randomUUID();
    const keepEntryId = crypto.randomUUID();
    const keepSetId = crypto.randomUUID();
    const addEntryId = crypto.randomUUID();
    const addSetId = crypto.randomUUID();
    const rollbackEntryId = crypto.randomUUID();
    const rollbackSetId = crypto.randomUUID();
    const providerId = `add-ex-${gymId.slice(0, 8)}`;

    try {
      const gymInsert = await admin.from("gyms").insert({
        id: gymId,
        teamup_provider_id: providerId,
        name: "Add Exercises Gym",
      });
      if (gymInsert.error) throw gymInsert.error;

      const memberInsert = await admin.from("members").insert([
        {
          id: memberId,
          gym_id: gymId,
          teamup_customer_id: "ADD-EX",
          display_name: "Add Exercises Member",
        },
        {
          id: otherMember,
          gym_id: gymId,
          teamup_customer_id: "ADD-EX-OTHER",
          display_name: "Other Member",
        },
      ]);
      if (memberInsert.error) throw memberInsert.error;

      const exerciseInsert = await admin.from("exercises").insert([
        {
          id: pressId,
          gym_id: gymId,
          name: "Add Exercises Press",
          category: "pbExercise",
          measurement_type: "weightAndReps",
          pb_rule: "heaviestWeightAtReps",
          target_reps: 5,
          display_order: 1,
          is_active: true,
        },
        {
          id: rowId,
          gym_id: gymId,
          name: "Add Exercises Row",
          category: "pbExercise",
          measurement_type: "weightAndReps",
          pb_rule: "heaviestWeight",
          display_order: 2,
          is_active: true,
        },
      ]);
      if (exerciseInsert.error) throw exerciseInsert.error;

      const sessionInsert = await admin.from("sessions").insert([
        {
          id: sessionId,
          gym_id: gymId,
          member_id: memberId,
          date: "2026-06-01",
          notes: "original notes",
          calories_burned: 200,
        },
        {
          id: tombstoneId,
          gym_id: gymId,
          member_id: memberId,
          date: "2026-05-01",
          deleted_at: new Date().toISOString(),
        },
      ]);
      if (sessionInsert.error) throw sessionInsert.error;

      const keepInsert = await admin.from("exercise_entries").insert({
        id: keepEntryId,
        gym_id: gymId,
        session_id: sessionId,
        exercise_id: pressId,
      });
      if (keepInsert.error) throw keepInsert.error;
      const keepSetInsert = await admin.from("sets").insert({
        id: keepSetId,
        gym_id: gymId,
        exercise_entry_id: keepEntryId,
        weight: 80,
        reps: 5,
      });
      if (keepSetInsert.error) throw keepSetInsert.error;

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

      const missingRes = await handleAddExercisesToSessionRequest(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${memberToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            sessionId: crypto.randomUUID(),
            exercises: [{
              exerciseId: rowId,
              sets: [{ weight: 90, reps: 8 }],
            }],
          }),
        }),
      );
      assertEquals(missingRes.status, 404);

      const tombstoneRes = await handleAddExercisesToSessionRequest(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${memberToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            sessionId: tombstoneId,
            exercises: [{
              exerciseId: rowId,
              sets: [{ weight: 90, reps: 8 }],
            }],
          }),
        }),
      );
      assertEquals(tombstoneRes.status, 404);

      const foreignRes = await handleAddExercisesToSessionRequest(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${otherToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            sessionId,
            exercises: [{
              exerciseId: rowId,
              sets: [{ weight: 90, reps: 8 }],
            }],
          }),
        }),
      );
      assertEquals(foreignRes.status, 404);

      const beforeSession = await admin
        .from("sessions")
        .select("updated_at")
        .eq("id", sessionId)
        .single();
      if (beforeSession.error) throw beforeSession.error;
      const updatedAtBefore = beforeSession.data.updated_at;

      const addRes = await handleAddExercisesToSessionRequest(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${memberToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            sessionId,
            exercises: [{
              exerciseId: rowId,
              exerciseEntryId: addEntryId,
              sets: [{ id: addSetId, weight: 90, reps: 8 }],
            }],
          }),
        }),
      );
      assertEquals(addRes.status, 200);
      const addBody = await addRes.json() as {
        session?: { id?: string; date?: string; notes?: string };
        exercises?: Array<{ exerciseId?: string; sets?: Array<{ id?: string }> }>;
      };
      assertEquals(addBody.session?.id, sessionId);
      assertEquals(addBody.session?.date, "2026-06-01");
      assertEquals(addBody.session?.notes, "original notes");
      assertEquals(addBody.exercises?.[0]?.exerciseId, rowId);
      assertEquals(addBody.exercises?.[0]?.sets?.[0]?.id, addSetId);

      const sessionRow = await admin
        .from("sessions")
        .select("date, notes, calories_burned, deleted_at, updated_at")
        .eq("id", sessionId)
        .single();
      if (sessionRow.error) throw sessionRow.error;
      assertEquals(sessionRow.data.date, "2026-06-01");
      assertEquals(sessionRow.data.notes, "original notes");
      assertEquals(sessionRow.data.calories_burned, 200);
      assertEquals(sessionRow.data.deleted_at, null);
      assertEquals(sessionRow.data.updated_at, updatedAtBefore);

      const addedSet = await admin
        .from("sets")
        .select("id, weight, synced_at, deleted_at")
        .eq("id", addSetId)
        .single();
      if (addedSet.error) throw addedSet.error;
      assertEquals(addedSet.data.weight, 90);
      assertEquals(addedSet.data.deleted_at, null);
      assert(addedSet.data.synced_at != null);

      const addedEntry = await admin
        .from("exercise_entries")
        .select("synced_at, session_id")
        .eq("id", addEntryId)
        .single();
      if (addedEntry.error) throw addedEntry.error;
      assertEquals(addedEntry.data.session_id, sessionId);
      assert(addedEntry.data.synced_at != null);

      const keepSet = await admin
        .from("sets")
        .select("id")
        .eq("id", keepSetId)
        .single();
      if (keepSet.error) throw keepSet.error;
      assertEquals(keepSet.data.id, keepSetId);

      const rollbackRes = await handleAddExercisesToSessionRequest(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${memberToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            sessionId,
            exercises: [
              {
                exerciseId: pressId,
                exerciseEntryId: rollbackEntryId,
                sets: [{ id: rollbackSetId, weight: 110, reps: 5 }],
              },
              {
                exerciseId: crypto.randomUUID(),
                sets: [{ weight: 50, reps: 5 }],
              },
            ],
          }),
        }),
      );
      assertEquals(rollbackRes.status, 404);

      const rolled = await admin
        .from("sets")
        .select("id")
        .eq("id", rollbackSetId);
      if (rolled.error) throw rolled.error;
      assertEquals(rolled.data.length, 0);
    } finally {
      try {
        await tombstoneIsolatedGymTree(admin, [gymId]);
      } finally {
        Deno.env.get = originalGet;
      }
    }
  },
});
