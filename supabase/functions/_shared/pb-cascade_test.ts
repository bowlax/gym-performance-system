import { assertEquals } from "jsr:@std/assert@1";
import { bestRestorable, type PBRecord } from "./pb-cascade.ts";
import type { PBRule } from "./pb-evaluation.ts";

interface PBCascadeVector {
  id: string;
  description: string;
  rule: PBRule;
  exerciseName: string;
  targetReps: number | null;
  minimumReps: number | null;
  records: PBRecord[];
  excludingIds?: string[] | null;
  excludingSetIds?: string[] | null;
  expectedCurrentId: string | null;
}

interface PBCascadeVectorFile {
  schemaVersion: number;
  vectors: PBCascadeVector[];
}

const vectorsFileURL = new URL(
  "../../../tests/vectors/pb-cascade-vectors.json",
  import.meta.url,
);

const vectorFile = JSON.parse(
  await Deno.readTextFile(vectorsFileURL),
) as PBCascadeVectorFile;

Deno.test("PB cascade vectors match shared contract", () => {
  assertEquals(vectorFile.vectors.length, 15);
});

for (const vector of vectorFile.vectors) {
  Deno.test(`[${vector.id}] ${vector.description}`, () => {
    const selectedId = bestRestorable({
      rule: vector.rule,
      records: vector.records,
      excludingIds: vector.excludingIds ?? undefined,
      excludingSetIds: vector.excludingSetIds ?? undefined,
      ruleParameters: {
        targetReps: vector.targetReps,
        minimumReps: vector.minimumReps,
      },
    });

    assertEquals(
      selectedId,
      vector.expectedCurrentId,
      `[${vector.id}] expected ${vector.expectedCurrentId ?? "null"}, got ${
        selectedId ?? "null"
      }`,
    );
  });
}
