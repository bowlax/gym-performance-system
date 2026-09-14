/**
 * HTTP-level tests for update-manual-pb.
 *
 * Routing tests always run against handleUpdateManualPBRequest.
 * Live tests confirm an in-place update (same id), no beat-current gate,
 * dated ↔ undated, and owner-current-pbs reflecting derivation afterwards.
 */
import { assertEquals, assert } from "jsr:@std/assert@1";
import { SignJWT } from "jsr:@panva/jose@6";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleUpdateManualPBRequest } from "./handler.ts";
import { handleOwnerCurrentPBsRequest } from "../owner-current-pbs/handler.ts";
import {
  onlyIfLoopback,
  tombstoneIsolatedGymTree,
} from "../_shared/test-isolated-gym-teardown.ts";

const ENDPOINT = "http://localhost/functions/v1/update-manual-pb";

Deno.test("HTTP GET update-manual-pb returns 405 via the served handler", async () => {
  const res = await handleUpdateManualPBRequest(
    new Request(ENDPOINT, { method: "GET" }),
  );
  assertEquals(res.status, 405);
  const body = await res.json() as { error?: string };
  assertEquals(body.error, "Method not allowed");
});

Deno.test("HTTP POST update-manual-pb without Authorization returns 401", async () => {
  const res = await handleUpdateManualPBRequest(
    new Request(ENDPOINT, { method: "POST" }),
  );
  assertEquals(res.status, 401);
  const body = await res.json() as { error?: string };
  assertEquals(body.error, "Unauthorized");
});

Deno.test("HTTP OPTIONS update-manual-pb returns 200 via the served handler", async () => {
  const res = await handleUpdateManualPBRequest(
    new Request(ENDPOINT, { method: "OPTIONS" }),
  );
  assertEquals(res.status, 200);
});

