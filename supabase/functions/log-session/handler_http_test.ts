/**
 * HTTP-level tests for log-session (#23).
 *
 * Routing tests always run against handleLogSessionRequest.
 * Live tests POST that handler with a signed member JWT, then confirm the
 * session tree is written in one transaction (all-or-nothing) and that a
 * retry with the same client ids is idempotent.
 */
import { assertEquals, assert } from "jsr:@std/assert@1";
import { SignJWT } from "jsr:@panva/jose@6";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleLogSessionRequest } from "./handler.ts";
import {
  onlyIfLoopback,
  tombstoneIsolatedGymTree,
} from "../_shared/test-isolated-gym-teardown.ts";

const ENDPOINT = "http://localhost/functions/v1/log-session";
const MEMBER_JWT =
  "Bearer eyJhbGciOiJub25lIn0.eyJtZW1iZXJfaWQiOiIwMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDAiLCJneW1faWQiOiIwMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEifQ.";

Deno.test("HTTP GET log-session returns 405 via the served handler", async () => {
  const res = await handleLogSessionRequest(
    new Request(ENDPOINT, { method: "GET" }),
  );
  assertEquals(res.status, 405);
  const body = await res.json() as { error?: string };
  assertEquals(body.error, "Method not allowed");
});

Deno.test("HTTP POST log-session without Authorization returns 401", async () => {
  const res = await handleLogSessionRequest(
    new Request(ENDPOINT, { method: "POST" }),
  );
  assertEquals(res.status, 401);
  const body = await res.json() as { error?: string };
  assertEquals(body.error, "Unauthorized");
});

Deno.test("HTTP OPTIONS log-session returns 200 via the served handler", async () => {
  const res = await handleLogSessionRequest(
    new Request(ENDPOINT, { method: "OPTIONS" }),
  );
  assertEquals(res.status, 200);
});

Deno.test("HTTP POST log-session with invalid body returns 400", async () => {
  const res = await handleLogSessionRequest(
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

Deno.test("HTTP POST log-session with empty exercises returns 400", async () => {
  const res = await handleLogSessionRequest(
    new Request(ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: MEMBER_JWT,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        session: { date: "2026-09-16" },
        exercises: [],
      }),
    }),
  );
  assertEquals(res.status, 400);
  const body = await res.json() as { error?: string };
  assertEquals(body.error, "At least one exercise is required.");
});

Deno.test("HTTP POST log-session with duplicate ids returns 400", async () => {
  const id = "00000000-0000-4000-8000-0000000000aa";
  const res = await handleLogSessionRequest(
    new Request(ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: MEMBER_JWT,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        session: { id, date: "2026-09-16" },
        exercises: [
          {
            exerciseId: "00000000-0000-4000-8000-0000000000bb",
            exerciseEntryId: id,
            sets: [{ weight: 100, reps: 5 }],
          },
        ],
      }),
    }),
  );
  assertEquals(res.status, 400);
  const body = await res.json() as { error?: string };
  assertEquals(body.error, "Duplicate ids in session payload.");
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

interface LogSessionResponse {
  session?: { id?: string; date?: string };
  exercises?: Array<{
    exerciseId?: string;
    exerciseEntryId?: string;
    sets?: Array<{ id?: string; weight?: number | null; reps?: number | null }>;
  }>;
  error?: string;
}

