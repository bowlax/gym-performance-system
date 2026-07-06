import { assertEquals } from "jsr:@std/assert@1";
import { evaluatePB, type PBRule, type SetState } from "./pb-evaluation.ts";

interface PBEvaluationVector {
  id: string;
  description: string;
  rule: PBRule;
  exerciseName: string;
  targetReps: number | null;
  minimumReps: number | null;
  currentPB: SetState | null;
  newSet: SetState;
  expectedResult: "isPB" | "notPB";
}

interface PBEvaluationVectorFile {
  schemaVersion: number;
  vectors: PBEvaluationVector[];
}

const vectorsFileURL = new URL(
  "../../../tests/vectors/pb-evaluation-vectors.json",
  import.meta.url,
);

const vectorFile = JSON.parse(
  await Deno.readTextFile(vectorsFileURL),
) as PBEvaluationVectorFile;

Deno.test("PB evaluation vectors match shared contract", () => {
  assertEquals(vectorFile.vectors.length, 19);
});

for (const vector of vectorFile.vectors) {
  Deno.test(`[${vector.id}] ${vector.description}`, () => {
    const result = evaluatePB({
      rule: vector.rule,
      currentPB: vector.currentPB,
      newSet: vector.newSet,
      ruleParameters: {
        targetReps: vector.targetReps,
        minimumReps: vector.minimumReps,
      },
    });

    const expectedIsPB = vector.expectedResult === "isPB";
    assertEquals(
      result.isPB,
      expectedIsPB,
      `[${vector.id}] expected ${vector.expectedResult}, got ${
        result.isPB ? "isPB" : "notPB"
      }`,
    );

    if (expectedIsPB) {
      assertEquals(result.resultingPB, {
        weight: vector.newSet.weight ?? null,
        reps: vector.newSet.reps ?? null,
        time: vector.newSet.time ?? null,
        distance: vector.newSet.distance ?? null,
      });
    } else {
      assertEquals(result.resultingPB, null);
    }
  });
}
