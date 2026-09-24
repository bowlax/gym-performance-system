/**
 * HTTP tests for the gym kiosk.
 *
 * Routing tests always run. Live tests need loopback Supabase: a pending row
 * is absent from member, owner, and sync reads, does not expire, and confirm
 * writes one normal session those reads then see.
 */
import { assert, assertEquals } from "jsr:@std/assert@1";
import { SignJWT } from "jsr:@panva/jose@6";
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { handleOwnerCurrentPBsRequest } from "../owner-current-pbs/handler.ts";
import { handleOwnerPbFrequencyRequest } from "../owner-pb-frequency/handler.ts";
import {
  onlyIfLoopback,
  throwIfPostgrestError,
  tombstoneIsolatedGymTree,
} from "../_shared/test-isolated-gym-teardown.ts";
import { handleKioskLogRequest } from "./handler.ts";

const ENDPOINT = "http://localhost/functions/v1/kiosk-log";

Deno.test("kiosk-log POST without a token is 401", async () => {
  const res = await handleKioskLogRequest(
    new Request(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "members" }),
    }),
  );
  assertEquals(res.status, 401);
});

Deno.test("kiosk-log GET on the owner path is 405", async () => {
  const res = await handleKioskLogRequest(new Request(ENDPOINT, { method: "GET" }));
  assertEquals(res.status, 405);
});