Deno.test({
  name: "HTTP POST log-session writes a multi-exercise session atomically and retries by id",
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
    const pressId = crypto.randomUUID();
    const rowId = crypto.randomUUID();
    const inactiveId = crypto.randomUUID();
    const providerId = `log-sess-${gymId.slice(0, 8)}`;

    const successSessionId = crypto.randomUUID();
    const successEntry1 = crypto.randomUUID();
    const successEntry2 = crypto.randomUUID();
    const successSet1 = crypto.randomUUID();
    const successSet2 = crypto.randomUUID();

    const rollbackSessionId = crypto.randomUUID();
    const rollbackEntry1 = crypto.randomUUID();
    const rollbackEntry2 = crypto.randomUUID();
    const rollbackSet1 = crypto.randomUUID();
    const rollbackSet2 = crypto.randomUUID();

    const inactiveSessionId = crypto.randomUUID();

    try {
      const gymInsert = await admin.from("gyms").insert({
        id: gymId,
        teamup_provider_id: providerId,
        name: "Log Session Gym",
      });
      if (gymInsert.error) throw gymInsert.error;

      const memberInsert = await admin.from("members").insert({
        id: memberId,
        gym_id: gymId,
        teamup_customer_id: "LOG-SESS",
        display_name: "Log Session Member",
      });
      if (memberInsert.error) throw memberInsert.error;

      const exerciseInsert = await admin.from("exercises").insert([
        {
          id: pressId,
          gym_id: gymId,
          name: "Log Session Press",
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
          name: "Log Session Row",
          category: "pbExercise",
          measurement_type: "weightAndReps",
          pb_rule: "heaviestWeight",
          display_order: 2,
          is_active: true,
        },
        {
          id: inactiveId,
          gym_id: gymId,
          name: "Log Session Inactive",
          category: "pbExercise",
          measurement_type: "weightAndReps",
          pb_rule: "heaviestWeight",
          display_order: 3,
          is_active: false,
        },
      ]);
      if (exerciseInsert.error) throw exerciseInsert.error;

      const memberToken = await mintJwt(env.jwtSecret, {
        memberId,
        gymId,
        appRole: "member",
      });

      const successPayload = {
        session: {
          id: successSessionId,
          date: "2026-09-16",
          notes: "atomic save",
          calories_burned: 350,
        },
        exercises: [
          {
            exerciseId: pressId,
            exerciseEntryId: successEntry1,
            sets: [{ id: successSet1, weight: 100, reps: 5 }],
          },
          {
            exerciseId: rowId,
            exerciseEntryId: successEntry2,
            sets: [{ id: successSet2, weight: 80, reps: 8 }],
          },
        ],
      };

      const firstRes = await handleLogSessionRequest(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${memberToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(successPayload),
        }),
      );
      assertEquals(firstRes.status, 200);
      const firstBody = await firstRes.json() as LogSessionResponse;
      assertEquals(firstBody.session?.id, successSessionId);
      assertEquals(firstBody.exercises?.length, 2);
      assertEquals(firstBody.exercises?.[0]?.sets?.[0]?.id, successSet1);
      assertEquals(firstBody.exercises?.[1]?.sets?.[0]?.id, successSet2);

      const retryRes = await handleLogSessionRequest(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${memberToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(successPayload),
        }),
      );
      assertEquals(retryRes.status, 200);
      const retryBody = await retryRes.json() as LogSessionResponse;
      assertEquals(retryBody.session?.id, successSessionId);

      const sessionRows = await admin
        .from("sessions")
        .select("id, notes, calories_burned, deleted_at")
        .eq("member_id", memberId)
        .is("deleted_at", null);
      if (sessionRows.error) throw sessionRows.error;
      assertEquals(sessionRows.data.length, 1);
      assertEquals(sessionRows.data[0].id, successSessionId);
      assertEquals(sessionRows.data[0].notes, "atomic save");
      assertEquals(sessionRows.data[0].calories_burned, 350);

      const setRows = await admin
        .from("sets")
        .select("id, weight, reps, deleted_at")
        .in("id", [successSet1, successSet2]);
      if (setRows.error) throw setRows.error;
      assertEquals(setRows.data.length, 2);

      const missingExerciseId = crypto.randomUUID();
      const rollbackRes = await handleLogSessionRequest(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${memberToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            session: {
              id: rollbackSessionId,
              date: "2026-09-16",
            },
            exercises: [
              {
                exerciseId: pressId,
                exerciseEntryId: rollbackEntry1,
                sets: [{ id: rollbackSet1, weight: 110, reps: 5 }],
              },
              {
                exerciseId: missingExerciseId,
                exerciseEntryId: rollbackEntry2,
                sets: [{ id: rollbackSet2, weight: 90, reps: 5 }],
              },
            ],
          }),
        }),
      );
      assertEquals(rollbackRes.status, 404);
      const rollbackBody = await rollbackRes.json() as LogSessionResponse;
      assertEquals(rollbackBody.error, "Exercise not found");

      const rolledSession = await admin
        .from("sessions")
        .select("id")
        .eq("id", rollbackSessionId);
      if (rolledSession.error) throw rolledSession.error;
      assertEquals(rolledSession.data.length, 0);

      const rolledSet = await admin
        .from("sets")
        .select("id")
        .eq("id", rollbackSet1);
      if (rolledSet.error) throw rolledSet.error;
      assertEquals(rolledSet.data.length, 0);

      const inactiveRes = await handleLogSessionRequest(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${memberToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            session: {
              id: inactiveSessionId,
              date: "2026-09-16",
            },
            exercises: [
              {
                exerciseId: pressId,
                sets: [{ weight: 95, reps: 5 }],
              },
              {
                exerciseId: inactiveId,
                sets: [{ weight: 40, reps: 8 }],
              },
            ],
          }),
        }),
      );
      assertEquals(inactiveRes.status, 400);
      const inactiveBody = await inactiveRes.json() as LogSessionResponse;
      assertEquals(inactiveBody.error, "Exercise is not active");

      const inactiveSession = await admin
        .from("sessions")
        .select("id")
        .eq("id", inactiveSessionId);
      if (inactiveSession.error) throw inactiveSession.error;
      assertEquals(inactiveSession.data.length, 0);

      const memberClient = createClient(env.url, env.anonKey, {
        global: { headers: { Authorization: `Bearer ${memberToken}` } },
        auth: { autoRefreshToken: false, persistSession: false },
      });
      const history = await memberClient
        .from("sessions")
        .select("id")
        .is("deleted_at", null);
      if (history.error) throw history.error;
      assertEquals(
        (history.data ?? []).map((row) => row.id),
        [successSessionId],
      );
      assert(successSet1.length > 0);
    } finally {
      try {
        await tombstoneIsolatedGymTree(admin, [gymId]);
      } finally {
        Deno.env.get = originalGet;
      }
    }
  },
});
