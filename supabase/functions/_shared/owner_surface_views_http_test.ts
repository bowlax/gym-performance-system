/**
 * HTTP-level tests for owner raw-fact views via PostgREST.
 *
 * These are not helper-boolean tests: each case GETs /rest/v1/<view>
 * with a signed JWT. Member and coach must get zero rows; owner gets
 * gym-scoped raw facts only. A second gym must not leak.
 */
import { assertEquals, assert } from "jsr:@std/assert@1";
import { SignJWT } from "jsr:@panva/jose@6";
import { createClient } from "jsr:@supabase/supabase-js@2";

const VIEWS = [
  "owner_session_activity",
  "owner_set_detail",
  "owner_exercise_catalogue",
] as const;

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
  const url = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("API_URL") ??
    Deno.env.get("GYMPERF_SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    Deno.env.get("PUBLISHABLE_KEY") ??
    Deno.env.get("GYMPERF_SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const jwtSecret = Deno.env.get("JWT_SIGNING_SECRET") ??
    Deno.env.get("JWT_SECRET");
  if (!url || !anonKey || !serviceRoleKey || !jwtSecret) {
    return null;
  }
  return {
    url: unquote(url).replace(/\/$/, ""),
    anonKey: unquote(anonKey),
    serviceRoleKey: unquote(serviceRoleKey),
    jwtSecret: unquote(jwtSecret),
  };
}

async function mintJwt(
  secret: string,
  claims: {
    memberId: string;
    gymId: string;
    appRole: "member" | "coach" | "owner";
  },
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

async function restGet(
  env: LiveEnv,
  token: string,
  pathAndQuery: string,
): Promise<Response> {
  return await fetch(`${env.url}/rest/v1/${pathAndQuery}`, {
    method: "GET",
    headers: {
      apikey: env.anonKey,
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
      Prefer: "count=exact",
    },
  });
}

async function restPost(
  env: LiveEnv,
  token: string,
  view: string,
  body: unknown,
): Promise<Response> {
  return await fetch(`${env.url}/rest/v1/${view}`, {
    method: "POST",
    headers: {
      apikey: env.anonKey,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify(body),
  });
}

async function jsonRows(res: Response): Promise<Array<Record<string, unknown>>> {
  assertEquals(res.status, 200, await res.clone().text());
  const body = await res.json();
  assertEquals(Array.isArray(body), true);
  return body as Array<Record<string, unknown>>;
}

function assertNoNames(rows: Array<Record<string, unknown>>): void {
  const keys = new Set(rows.flatMap((row) => Object.keys(row)));
  assertEquals(keys.has("display_name"), false);
  assertEquals(keys.has("notes"), false);
}

Deno.test({
  name:
    "HTTP GET owner views: member/coach get zero rows; owner gets gym-scoped raw facts; other gym does not leak",
  ignore: liveEnv() == null,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const env = liveEnv();
    if (!env) throw new Error("live env disappeared");

    const admin = createClient(env.url, env.serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const gymA = crypto.randomUUID();
    const gymB = crypto.randomUUID();
    const memberA = crypto.randomUUID();
    const memberB = crypto.randomUUID();
    const memberC = crypto.randomUUID();
    const memberCaller = crypto.randomUUID();
    const coachCaller = crypto.randomUUID();
    const ownerA = crypto.randomUUID();
    const ownerB = crypto.randomUUID();
    const pressA = crypto.randomUUID();
    const squatA = crypto.randomUUID();
    const pressB = crypto.randomUUID();
    const sessionA1 = crypto.randomUUID();
    const sessionA2 = crypto.randomUUID();
    const sessionB1 = crypto.randomUUID();
    const sessionDeleted = crypto.randomUUID();
    const sessionC = crypto.randomUUID();
    const entryA1 = crypto.randomUUID();
    const entryA2 = crypto.randomUUID();
    const entryB1 = crypto.randomUUID();
    const entryDeleted = crypto.randomUUID();
    const entryC = crypto.randomUUID();
    const setA1 = crypto.randomUUID();
    const setA2 = crypto.randomUUID();
    const setB1 = crypto.randomUUID();
    const setDeleted = crypto.randomUUID();
    const setC = crypto.randomUUID();

    const throwIf = (error: { message?: string } | null, label: string) => {
      if (error) throw new Error(`${label}: ${error.message}`);
    };

    try {
      throwIf(
        (await admin.from("gyms").insert([
          {
            id: gymA,
            teamup_provider_id: `view-a-${gymA.slice(0, 8)}`,
            name: "Owner View Gym A",
          },
          {
            id: gymB,
            teamup_provider_id: `view-b-${gymB.slice(0, 8)}`,
            name: "Owner View Gym B",
          },
        ])).error,
        "gyms",
      );

      throwIf(
        (await admin.from("members").insert([
          {
            id: memberA,
            gym_id: gymA,
            teamup_customer_id: "VIEW-A",
            display_name: "Lee Secret",
          },
          {
            id: memberB,
            gym_id: gymA,
            teamup_customer_id: "VIEW-B",
            display_name: "Member B Secret",
          },
          {
            id: memberCaller,
            gym_id: gymA,
            teamup_customer_id: "VIEW-CALLER",
            display_name: "Caller Secret",
          },
          {
            id: coachCaller,
            gym_id: gymA,
            teamup_customer_id: "VIEW-COACH",
            display_name: "Coach Secret",
          },
          {
            id: memberC,
            gym_id: gymB,
            teamup_customer_id: "VIEW-C",
            display_name: "Other Gym Secret",
          },
        ])).error,
        "members",
      );

      throwIf(
        (await admin.from("exercises").insert([
          {
            id: pressA,
            gym_id: gymA,
            name: "45-degree dumbbell press",
            category: "pbExercise",
            measurement_type: "weightAndReps",
            pb_rule: "heaviestWeightAtReps",
            target_reps: 8,
            display_order: 1,
            is_active: true,
          },
          {
            id: squatA,
            gym_id: gymA,
            name: "Split squat",
            category: "pbExercise",
            measurement_type: "weightAndReps",
            pb_rule: "heaviestWeightAtReps",
            target_reps: 8,
            display_order: 2,
            is_active: false,
          },
          {
            id: pressB,
            gym_id: gymB,
            name: "Other gym press",
            category: "pbExercise",
            measurement_type: "weightAndReps",
            pb_rule: "heaviestWeightAtReps",
            target_reps: 5,
            display_order: 1,
            is_active: true,
          },
        ])).error,
        "exercises",
      );

      throwIf(
        (await admin.from("sessions").insert([
          {
            id: sessionA1,
            gym_id: gymA,
            member_id: memberA,
            date: "2026-07-02",
            calories_burned: 420,
          },
          { id: sessionA2, gym_id: gymA, member_id: memberA, date: "2026-08-15" },
          { id: sessionB1, gym_id: gymA, member_id: memberB, date: "2026-08-20" },
          {
            id: sessionDeleted,
            gym_id: gymA,
            member_id: memberA,
            date: "2026-08-01",
            deleted_at: "2026-08-02T00:00:00Z",
          },
          { id: sessionC, gym_id: gymB, member_id: memberC, date: "2026-08-10" },
        ])).error,
        "sessions",
      );

      throwIf(
        (await admin.from("exercise_entries").insert([
          { id: entryA1, gym_id: gymA, session_id: sessionA1, exercise_id: pressA },
          { id: entryA2, gym_id: gymA, session_id: sessionA2, exercise_id: pressA },
          { id: entryB1, gym_id: gymA, session_id: sessionB1, exercise_id: squatA },
          {
            id: entryDeleted,
            gym_id: gymA,
            session_id: sessionDeleted,
            exercise_id: pressA,
          },
          { id: entryC, gym_id: gymB, session_id: sessionC, exercise_id: pressB },
        ])).error,
        "entries",
      );

      throwIf(
        (await admin.from("sets").insert([
          {
            id: setA1,
            gym_id: gymA,
            exercise_entry_id: entryA1,
            weight: 22.5,
            reps: 8,
          },
          {
            id: setA2,
            gym_id: gymA,
            exercise_entry_id: entryA2,
            weight: 25,
            reps: 8,
          },
          {
            id: setB1,
            gym_id: gymA,
            exercise_entry_id: entryB1,
            weight: 40,
            reps: 8,
          },
          {
            id: setDeleted,
            gym_id: gymA,
            exercise_entry_id: entryDeleted,
            weight: 99,
            reps: 8,
          },
          {
            id: setC,
            gym_id: gymB,
            exercise_entry_id: entryC,
            weight: 60,
            reps: 5,
          },
        ])).error,
        "sets",
      );

      const memberToken = await mintJwt(env.jwtSecret, {
        memberId: memberCaller,
        gymId: gymA,
        appRole: "member",
      });
      const coachToken = await mintJwt(env.jwtSecret, {
        memberId: coachCaller,
        gymId: gymA,
        appRole: "coach",
      });
      const ownerTokenA = await mintJwt(env.jwtSecret, {
        memberId: ownerA,
        gymId: gymA,
        appRole: "owner",
      });
      const ownerTokenB = await mintJwt(env.jwtSecret, {
        memberId: ownerB,
        gymId: gymB,
        appRole: "owner",
      });

      for (const view of VIEWS) {
        const memberRes = await restGet(env, memberToken, view);
        const memberRows = await jsonRows(memberRes);
        assertEquals(
          memberRows.length,
          0,
          `member JWT must get zero rows from ${view}`,
        );

        const coachRes = await restGet(env, coachToken, view);
        const coachRows = await jsonRows(coachRes);
        assertEquals(
          coachRows.length,
          0,
          `coach JWT must get zero rows from ${view}`,
        );

        const writeRes = await restPost(env, ownerTokenA, view, {});
        const writeBody = await writeRes.text();
        const writeRefused =
          writeRes.status === 401 ||
          writeRes.status === 403 ||
          writeRes.status === 405 ||
          (writeRes.status === 500 &&
            writeBody.includes("cannot insert into view"));
        assert(
          writeRefused,
          `POST ${view} must not write, got ${writeRes.status}: ${writeBody}`,
        );
      }

      const sessionsA = await jsonRows(
        await restGet(env, ownerTokenA, "owner_session_activity"),
      );
      assertNoNames(sessionsA);
      const sessionIds = new Set(sessionsA.map((row) => row.session_id));
      assertEquals(sessionIds.has(sessionA1), true);
      assertEquals(sessionIds.has(sessionA2), true);
      assertEquals(sessionIds.has(sessionB1), true);
      assertEquals(sessionIds.has(sessionDeleted), false);
      assertEquals(sessionIds.has(sessionC), false);
      assertEquals(sessionsA.length, 3);
      const sessionsById = new Map(
        sessionsA.map((row) => [row.session_id, row]),
      );
      const withCalories = sessionsById.get(sessionA1);
      const withoutCalories = sessionsById.get(sessionA2);
      assertEquals("calories_burned" in (withCalories ?? {}), true);
      assertEquals(withCalories?.calories_burned, 420);
      assertEquals("calories_burned" in (withoutCalories ?? {}), true);
      assertEquals(withoutCalories?.calories_burned, null);
      for (const row of sessionsA) {
        assertEquals(row.gym_id, gymA);
        assertEquals(typeof row.member_id, "string");
        assertEquals(
          row.member_id === ownerA || typeof row.display_name === "string",
          false,
        );
      }

      const periodRows = await jsonRows(
        await restGet(
          env,
          ownerTokenA,
          `owner_session_activity?member_id=eq.${memberA}&session_date=gte.2026-07-01&session_date=lte.2026-07-31`,
        ),
      );
      assertEquals(periodRows.length, 1);
      assertEquals(periodRows[0].session_id, sessionA1);
      assertEquals(periodRows[0].teamup_customer_id, "VIEW-A");
      assertEquals(periodRows[0].session_date, "2026-07-02");

      const setsA = await jsonRows(
        await restGet(env, ownerTokenA, "owner_set_detail"),
      );
      assertNoNames(setsA);
      const setIds = new Set(setsA.map((row) => row.set_id));
      assertEquals(setIds.has(setA1), true);
      assertEquals(setIds.has(setA2), true);
      assertEquals(setIds.has(setB1), true);
      assertEquals(setIds.has(setDeleted), false);
      assertEquals(setIds.has(setC), false);
      assertEquals(setsA.length, 3);
      assertEquals(
        setsA.some((row) => JSON.stringify(row).includes("Lee Secret")),
        false,
      );

      const pressHistory = await jsonRows(
        await restGet(
          env,
          ownerTokenA,
          `owner_set_detail?member_id=eq.${memberA}&exercise_id=eq.${pressA}&session_date=gte.2026-07-01&session_date=lte.2026-09-30&order=session_date.asc`,
        ),
      );
      assertEquals(pressHistory.length, 2);
      assertEquals(pressHistory[0].weight, 22.5);
      assertEquals(pressHistory[0].reps, 8);
      assertEquals(pressHistory[0].session_date, "2026-07-02");
      assertEquals(pressHistory[1].weight, 25);
      assertEquals(pressHistory[1].session_date, "2026-08-15");
      assertEquals(pressHistory[0].teamup_customer_id, "VIEW-A");

      const catalogueA = await jsonRows(
        await restGet(env, ownerTokenA, "owner_exercise_catalogue"),
      );
      const catalogueIds = new Set(catalogueA.map((row) => row.exercise_id));
      assertEquals(catalogueIds.has(pressA), true);
      assertEquals(catalogueIds.has(squatA), true);
      assertEquals(catalogueIds.has(pressB), false);
      const pressRow = catalogueA.find((row) => row.exercise_id === pressA);
      assert(pressRow != null);
      assertEquals(pressRow.name, "45-degree dumbbell press");
      assertEquals(pressRow.is_active, true);
      const squatRow = catalogueA.find((row) => row.exercise_id === squatA);
      assert(squatRow != null);
      assertEquals(squatRow.is_active, false);

      const sessionsB = await jsonRows(
        await restGet(env, ownerTokenB, "owner_session_activity"),
      );
      assertEquals(sessionsB.length, 1);
      assertEquals(sessionsB[0].session_id, sessionC);
      assertEquals(sessionsB[0].member_id, memberC);
      assertEquals(sessionsB[0].gym_id, gymB);

      const setsB = await jsonRows(
        await restGet(env, ownerTokenB, "owner_set_detail"),
      );
      assertEquals(setsB.length, 1);
      assertEquals(setsB[0].set_id, setC);
      assertEquals(setsB[0].weight, 60);

      const catalogueB = await jsonRows(
        await restGet(env, ownerTokenB, "owner_exercise_catalogue"),
      );
      assertEquals(catalogueB.length, 1);
      assertEquals(catalogueB[0].exercise_id, pressB);

      const anonRes = await fetch(
        `${env.url}/rest/v1/owner_session_activity`,
        {
          headers: {
            apikey: env.anonKey,
            Authorization: `Bearer ${env.anonKey}`,
            Accept: "application/json",
          },
        },
      );
      assert(
        anonRes.status === 401 || anonRes.status === 403,
        `anon must not read owner views, got ${anonRes.status}`,
      );
    } finally {
      await admin.from("sets").delete().in("id", [
        setA1,
        setA2,
        setB1,
        setDeleted,
        setC,
      ]);
      await admin.from("exercise_entries").delete().in("id", [
        entryA1,
        entryA2,
        entryB1,
        entryDeleted,
        entryC,
      ]);
      await admin.from("sessions").delete().in("id", [
        sessionA1,
        sessionA2,
        sessionB1,
        sessionDeleted,
        sessionC,
      ]);
      await admin.from("exercises").delete().in("id", [pressA, squatA, pressB]);
      await admin.from("members").delete().in("id", [
        memberA,
        memberB,
        memberC,
        memberCaller,
        coachCaller,
      ]);
      await admin.from("owner_surface_grants").delete().in("gym_id", [gymA, gymB]);
      await admin.from("gyms").delete().in("id", [gymA, gymB]);
    }
  },
});
