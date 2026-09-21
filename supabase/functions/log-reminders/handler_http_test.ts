/**
 * HTTP-level tests for log-reminders (job + public unsubscribe).
 *
 * Routing, copy, token, and the London hour gate always run.
 * Eligibility / backoff / opt-out go through handleLogRemindersRequest
 * against loopback PostgREST with TeamUp + Resend mocked.
 */
import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleLogRemindersRequest } from "./handler.ts";
import { buildReminderCopy, WOLF_LOGO_URL } from "../_shared/log-reminder-copy.ts";
import {
  signLogReminderOptOutToken,
  verifyLogReminderOptOutToken,
} from "../_shared/log-reminder-token.ts";
import {
  onlyIfLoopback,
  tombstoneIsolatedGymTree,
} from "../_shared/test-isolated-gym-teardown.ts";

const JOB = "http://localhost/functions/v1/log-reminders";
const UNSUB = "http://localhost/functions/v1/log-reminders/unsubscribe";
const CRON_SECRET = "cron-secret-for-log-reminders-tests-32ch";
const UNSUB_SECRET = "unsub-secret-for-log-reminders-tests-32ch";
const MEMBER_WEB = "https://member.test";

const MORNING_BST = "2026-07-15T08:00:00.000Z"; // 09:00 London
const TEN_BST = "2026-07-15T09:00:00.000Z"; // 10:00 London
const LUNCH_BST = "2026-07-15T13:00:00.000Z"; // 14:00 London
const EVENING_BST = "2026-07-15T20:00:00.000Z"; // 21:00 London

interface LiveEnv {
  url: string;
  anonKey: string;
  serviceRoleKey: string;
}

function liveEnv(): LiveEnv | null {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceRoleKey) return null;
  return onlyIfLoopback({ url, anonKey, serviceRoleKey });
}

function jobRequest(now: string, secret = CRON_SECRET): Request {
  return new Request(JOB, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${secret}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ now }),
  });
}

Deno.test("HTTP GET log-reminders returns 405", async () => {
  const res = await handleLogRemindersRequest(new Request(JOB, { method: "GET" }));
  assertEquals(res.status, 405);
});