Deno.test("kiosk confirm without a token is 404 and does not write a session", async () => {
  const res = await handleKioskLogRequest(
    new Request(`${ENDPOINT}/confirm`, { method: "GET" }),
  );
  assertEquals(res.status, 404);
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
  if (!url || !anonKey || !serviceRoleKey || !jwtSecret) return null;
  return onlyIfLoopback({ url, anonKey, serviceRoleKey, jwtSecret });
}

async function mintJwt(
  secret: string,
  claims: { memberId: string; gymId: string; appRole: "member" | "owner" },
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

function userClient(env: LiveEnv, token: string): SupabaseClient {
  return createClient(env.url, env.anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function countRows(
  client: SupabaseClient,
  table: string,
  column: string,
  value: string,
): Promise<number> {
  const { data, error } = await client.from(table).select("id").eq(column, value);
  throwIfPostgrestError(`${table} ${column}`, error);
  return data?.length ?? 0;
}

Deno.test({
  name: "pending kiosk log is invisible until confirm, and an old unconfirmed row does not expire",
  ignore: liveEnv() == null,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const env = liveEnv();
    if (!env) throw new Error("live env disappeared");

    const originalGet = Deno.env.get.bind(Deno.env);
    Deno.env.get = (name: string) => {
      if (name === "SUPABASE_URL") return env.url;
      if (name === "SUPABASE_ANON_KEY" || name === "SUPABASE_PUBLISHABLE_KEY") {
        return env.anonKey;
      }
      if (name === "SERVICE_ROLE_KEY") return env.serviceRoleKey;
      if (name === "JWT_SIGNING_SECRET") return env.jwtSecret;
      if (name === "MEMBER_WEB_ORIGIN") return "https://gym.example";
      if (name === "RESEND_API_KEY") return "re_test_key";
      return originalGet(name);
    };

    const admin = createClient(env.url, env.serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const gymId = crypto.randomUUID();
    const ownerId = crypto.randomUUID();
    const adaId = crypto.randomUUID();
    const graceId = crypto.randomUUID();
    const jwtOnlyId = crypto.randomUUID();
    const unnamedId = crypto.randomUUID();
    const noEmailId = crypto.randomUUID();
    const exerciseId = crypto.randomUUID();
    const providerId = `kiosk-${gymId.slice(0, 8)}`;
    const sent: Array<{ to: string[]; text: string }> = [];

    const fetchImpl: typeof fetch = async (_input, init) => {
      const body = JSON.parse(String(init?.body)) as { to: string[]; text: string };
      sent.push(body);
      return new Response(JSON.stringify({ id: "email" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    };

    try {
      throwIfPostgrestError(
        "gym",
        (await admin.from("gyms").insert({
          id: gymId,
          teamup_provider_id: providerId,
          name: "Kiosk Test Gym",
        })).error,
      );
      throwIfPostgrestError(
        "members",
        (await admin.from("members").insert([
          {
            id: ownerId,
            gym_id: gymId,
            teamup_customer_id: `kiosk-owner-${gymId.slice(0, 8)}`,
            display_name: "Owner Caller",
          },
          {
            id: adaId,
            gym_id: gymId,
            teamup_customer_id: `kiosk-ada-${gymId.slice(0, 8)}`,
            display_name: "Ada Lovelace",
            teamup_email: "ada@example.com",
            teamup_roster_id: "1001",
          },
          {
            id: graceId,
            gym_id: gymId,
            teamup_customer_id: `kiosk-grace-${gymId.slice(0, 8)}`,
            display_name: "Grace Hopper",
            teamup_email: "grace@example.com",
            teamup_roster_id: "1002",
          },
          {
            id: jwtOnlyId,
            gym_id: gymId,
            teamup_customer_id: `kiosk-jwt-${gymId.slice(0, 8)}`,
            display_name: "Jwt Only",
            teamup_email: "jwt@example.com",
          },
          {
            id: unnamedId,
            gym_id: gymId,
            teamup_customer_id: `kiosk-unnamed-${gymId.slice(0, 8)}`,
            display_name: "Member",
            teamup_email: "unnamed@example.com",
            teamup_roster_id: "1003",
          },
          {
            id: noEmailId,
            gym_id: gymId,
            teamup_customer_id: `kiosk-noemail-${gymId.slice(0, 8)}`,
            display_name: "No Email",
            teamup_roster_id: "1004",
          },
        ])).error,
      );
      throwIfPostgrestError(
        "exercise",
        (await admin.from("exercises").insert({
          id: exerciseId,
          gym_id: gymId,
          name: "Back Squat",
          category: "pbExercise",
          measurement_type: "weightAndReps",
          pb_rule: "heaviestWeightAtReps",
          target_reps: 5,
          display_order: 1,
          is_active: true,
        })).error,
      );

      const ownerToken = await mintJwt(env.jwtSecret, {
        memberId: ownerId,
        gymId,
        appRole: "owner",
      });
      const adaToken = await mintJwt(env.jwtSecret, {
        memberId: adaId,
        gymId,
        appRole: "member",
      });
      const graceToken = await mintJwt(env.jwtSecret, {
        memberId: graceId,
        gymId,
        appRole: "member",
      });
      const owner = userClient(env, ownerToken);
      const ada = userClient(env, adaToken);
      const grace = userClient(env, graceToken);

      const memberListDenied = await handleKioskLogRequest(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${adaToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ action: "members" }),
        }),
      );
      assertEquals(memberListDenied.status, 403);

      const listed = await handleKioskLogRequest(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ownerToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ action: "members" }),
        }),
      );
      assertEquals(listed.status, 200);
      const listedBody = await listed.json() as {
        members: Array<{ member_id: string; display_name: string }>;
      };
      const listedIds = listedBody.members.map((row) => row.member_id).sort();
      assertEquals(listedIds, [adaId, graceId].sort());
      assert(
        listedBody.members.every((row) => !("teamup_email" in row)),
      );

      const multi = await handleKioskLogRequest(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ownerToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            action: "submit",
            memberId: adaId,
            session: { date: "2026-09-24" },
            exercises: [{
              exerciseId,
              sets: [{ weight: 80, reps: 5 }, { weight: 100, reps: 5 }],
            }],
          }),
        }),
        { fetchImpl },
      );
      assertEquals(multi.status, 400);
      assertEquals(sent.length, 0);
      assertEquals(await countRows(admin, "sessions", "member_id", adaId), 0);

      async function submit(memberId: string, weight: number) {
        const res = await handleKioskLogRequest(
          new Request(ENDPOINT, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${ownerToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              action: "submit",
              memberId,
              session: { date: "2026-09-24", notes: "kiosk", calories_burned: 80 },
              exercises: [{
                exerciseId,
                sets: [{ weight, reps: 5 }],
              }],
            }),
          }),
          { fetchImpl },
        );
        assertEquals(res.status, 200);
      }

      await submit(adaId, 100);
      await submit(graceId, 90);
      assertEquals(sent.length, 2);
      assertEquals(sent[0]?.to, ["ada@example.com"]);
      assert(sent[0]?.text.includes("Back Squat: 100 kg, 5 reps"));
      assertEquals(sent[1]?.to, ["grace@example.com"]);
      assert(sent[1]?.text.includes("Back Squat: 90 kg, 5 reps"));

      throwIfPostgrestError(
        "backdate pending",
        (await admin
          .from("kiosk_pending_sessions")
          .update({ created_at: "2000-01-01T00:00:00Z" })
          .in("member_id", [adaId, graceId])).error,
      );

      async function assertInvisible(memberId: string, member: SupabaseClient) {
        assertEquals(await countRows(admin, "sessions", "member_id", memberId), 0);
        assertEquals(await countRows(admin, "personal_bests", "member_id", memberId), 0);
        assertEquals(await countRows(member, "sessions", "member_id", memberId), 0);
        const sync = await member
          .from("sessions")
          .select("id")
          .eq("member_id", memberId)
          .not("synced_at", "is", null);
        throwIfPostgrestError("sync sessions", sync.error);
        assertEquals(sync.data?.length ?? 0, 0);
        const entries = await member
          .from("exercise_entries")
          .select("id, session:sessions!inner(member_id)")
          .eq("session.member_id", memberId);
        throwIfPostgrestError("member entries", entries.error);
        assertEquals(entries.data?.length ?? 0, 0);
        const activity = await owner
          .from("owner_session_activity")
          .select("session_id")
          .eq("member_id", memberId);
        throwIfPostgrestError("owner activity", activity.error);
        assertEquals(activity.data?.length ?? 0, 0);
        const detail = await owner
          .from("owner_set_detail")
          .select("set_id")
          .eq("member_id", memberId);
        throwIfPostgrestError("owner sets", detail.error);
        assertEquals(detail.data?.length ?? 0, 0);
        const hidden = await member.from("kiosk_pending_sessions").select("id");
        if (!hidden.error) assertEquals(hidden.data?.length ?? 0, 0);
        const ownerHidden = await owner.from("kiosk_pending_sessions").select("id");
        if (!ownerHidden.error) assertEquals(ownerHidden.data?.length ?? 0, 0);
      }

      await assertInvisible(adaId, ada);
      await assertInvisible(graceId, grace);
      assertEquals(await countRows(admin, "kiosk_pending_sessions", "member_id", adaId), 1);

      const pbsBefore = await handleOwnerCurrentPBsRequest(
        new Request("http://localhost/functions/v1/owner-current-pbs", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ownerToken}`,
            "Content-Type": "application/json",
          },
          body: "{}",
        }),
      );
      assertEquals(pbsBefore.status, 200);
      const pbsBeforeBody = await pbsBefore.json() as {
        currentPBs: Array<{ member_id: string }>;
      };
      assertEquals(
        pbsBeforeBody.currentPBs.filter((row) => row.member_id === adaId).length,
        0,
      );

      const freqBefore = await handleOwnerPbFrequencyRequest(
        new Request("http://localhost/functions/v1/owner-pb-frequency", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ownerToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ from: "2026-09-01", to: "2026-09-30" }),
        }),
      );
      assertEquals(freqBefore.status, 200);
      const freqBeforeBody = await freqBefore.json() as {
        members: Array<{ member_id: string }>;
      };
      assertEquals(
        freqBeforeBody.members.filter((row) => row.member_id === adaId).length,
        0,
      );

      const tokenMatch = sent[0]?.text.match(/token=([^\s]+)/);
      assert(tokenMatch?.[1]);
      const confirm = await handleKioskLogRequest(
        new Request(
          `${ENDPOINT}/confirm?token=${tokenMatch[1]}`,
          { method: "GET" },
        ),
      );
      assertEquals(confirm.status, 200);
      const confirmBody = await confirm.json() as { ok?: boolean; sessionId?: string };
      assertEquals(confirmBody.ok, true);
      assert(typeof confirmBody.sessionId === "string");

      const again = await handleKioskLogRequest(
        new Request(
          `${ENDPOINT}/confirm?token=${tokenMatch[1]}`,
          { method: "GET" },
        ),
      );
      assertEquals(again.status, 404);
      assertEquals(await countRows(admin, "sessions", "member_id", adaId), 1);

      const live = await admin
        .from("sessions")
        .select("id, member_id, date, notes, calories_burned, synced_at, deleted_at")
        .eq("member_id", adaId)
        .single();
      throwIfPostgrestError("live session", live.error);
      assertEquals(live.data?.member_id, adaId);
      assertEquals(live.data?.date, "2026-09-24");
      assertEquals(live.data?.notes, "kiosk");
      assertEquals(live.data?.calories_burned, 80);
      assertEquals(live.data?.deleted_at, null);
      assert(typeof live.data?.synced_at === "string");

      const syncAfter = await ada
        .from("sessions")
        .select("id")
        .eq("member_id", adaId)
        .not("synced_at", "is", null);
      throwIfPostgrestError("sync after", syncAfter.error);
      assertEquals(syncAfter.data?.length, 1);

      const activityAfter = await owner
        .from("owner_session_activity")
        .select("session_id")
        .eq("member_id", adaId);
      throwIfPostgrestError("activity after", activityAfter.error);
      assertEquals(activityAfter.data?.length, 1);

      const detailAfter = await owner
        .from("owner_set_detail")
        .select("weight, reps")
        .eq("member_id", adaId);
      throwIfPostgrestError("detail after", detailAfter.error);
      assertEquals(detailAfter.data, [{ weight: 100, reps: 5 }]);

      const pbsAfter = await handleOwnerCurrentPBsRequest(
        new Request("http://localhost/functions/v1/owner-current-pbs", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ownerToken}`,
            "Content-Type": "application/json",
          },
          body: "{}",
        }),
      );
      const pbsAfterBody = await pbsAfter.json() as {
        currentPBs: Array<{ member_id: string; exercise_id: string; value: number }>;
      };
      const adaPb = pbsAfterBody.currentPBs.find((row) => row.member_id === adaId);
      assertEquals(adaPb?.exercise_id, exerciseId);
      assertEquals(adaPb?.value, 100);

      const freqAfter = await handleOwnerPbFrequencyRequest(
        new Request("http://localhost/functions/v1/owner-pb-frequency", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ownerToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ from: "2026-09-01", to: "2026-09-30" }),
        }),
      );
      const freqAfterBody = await freqAfter.json() as {
        members: Array<{ member_id: string; count: number }>;
      };
      assertEquals(
        freqAfterBody.members.find((row) => row.member_id === adaId)?.count,
        1,
      );

      assertEquals(await countRows(admin, "kiosk_pending_sessions", "member_id", adaId), 0);
      assertEquals(await countRows(admin, "sessions", "member_id", graceId), 0);
      const gracePending = await admin
        .from("kiosk_pending_sessions")
        .select("created_at")
        .eq("member_id", graceId)
        .single();
      throwIfPostgrestError("grace pending", gracePending.error);
      assert(String(gracePending.data?.created_at).startsWith("2000-01-01"));
    } finally {
      Deno.env.get = originalGet;
      await admin.from("kiosk_pending_sessions").delete().eq("gym_id", gymId);
      await tombstoneIsolatedGymTree(admin, [gymId]);
    }
  },
});
