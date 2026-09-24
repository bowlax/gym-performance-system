import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  buildKioskConfirmEmail,
  hasResolvedKioskName,
  hashKioskToken,
  parseKioskSubmitBody,
} from "./kiosk-pending.ts";

const MEMBER = "00000000-0000-4000-8000-000000000001";
const EXERCISE = "00000000-0000-4000-8000-000000000002";

Deno.test("resolved kiosk name requires roster match, email, and a real display name", () => {
  assertEquals(
    hasResolvedKioskName({
      display_name: "Ada Lovelace",
      teamup_email: "ada@example.com",
      teamup_roster_id: "6714431",
    }),
    true,
  );
  // Device disconnect is not a column. The same row is still listable.
  assertEquals(
    hasResolvedKioskName({
      display_name: "Grace Hopper",
      teamup_email: "grace@example.com",
      teamup_roster_id: "42",
      deleted_at: null,
    }),
    true,
  );
  assertEquals(
    hasResolvedKioskName({
      display_name: "Jwt Only",
      teamup_email: "jwt@example.com",
      teamup_roster_id: null,
    }),
    false,
  );
  assertEquals(
    hasResolvedKioskName({
      display_name: "Member",
      teamup_email: "unnamed@example.com",
      teamup_roster_id: "9",
    }),
    false,
  );
  assertEquals(
    hasResolvedKioskName({
      display_name: "No Email",
      teamup_email: null,
      teamup_roster_id: "9",
    }),
    false,
  );
  assertEquals(
    hasResolvedKioskName({
      display_name: "Deleted",
      teamup_email: "d@example.com",
      teamup_roster_id: "9",
      deleted_at: "2026-01-01T00:00:00Z",
    }),
    false,
  );
});

Deno.test("kiosk submit accepts one set per exercise and rejects multi-set", () => {
  const ok = parseKioskSubmitBody({
    memberId: MEMBER,
    session: { date: "2026-09-24", notes: "board", calories_burned: 120 },
    exercises: [
      {
        exerciseId: EXERCISE,
        sets: [{ weight: 100, reps: 5 }],
      },
    ],
  });
  assert(ok.ok);
  if (!ok.ok) return;
  assertEquals(ok.request.payload.exercises.length, 1);
  assertEquals(ok.request.payload.exercises[0]?.sets.length, 1);
  assertEquals(ok.request.payload.exercises[0]?.sets[0]?.weight, 100);

  const multi = parseKioskSubmitBody({
    memberId: MEMBER,
    session: { date: "2026-09-24" },
    exercises: [
      {
        exerciseId: EXERCISE,
        sets: [{ weight: 80, reps: 5 }, { weight: 100, reps: 5 }],
      },
    ],
  });
  assert(!multi.ok);
  if (multi.ok) return;
  assertEquals(multi.error, "Each exercise must include exactly one set.");
});

Deno.test("confirm email contains the logged set and a single confirm link", () => {
  const copy = buildKioskConfirmEmail({
    displayName: "Ada Lovelace",
    sessionDate: "2026-09-24",
    exercises: [{
      name: "Back Squat",
      weight: 100,
      reps: 5,
      time_seconds: null,
      distance: null,
    }],
    confirmUrl: "https://gym.example/kiosk/confirm?token=abc",
  });
  assertEquals(copy.subject, "Confirm your Wolf session");
  assert(copy.text.includes("Back Squat: 100 kg, 5 reps"));
  assert(copy.text.includes("https://gym.example/kiosk/confirm?token=abc"));
  assert(copy.text.includes("not on your board until you confirm"));
  assertEquals(copy.text.match(/kiosk\/confirm/g)?.length, 1);
});

Deno.test("kiosk token hash is stable and not the raw token", async () => {
  const hash = await hashKioskToken("abc");
  assertEquals(hash, await hashKioskToken("abc"));
  assert(hash !== "abc");
  assertEquals(hash.length, 64);
});

Deno.test("pending migration is a separate table with no expiry and no session flag", async () => {
  const sql = await Deno.readTextFile(
    new URL("../../migrations/20260924120000_kiosk_pending_sessions.sql", import.meta.url),
  );
  assert(sql.includes("create table public.kiosk_pending_sessions"));
  assert(!/expires_at\s+timestamptz/i.test(sql));
  assert(!/alter table public\.sessions/i.test(sql));
  assert(sql.includes("delete from public.kiosk_pending_sessions"));
  assert(sql.includes("insert into public.sessions"));
  assert(!sql.includes("created_at <"));
  assert(!/interval/i.test(sql));
});
