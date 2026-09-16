import { describe, expect, test } from "bun:test";
import { buildAddExercisesPayload, buildLogSessionPayload } from "./log-set";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

describe("buildLogSessionPayload", () => {
  test("packs every exercise into one payload with client ids", () => {
    const payload = buildLogSessionPayload({
      sessionDate: "2026-09-16",
      notes: "legs",
      calories_burned: 400,
      exercises: [
        { exerciseId: "11111111-1111-4111-8111-111111111111", weight: 100, reps: 5 },
        { exerciseId: "22222222-2222-4222-8222-222222222222", time: 60 },
      ],
    });

    expect(payload.session.date).toBe("2026-09-16");
    expect(payload.session.notes).toBe("legs");
    expect(payload.session.calories_burned).toBe(400);
    expect(payload.session.id).toMatch(UUID_PATTERN);
    expect(payload.exercises).toHaveLength(2);
    expect(payload.exercises[0]?.exerciseId).toBe(
      "11111111-1111-4111-8111-111111111111",
    );
    expect(payload.exercises[0]?.sets[0]).toMatchObject({ weight: 100, reps: 5 });
    expect(payload.exercises[1]?.sets[0]).toMatchObject({ time_seconds: 60 });

    const ids = [
      payload.session.id,
      ...payload.exercises.flatMap((ex) => [
        ex.exerciseEntryId,
        ...ex.sets.map((set) => set.id),
      ]),
    ];
    expect(ids.every((id) => UUID_PATTERN.test(id))).toBe(true);
    expect(new Set(ids).size).toBe(ids.length);
  });

  test("rejects an empty exercise list before any network call", () => {
    expect(() =>
      buildLogSessionPayload({
        sessionDate: "2026-09-16",
        exercises: [],
      }),
    ).toThrow("At least one exercise is required to log a session.");
  });
});

describe("buildAddExercisesPayload", () => {
  test("attaches exercises to an existing session id without a session create object", () => {
    const sessionId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const payload = buildAddExercisesPayload(sessionId, [
      { exerciseId: "11111111-1111-4111-8111-111111111111", weight: 100, reps: 5 },
    ]);

    expect(payload.sessionId).toBe(sessionId);
    expect(payload.exercises).toHaveLength(1);
    expect(payload.exercises[0]?.exerciseEntryId).toMatch(UUID_PATTERN);
    expect(payload.exercises[0]?.sets[0]).toMatchObject({ weight: 100, reps: 5 });
    expect("session" in payload).toBe(false);
  });

  test("rejects an empty exercise list before any network call", () => {
    expect(() =>
      buildAddExercisesPayload("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", []),
    ).toThrow("At least one exercise is required to log a session.");
  });
});
