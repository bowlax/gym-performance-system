/**
 * Unit tests for gymPbFrequencyFromSources (the body of deriveGymPbFrequency).
 *
 * Hits must follow the same badgeIds contract as count: undated excluded,
 * ties not badged, resets unused. Members with zero in-window badges omitted.
 */
import { assertEquals } from "jsr:@std/assert@1";
import {
  gymPbFrequencyFromSources,
  type GymPbFrequencySources,
} from "./edge-pb-reads.ts";
import type { DerivationRecord } from "./pb-derivation.ts";
import type { PBRule } from "./pb-evaluation.ts";

const SQUAT = {
  id: "ex-squat",
  name: "Squat",
  pb_rule: "heaviestWeightAtReps" as PBRule,
  measurement_type: "weightAndReps",
};
const BENCH = {
  id: "ex-bench",
  name: "Bench",
  pb_rule: "heaviestWeightAtReps" as PBRule,
  measurement_type: "weightAndReps",
};

const MEMBER_A = { id: "m-a", teamup_customer_id: "A" };
const MEMBER_ZERO = { id: "m-zero", teamup_customer_id: "Z" };
const MEMBER_TIE_ONLY = { id: "m-tie", teamup_customer_id: "T" };

const WINDOW = { from: "2026-07-01", to: "2026-07-31" };

function setRecord(
  id: string,
  achievedAt: string | null,
  weight: number,
  reps = 5,
): DerivationRecord {
  return { id, achievedAt, weight, reps, entryKind: achievedAt == null ? "manual" : "set" };
}

function sources(input: {
  members?: GymPbFrequencySources["members"];
  exercises?: GymPbFrequencySources["exercises"];
  records: Array<[string, DerivationRecord[]]>;
}): GymPbFrequencySources {
  return {
    members: input.members ?? [MEMBER_A, MEMBER_ZERO],
    exercises: input.exercises ?? [SQUAT, BENCH],
    recordsByMemberExercise: new Map(input.records),
  };
}

function assertHitsMatchCount(
  rows: ReturnType<typeof gymPbFrequencyFromSources>,
): void {
  for (const row of rows) {
    assertEquals(row.hits.length, row.count, `${row.member_id} hits.length vs count`);
  }
}

Deno.test("hits exclude undated manuals that badgeIds also exclude", () => {
  const rows = gymPbFrequencyFromSources(
    sources({
      records: [
        [
          `${MEMBER_A.id}:${SQUAT.id}`,
          [
            setRecord("s-dated", "2026-07-02", 90),
            setRecord("s-undated", null, 200),
            setRecord("s-later", "2026-07-20", 100),
          ],
        ],
      ],
    }),
    WINDOW.from,
    WINDOW.to,
  );

  assertEquals(rows.length, 1);
  assertEquals(rows[0].member_id, MEMBER_A.id);
  assertEquals(rows[0].count, 2);
  assertEquals(rows[0].hits.map((hit) => hit.weight), [90, 100]);
  assertEquals(
    rows[0].hits.every((hit) => hit.weight !== 200),
    true,
  );
  assertHitsMatchCount(rows);
});

Deno.test("hits omit ties that badgeIds also omit", () => {
  const rows = gymPbFrequencyFromSources(
    sources({
      records: [
        [
          `${MEMBER_A.id}:${SQUAT.id}`,
          [
            setRecord("s-before", "2026-06-30", 80),
            setRecord("s-beat", "2026-07-02", 90),
            setRecord("s-tie", "2026-07-15", 90),
          ],
        ],
      ],
    }),
    WINDOW.from,
    WINDOW.to,
  );

  assertEquals(rows.length, 1);
  assertEquals(rows[0].count, 1);
  assertEquals(rows[0].hits, [
    {
      exercise_id: SQUAT.id,
      exercise_name: SQUAT.name,
      achieved_at: "2026-07-02",
      measurement_type: "weightAndReps",
      weight: 90,
      reps: 5,
      time_seconds: null,
      distance: null,
    },
  ]);
  assertHitsMatchCount(rows);
});

Deno.test("reset is not an input; a post-reset badge is still a hit", () => {
  // badgeIds has no resetAt. A 110 after a would-be reset still badges off
  // the lifetime running max (100), same as count. gymPbFrequencyFromSources
  // does not even accept reset lines.
  const rows = gymPbFrequencyFromSources(
    sources({
      records: [
        [
          `${MEMBER_A.id}:${SQUAT.id}`,
          [
            setRecord("s-pre-reset", "2026-07-05", 100),
            setRecord("s-post-reset", "2026-07-20", 110),
          ],
        ],
      ],
    }),
    WINDOW.from,
    WINDOW.to,
  );

  assertEquals(rows[0].count, 2);
  assertEquals(rows[0].hits.map((hit) => hit.achieved_at), [
    "2026-07-05",
    "2026-07-20",
  ]);
  assertHitsMatchCount(rows);
});

Deno.test("member with zero in-window hits is omitted, matching zero count", () => {
  const rows = gymPbFrequencyFromSources(
    sources({
      members: [MEMBER_A, MEMBER_ZERO, MEMBER_TIE_ONLY],
      records: [
        [
          `${MEMBER_A.id}:${SQUAT.id}`,
          [
            setRecord("s-june", "2026-06-30", 80),
            setRecord("s-august", "2026-08-01", 90),
          ],
        ],
        [
          `${MEMBER_TIE_ONLY.id}:${SQUAT.id}`,
          [
            setRecord("t-before", "2026-06-30", 90),
            setRecord("t-tie", "2026-07-10", 90),
          ],
        ],
      ],
    }),
    WINDOW.from,
    WINDOW.to,
  );

  assertEquals(rows, []);
});

Deno.test("hits stay one-per-badge across two exercises and sort by date then name", () => {
  const rows = gymPbFrequencyFromSources(
    sources({
      members: [MEMBER_A],
      records: [
        [
          `${MEMBER_A.id}:${SQUAT.id}`,
          [
            setRecord("sq-1", "2026-07-20", 110),
            setRecord("sq-0", "2026-07-05", 100),
          ],
        ],
        [
          `${MEMBER_A.id}:${BENCH.id}`,
          [setRecord("bp-1", "2026-07-05", 70)],
        ],
      ],
    }),
    WINDOW.from,
    WINDOW.to,
  );

  assertEquals(rows.length, 1);
  assertEquals(rows[0].count, 3);
  assertEquals(rows[0].exercises, [SQUAT.name, BENCH.name]);
  assertEquals(
    rows[0].hits.map((hit) => `${hit.achieved_at}:${hit.exercise_name}`),
    ["2026-07-05:Bench", "2026-07-05:Squat", "2026-07-20:Squat"],
  );
  assertHitsMatchCount(rows);
});