Deno.test("HTTP POST without cron secret returns 401", async () => {
  const res = await handleLogRemindersRequest(
    new Request(JOB, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" }),
  );
  assertEquals(res.status, 401);
});

Deno.test("HTTP POST with the wrong cron secret returns 401", async () => {
  const originalGet = Deno.env.get.bind(Deno.env);
  Deno.env.get = (name: string) => {
    if (name === "LOG_REMINDER_CRON_SECRET") return CRON_SECRET;
    return originalGet(name);
  };
  try {
    const res = await handleLogRemindersRequest(jobRequest(MORNING_BST, "nope"));
    assertEquals(res.status, 401);
  } finally {
    Deno.env.get = originalGet;
  }
});

Deno.test("HTTP OPTIONS log-reminders returns 200", async () => {
  const res = await handleLogRemindersRequest(
    new Request(JOB, { method: "OPTIONS" }),
  );
  assertEquals(res.status, 200);
});

Deno.test("copy variants: morning, lunch, evening, and multi-class times", () => {
  const logUrl = "https://member.test/log";
  const unsub = "https://member.test/reminders/unsubscribe?token=t";
  const morning = buildReminderCopy(
    "morning",
    [{ name: "Hyrox", startsAt: "2026-07-15T07:15:00.000Z" }],
    logUrl,
    unsub,
    "Lee Ball",
  );
  assertEquals(morning.subject, "Log your Wolf morning session");
  assertEquals(morning.greeting, "Hi Lee,");
  assertStringIncludes(morning.text, "Hi Lee,");
  assertStringIncludes(morning.text, "You were booked in this morning (Hyrox at 8:15).");
  assertStringIncludes(morning.text, "booked");
  assertEquals(morning.text.includes("trained"), false);
  assertEquals(morning.text.includes("skipped"), false);
  assertStringIncludes(morning.text, unsub);
  assertStringIncludes(morning.html, unsub);
  assertStringIncludes(morning.html, "Log session");
  assertStringIncludes(morning.html, logUrl);
  assertStringIncludes(morning.html, "Hi Lee,");
  assertStringIncludes(morning.html, WOLF_LOGO_URL);

  const lunch = buildReminderCopy("lunch", [], logUrl, unsub, "Ada Lovelace");
  assertEquals(lunch.subject, "Log your Wolf lunch session");
  assertStringIncludes(lunch.text, "Hi Ada,");
  assertStringIncludes(lunch.text, "You were booked in at lunch.");

  const evening = buildReminderCopy(
    "evening",
    [{ name: "WOD", startsAt: "2026-07-15T18:40:00.000Z" }],
    logUrl,
    unsub,
    null,
  );
  assertEquals(evening.subject, "Log your Wolf evening session");
  assertEquals(evening.greeting, "Hi,");
  assertStringIncludes(evening.text, "You were booked in this evening (WOD at 19:40).");

  const multi = buildReminderCopy(
    "morning",
    [
      { name: "A", startsAt: "2026-07-15T07:15:00.000Z" },
      { name: "B", startsAt: "2026-07-15T11:00:00.000Z" },
    ],
    logUrl,
    unsub,
    "Lee Ball",
  );
  assertStringIncludes(multi.text, "this morning (8:15 and 12:00)");
});

Deno.test("opt-out token verifies and rejects a tampered payload", async () => {
  const memberId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
  const token = await signLogReminderOptOutToken(memberId, UNSUB_SECRET);
  assertEquals((await verifyLogReminderOptOutToken(token, UNSUB_SECRET)).memberId, memberId);
  const parts = token.split(".");
  const tampered = `${parts[0]}.${parts[1]}x.${parts[2]}`;
  let rejected = false;
  try {
    await verifyLogReminderOptOutToken(tampered, UNSUB_SECRET);
  } catch {
    rejected = true;
  }
  assertEquals(rejected, true);
});

function attendance(row: {
  rosterId: number;
  email: string;
  status: string;
  name: string;
  startsAt: string;
  endsAt: string;
}) {
  return {
    customer: { id: row.rosterId, email: row.email },
    status: row.status,
    event: {
      name: row.name,
      starts_at: row.startsAt,
      ends_at: row.endsAt,
    },
  };
}

interface Harness {
  gymId: string;
  memberId: string;
  email: string;
  rosterId: string;
  providerId: string;
  sent: unknown[];
  attendances: unknown[];
  restore: () => Promise<void>;
}

async function startLiveHarness(): Promise<Harness | null> {
  const env = liveEnv();
  if (!env) return null;

  const originalGet = Deno.env.get.bind(Deno.env);
  const originalFetch = globalThis.fetch;
  const gymId = crypto.randomUUID();
  const memberId = crypto.randomUUID();
  const email = `reminder-${gymId.slice(0, 8)}@example.com`;
  const rosterId = String(8_000_000 + (Number.parseInt(gymId.slice(0, 6), 16) % 100_000));
  const providerId = `log-rem-${gymId.slice(0, 8)}`;
  const sent: unknown[] = [];
  const attendances: unknown[] = [];

  Deno.env.get = (name: string) => {
    if (name === "SUPABASE_URL") return env.url;
    if (name === "SUPABASE_ANON_KEY") return env.anonKey;
    if (name === "SUPABASE_PUBLISHABLE_KEY") return env.anonKey;
    if (name === "SERVICE_ROLE_KEY") return env.serviceRoleKey;
    if (name === "TEAMUP_M2M_TOKEN") return "test-m2m-token";
    if (name === "TEAMUP_OAUTH_PROVIDER_ID") return providerId;
    if (name === "RESEND_API_KEY") return "re_test_key";
    if (name === "MEMBER_WEB_ORIGIN") return MEMBER_WEB;
    if (name === "LOG_REMINDER_CRON_SECRET") return CRON_SECRET;
    if (name === "LOG_REMINDER_UNSUBSCRIBE_SECRET") return UNSUB_SECRET;
    return originalGet(name);
  };

  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    if (url.hostname === "goteamup.com" && url.pathname.endsWith("/customers")) {
      return new Response(JSON.stringify({ count: 0, next: null, results: [] }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
    if (url.hostname === "goteamup.com" && url.pathname.endsWith("/attendances")) {
      return new Response(
        JSON.stringify({ count: attendances.length, next: null, results: attendances }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }
    if (url.hostname === "api.resend.com") {
      sent.push(JSON.parse(String(init?.body ?? "{}")));
      return new Response(JSON.stringify({ id: "re_test" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
    return await originalFetch(input, init);
  };

  const admin = createClient(env.url, env.serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const gymInsert = await admin.from("gyms").insert({
    id: gymId,
    teamup_provider_id: providerId,
    name: "Log Reminder Test Gym",
  });
  if (gymInsert.error) throw gymInsert.error;
  const memberInsert = await admin.from("members").insert({
    id: memberId,
    gym_id: gymId,
    teamup_customer_id: `oauth-${rosterId}`,
    teamup_roster_id: rosterId,
    teamup_email: email,
    display_name: "Reminder Member",
  });
  if (memberInsert.error) throw memberInsert.error;

  return {
    gymId,
    memberId,
    email,
    rosterId,
    providerId,
    sent,
    attendances,
    restore: async () => {
      globalThis.fetch = originalFetch;
      try {
        await tombstoneIsolatedGymTree(admin, [gymId]);
      } finally {
        Deno.env.get = originalGet;
      }
    },
  };
}

Deno.test("HTTP POST test_to sends one email to an lbconsulting address", async () => {
  const originalGet = Deno.env.get.bind(Deno.env);
  const originalFetch = globalThis.fetch;
  const sent: unknown[] = [];
  Deno.env.get = (name: string) => {
    if (name === "LOG_REMINDER_CRON_SECRET") return CRON_SECRET;
    if (name === "RESEND_API_KEY") return "re_test_key";
    if (name === "MEMBER_WEB_ORIGIN") return MEMBER_WEB;
    if (name === "LOG_REMINDER_UNSUBSCRIBE_SECRET") return UNSUB_SECRET;
    return originalGet(name);
  };
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    if (url.hostname === "api.resend.com") {
      sent.push(JSON.parse(String(init?.body ?? "{}")));
      return new Response(JSON.stringify({ id: "re_live_test" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
    return await originalFetch(input, init);
  };
  try {
    const member = await handleLogRemindersRequest(
      new Request(JOB, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${CRON_SECRET}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ test_to: "member@wolf.example" }),
      }),
    );
    assertEquals(member.status, 400);
    assertEquals(sent.length, 0);

    const res = await handleLogRemindersRequest(
      new Request(JOB, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${CRON_SECRET}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ test_to: "privacy@lbconsulting.tech" }),
      }),
    );
    assertEquals(res.status, 200);
    const body = await res.json() as { test?: boolean; to?: string; id?: string };
    assertEquals(body.test, true);
    assertEquals(body.to, "privacy@lbconsulting.tech");
    assertEquals(body.id, "re_live_test");
    const first = sent[0] as {
      from: string;
      to: string[];
      subject: string;
      html: string;
      headers: Record<string, string>;
    };
    assertEquals(first.from, "Wolf Reminders <reminders@lbconsulting.tech>");
    assertEquals(first.to, ["privacy@lbconsulting.tech"]);
    assertEquals(first.subject, "Log your Wolf morning session");
    assertStringIncludes(first.html, "Hi Lee,");
    assertStringIncludes(first.html, "Log session");
    assertEquals(first.headers["List-Unsubscribe-Post"], "List-Unsubscribe=One-Click");
  } finally {
    globalThis.fetch = originalFetch;
    Deno.env.get = originalGet;
  }
});

Deno.test("HTTP POST job skips a non-slot London hour without sending", async () => {
  const originalGet = Deno.env.get.bind(Deno.env);
  Deno.env.get = (name: string) => {
    if (name === "LOG_REMINDER_CRON_SECRET") return CRON_SECRET;
    return originalGet(name);
  };
  try {
    const res = await handleLogRemindersRequest(jobRequest(TEN_BST));
    assertEquals(res.status, 200);
    const body = await res.json() as { skipped?: Record<string, number>; sent?: number; slot?: string | null };
    assertEquals(body.sent, 0);
    assertEquals(body.slot, null);
    assertEquals(body.skipped?.not_slot_hour, 1);
  } finally {
    Deno.env.get = originalGet;
  }
});

Deno.test({
  name: "HTTP POST eligibility: ends_at gate, multi-class one email, already-sent-today, copy slots",
  ignore: liveEnv() == null,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const harness = await startLiveHarness();
    if (!harness) throw new Error("live env disappeared");
    const env = liveEnv()!;
    const admin = createClient(env.url, env.serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    try {
      const roster = Number(harness.rosterId);
      harness.attendances.splice(
        0,
        harness.attendances.length,
        attendance({
          rosterId: roster,
          email: harness.email,
          status: "registered",
          name: "Late morning",
          startsAt: "2026-07-15T08:30:00.000Z",
          endsAt: "2026-07-15T09:00:00.000Z",
        }),
      );
      const tooEarly = await handleLogRemindersRequest(jobRequest(MORNING_BST));
      assertEquals(tooEarly.status, 200);
      const tooEarlyBody = await tooEarly.json() as { sent?: number; skipped?: Record<string, number> };
      assertEquals(tooEarlyBody.sent, 0);
      assertEquals(harness.sent.length, 0);

      harness.attendances.splice(
        0,
        harness.attendances.length,
        attendance({
          rosterId: roster,
          email: harness.email,
          status: "registered",
          name: "Hyrox",
          startsAt: "2026-07-15T07:15:00.000Z",
          endsAt: "2026-07-15T07:45:00.000Z",
        }),
      );
      const morning = await handleLogRemindersRequest(jobRequest(MORNING_BST));
      assertEquals(morning.status, 200);
      const morningBody = await morning.json() as { sent?: number; slot?: string };
      assertEquals(morningBody.sent, 1);
      assertEquals(morningBody.slot, "morning");
      const first = harness.sent[0] as {
        from: string;
        to: string[];
        subject: string;
        text: string;
        headers: Record<string, string>;
      };
      assertEquals(first.from, "Wolf Reminders <reminders@lbconsulting.tech>");
      assertEquals(first.to, [harness.email]);
      assertEquals(first.subject, "Log your Wolf morning session");
      assertStringIncludes(first.text, "You were booked in this morning (Hyrox at 8:15).");
      assertEquals(first.headers["List-Unsubscribe-Post"], "List-Unsubscribe=One-Click");
      assertStringIncludes(first.headers["List-Unsubscribe"], `${MEMBER_WEB}/reminders/unsubscribe?token=`);

      const again = await handleLogRemindersRequest(jobRequest(LUNCH_BST));
      assertEquals(again.status, 200);
      const againBody = await again.json() as { sent?: number; skipped?: Record<string, number> };
      assertEquals(againBody.sent, 0);
      assertEquals(againBody.skipped?.already_sent_today, 1);
      assertEquals(harness.sent.length, 1);

      const otherId = crypto.randomUUID();
      const otherEmail = `multi-${harness.gymId.slice(0, 8)}@example.com`;
      const otherRoster = String(Number(harness.rosterId) + 1);
      const otherInsert = await admin.from("members").insert({
        id: otherId,
        gym_id: harness.gymId,
        teamup_customer_id: `oauth-${otherRoster}`,
        teamup_roster_id: otherRoster,
        teamup_email: otherEmail,
        display_name: "Multi Class",
      });
      if (otherInsert.error) throw otherInsert.error;

      harness.attendances.splice(
        0,
        harness.attendances.length,
        attendance({
          rosterId: Number(otherRoster),
          email: otherEmail,
          status: "attended",
          name: "AM",
          startsAt: "2026-07-15T07:15:00.000Z",
          endsAt: "2026-07-15T07:45:00.000Z",
        }),
        attendance({
          rosterId: Number(otherRoster),
          email: otherEmail,
          status: "registered",
          name: "Noon",
          startsAt: "2026-07-15T11:00:00.000Z",
          endsAt: "2026-07-15T11:45:00.000Z",
        }),
      );
      const multi = await handleLogRemindersRequest(jobRequest(LUNCH_BST));
      assertEquals(multi.status, 200);
      const multiBody = await multi.json() as { sent?: number; slot?: string };
      assertEquals(multiBody.sent, 1);
      assertEquals(multiBody.slot, "lunch");
      const second = harness.sent[1] as { subject: string; text: string };
      assertEquals(second.subject, "Log your Wolf lunch session");
      assertStringIncludes(second.text, "You were booked in at lunch (8:15 and 12:00)");

      const eveningId = crypto.randomUUID();
      const eveningEmail = `evening-${harness.gymId.slice(0, 8)}@example.com`;
      const eveningRoster = String(Number(harness.rosterId) + 2);
      const eveningInsert = await admin.from("members").insert({
        id: eveningId,
        gym_id: harness.gymId,
        teamup_customer_id: `oauth-${eveningRoster}`,
        teamup_roster_id: eveningRoster,
        teamup_email: eveningEmail,
        display_name: "Evening Member",
      });
      if (eveningInsert.error) throw eveningInsert.error;

      harness.attendances.splice(
        0,
        harness.attendances.length,
        attendance({
          rosterId: Number(eveningRoster),
          email: eveningEmail,
          status: "registered",
          name: "WOD",
          startsAt: "2026-07-15T18:40:00.000Z",
          endsAt: "2026-07-15T19:20:00.000Z",
        }),
      );
      const evening = await handleLogRemindersRequest(jobRequest(EVENING_BST));
      assertEquals(evening.status, 200);
      const eveningBody = await evening.json() as { sent?: number; slot?: string };
      assertEquals(eveningBody.sent, 1);
      assertEquals(eveningBody.slot, "evening");
      const third = harness.sent[2] as { subject: string; text: string };
      assertEquals(third.subject, "Log your Wolf evening session");
      assertStringIncludes(third.text, "You were booked in this evening (WOD at 19:40).");

      const loggedId = crypto.randomUUID();
      const loggedEmail = `logged-${harness.gymId.slice(0, 8)}@example.com`;
      const loggedRoster = String(Number(harness.rosterId) + 3);
      const loggedMember = await admin.from("members").insert({
        id: loggedId,
        gym_id: harness.gymId,
        teamup_customer_id: `oauth-${loggedRoster}`,
        teamup_roster_id: loggedRoster,
        teamup_email: loggedEmail,
        display_name: "Already Logged",
      });
      if (loggedMember.error) throw loggedMember.error;
      const sessionInsert = await admin.from("sessions").insert({
        id: crypto.randomUUID(),
        gym_id: harness.gymId,
        member_id: loggedId,
        date: "2026-07-15",
      });
      if (sessionInsert.error) throw sessionInsert.error;
      harness.attendances.splice(
        0,
        harness.attendances.length,
        attendance({
          rosterId: Number(loggedRoster),
          email: loggedEmail,
          status: "attended",
          name: "Hyrox",
          startsAt: "2026-07-15T07:15:00.000Z",
          endsAt: "2026-07-15T07:45:00.000Z",
        }),
      );
      const loggedRun = await handleLogRemindersRequest(jobRequest(MORNING_BST));
      assertEquals(loggedRun.status, 200);
      const loggedBody = await loggedRun.json() as {
        sent?: number;
        skipped?: Record<string, number>;
      };
      assertEquals(loggedBody.sent, 0);
      assertEquals(loggedBody.skipped?.already_logged, 1);
    } finally {
      await harness.restore();
    }
  },
});

Deno.test({
  name: "HTTP unsubscribe sets opt-out, rejects tampered token, job then skips",
  ignore: liveEnv() == null,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const harness = await startLiveHarness();
    if (!harness) throw new Error("live env disappeared");
    const env = liveEnv()!;
    const admin = createClient(env.url, env.serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    try {
      const token = await signLogReminderOptOutToken(harness.memberId, UNSUB_SECRET);
      const tampered = `${token.slice(0, -4)}abcd`;
      const bad = await handleLogRemindersRequest(
        new Request(`${UNSUB}?token=${encodeURIComponent(tampered)}`),
      );
      assertEquals(bad.status, 400);
      assertStringIncludes(await bad.text(), "invalid");

      const getRes = await handleLogRemindersRequest(
        new Request(`${UNSUB}?token=${encodeURIComponent(token)}`),
      );
      assertEquals(getRes.status, 200);
      assertEquals(getRes.headers.get("Content-Type")?.includes("text/html"), true);
      assertStringIncludes(await getRes.text(), "You are unsubscribed");

      const row = await admin
        .from("members")
        .select("log_reminder_email_opted_out_at")
        .eq("id", harness.memberId)
        .single();
      if (row.error) throw row.error;
      assertEquals(typeof row.data.log_reminder_email_opted_out_at, "string");

      const postRes = await handleLogRemindersRequest(
        new Request(`${UNSUB}?token=${encodeURIComponent(token)}`, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: "List-Unsubscribe=One-Click",
        }),
      );
      assertEquals(postRes.status, 200);
      assertEquals((await postRes.json() as { ok?: boolean }).ok, true);

      harness.attendances.push(attendance({
        rosterId: Number(harness.rosterId),
        email: harness.email,
        status: "registered",
        name: "Hyrox",
        startsAt: "2026-07-15T07:15:00.000Z",
        endsAt: "2026-07-15T07:45:00.000Z",
      }));
      const job = await handleLogRemindersRequest(jobRequest(MORNING_BST));
      assertEquals(job.status, 200);
      const body = await job.json() as { sent?: number; skipped?: Record<string, number> };
      assertEquals(body.sent, 0);
      assertEquals(body.skipped?.opted_out, 1);
      assertEquals(harness.sent.length, 0);
    } finally {
      await harness.restore();
    }
  },
});

Deno.test({
  name: "HTTP POST backoff pauses after 3 send dates and resets when any session is logged",
  ignore: liveEnv() == null,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const harness = await startLiveHarness();
    if (!harness) throw new Error("live env disappeared");
    const env = liveEnv()!;
    const admin = createClient(env.url, env.serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    try {
      const prior = await admin.from("log_reminder_sends").insert([
        {
          gym_id: harness.gymId,
          member_id: harness.memberId,
          for_date: "2026-07-12",
          kind: "booked_unlogged",
          slot: "morning",
          sent_at: "2026-07-12T08:00:00.000Z",
        },
        {
          gym_id: harness.gymId,
          member_id: harness.memberId,
          for_date: "2026-07-13",
          kind: "booked_unlogged",
          slot: "lunch",
          sent_at: "2026-07-13T13:00:00.000Z",
        },
        {
          gym_id: harness.gymId,
          member_id: harness.memberId,
          for_date: "2026-07-14",
          kind: "booked_unlogged",
          slot: "evening",
          sent_at: "2026-07-14T20:00:00.000Z",
        },
      ]);
      if (prior.error) throw prior.error;

      harness.attendances.push(attendance({
        rosterId: Number(harness.rosterId),
        email: harness.email,
        status: "registered",
        name: "Hyrox",
        startsAt: "2026-07-15T07:15:00.000Z",
        endsAt: "2026-07-15T07:45:00.000Z",
      }));
      const paused = await handleLogRemindersRequest(jobRequest(MORNING_BST));
      assertEquals(paused.status, 200);
      const pausedBody = await paused.json() as { sent?: number; skipped?: Record<string, number> };
      assertEquals(pausedBody.sent, 0);
      assertEquals(pausedBody.skipped?.backoff, 1);
      assertEquals(harness.sent.length, 0);

      const logged = await admin.from("sessions").insert({
        id: crypto.randomUUID(),
        gym_id: harness.gymId,
        member_id: harness.memberId,
        date: "2026-07-11",
        created_at: "2026-07-15T07:00:00.000Z",
      });
      if (logged.error) throw logged.error;

      const resumed = await handleLogRemindersRequest(jobRequest(MORNING_BST));
      assertEquals(resumed.status, 200);
      const resumedBody = await resumed.json() as { sent?: number };
      assertEquals(resumedBody.sent, 1);
      assertEquals(harness.sent.length, 1);
    } finally {
      await harness.restore();
    }
  },
});