Deno.test("HTTP POST update-manual-pb with invalid body returns 400", async () => {
  const res = await handleUpdateManualPBRequest(
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

function postUpdate(
  token: string,
  body: Record<string, unknown>,
): Request {
  return new Request(ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

Deno.test({
  name: "HTTP POST update-manual-pb updates in place, allows a weaker value, and dated/undated changes re-derive",
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
    const ownerCaller = crypto.randomUUID();
    const exerciseId = crypto.randomUUID();
    const sessionId = crypto.randomUUID();
    const entryId = crypto.randomUUID();
    const setId = crypto.randomUUID();
    const manualId = crypto.randomUUID();
    const providerId = `upd-pb-${gymId.slice(0, 8)}`;

    try {
      const gymInsert = await admin.from("gyms").insert({
        id: gymId,
        teamup_provider_id: providerId,
        name: "Update Manual PB Gym",
      });
      if (gymInsert.error) throw gymInsert.error;

      const membersInsert = await admin.from("members").insert([
        {
          id: memberId,
          gym_id: gymId,
          teamup_customer_id: "UPD-PB",
          display_name: "Update Manual Member",
        },
        {
          id: ownerCaller,
          gym_id: gymId,
          teamup_customer_id: "UPD-PB-OWNER",
          display_name: "Update Manual Owner",
        },
      ]);
      if (membersInsert.error) throw membersInsert.error;

      const exerciseInsert = await admin.from("exercises").insert({
        id: exerciseId,
        gym_id: gymId,
        name: "Update Manual Press",
        category: "pbExercise",
        measurement_type: "weightAndReps",
        pb_rule: "heaviestWeightAtReps",
        target_reps: 5,
        display_order: 1,
        is_active: true,
      });
      if (exerciseInsert.error) throw exerciseInsert.error;

      const sessionInsert = await admin.from("sessions").insert({
        id: sessionId,
        gym_id: gymId,
        member_id: memberId,
        date: "2026-07-01",
      });
      if (sessionInsert.error) throw sessionInsert.error;

      const entryInsert = await admin.from("exercise_entries").insert({
        id: entryId,
        gym_id: gymId,
        session_id: sessionId,
        exercise_id: exerciseId,
      });
      if (entryInsert.error) throw entryInsert.error;

      const setInsert = await admin.from("sets").insert({
        id: setId,
        gym_id: gymId,
        exercise_entry_id: entryId,
        weight: 100,
        reps: 5,
      });
      if (setInsert.error) throw setInsert.error;

      const manualInsert = await admin.from("personal_bests").insert({
        id: manualId,
        gym_id: gymId,
        member_id: memberId,
        exercise_id: exerciseId,
        set_id: null,
        weight: 80,
        reps: 5,
        achieved_at: "2026-06-01",
        entry_type: "manualEntry",
      });
      if (manualInsert.error) throw manualInsert.error;

      const memberToken = await mintJwt(env.jwtSecret, {
        memberId,
        gymId,
        appRole: "member",
      });
      const ownerToken = await mintJwt(env.jwtSecret, {
        memberId: ownerCaller,
        gymId,
        appRole: "owner",
      });

      const weaker = await handleUpdateManualPBRequest(
        postUpdate(memberToken, {
          exerciseId,
          personalBestId: manualId,
          weight: 90,
          reps: 5,
          time_seconds: null,
          distance: null,
          achievedAt: "2026-06-01",
        }),
      );
      assertEquals(weaker.status, 200);
      const weakerBody = await weaker.json() as {
        personalBest: { id: string; weight: number; achieved_at: string | null };
      };
      assertEquals(weakerBody.personalBest.id, manualId);
      assertEquals(weakerBody.personalBest.weight, 90);

      const stillSession = await handleOwnerCurrentPBsRequest(
        new Request("http://localhost/functions/v1/owner-current-pbs", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ownerToken}`,
            "Content-Type": "application/json",
          },
          body: "{}",
        }),
      );
      assertEquals(stillSession.status, 200);
      const stillBody = await stillSession.json() as {
        currentPBs: Array<{ value: number; achieved_at: string | null }>;
      };
      assertEquals(stillBody.currentPBs.length, 1);
      assertEquals(stillBody.currentPBs[0].value, 100);

      const stronger = await handleUpdateManualPBRequest(
        postUpdate(memberToken, {
          exerciseId,
          personalBestId: manualId,
          weight: 120,
          reps: 5,
          time_seconds: null,
          distance: null,
          achievedAt: "2026-08-01",
        }),
      );
      assertEquals(stronger.status, 200);
      const strongerBody = await stronger.json() as {
        personalBest: { id: string; weight: number; achieved_at: string | null };
      };
      assertEquals(strongerBody.personalBest.id, manualId);
      assertEquals(strongerBody.personalBest.weight, 120);
      assertEquals(strongerBody.personalBest.achieved_at, "2026-08-01");

      const nowCurrent = await handleOwnerCurrentPBsRequest(
        new Request("http://localhost/functions/v1/owner-current-pbs", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ownerToken}`,
            "Content-Type": "application/json",
          },
          body: "{}",
        }),
      );
      assertEquals(nowCurrent.status, 200);
      const nowBody = await nowCurrent.json() as {
        currentPBs: Array<{ value: number; achieved_at: string | null }>;
      };
      assertEquals(nowBody.currentPBs.length, 1);
      assertEquals(nowBody.currentPBs[0].value, 120);
      assertEquals(nowBody.currentPBs[0].achieved_at, "2026-08-01");

      const undate = await handleUpdateManualPBRequest(
        postUpdate(memberToken, {
          exerciseId,
          personalBestId: manualId,
          weight: 120,
          reps: 5,
          time_seconds: null,
          distance: null,
          achievedAt: null,
        }),
      );
      assertEquals(undate.status, 200);
      const undateBody = await undate.json() as {
        personalBest: { id: string; achieved_at: string | null };
      };
      assertEquals(undateBody.personalBest.id, manualId);
      assertEquals(undateBody.personalBest.achieved_at, null);

      const afterUndate = await handleOwnerCurrentPBsRequest(
        new Request("http://localhost/functions/v1/owner-current-pbs", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ownerToken}`,
            "Content-Type": "application/json",
          },
          body: "{}",
        }),
      );
      assertEquals(afterUndate.status, 200);
      const afterUndateBody = await afterUndate.json() as {
        currentPBs: Array<{ value: number }>;
      };
      assertEquals(afterUndateBody.currentPBs.length, 1);
      assertEquals(afterUndateBody.currentPBs[0].value, 100);

      const redate = await handleUpdateManualPBRequest(
        postUpdate(memberToken, {
          exerciseId,
          personalBestId: manualId,
          weight: 130,
          reps: 5,
          time_seconds: null,
          distance: null,
          achievedAt: "2026-08-15",
        }),
      );
      assertEquals(redate.status, 200);

      const afterRedate = await handleOwnerCurrentPBsRequest(
        new Request("http://localhost/functions/v1/owner-current-pbs", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ownerToken}`,
            "Content-Type": "application/json",
          },
          body: "{}",
        }),
      );
      assertEquals(afterRedate.status, 200);
      const afterRedateBody = await afterRedate.json() as {
        currentPBs: Array<{ value: number; achieved_at: string | null }>;
      };
      assertEquals(afterRedateBody.currentPBs.length, 1);
      assertEquals(afterRedateBody.currentPBs[0].value, 130);

      const stored = await admin
        .from("personal_bests")
        .select("id, weight, achieved_at, updated_at, deleted_at")
        .eq("id", manualId)
        .single();
      if (stored.error) throw stored.error;
      assertEquals(stored.data.id, manualId);
      assertEquals(stored.data.weight, 130);
      assertEquals(stored.data.achieved_at, "2026-08-15");
      assertEquals(stored.data.deleted_at, null);
      assert(stored.data.updated_at != null);
    } finally {
      try {
        await tombstoneIsolatedGymTree(admin, [gymId]);
      } finally {
        Deno.env.get = originalGet;
      }
    }
  },
});
