import { assertEquals } from "jsr:@std/assert@1";
import {
  badgeIds,
  derivePBs,
  expiryDate,
  isFresh,
  shouldShowLifetimePB,
  type DerivationRecord,
  type StalenessSetting,
} from "./pb-derivation.ts";
import type { PBRule, SetState } from "./pb-evaluation.ts";

interface ExpiryVector {
  id: string;
  description: string;
  achievedAt: string;
  compareAchievedAt?: string;
  staleness: StalenessSetting;
  evaluatedAt: string;
  expectedExpiryAt: string | null;
  expectedFresh: boolean;
  expectedCompareExpiryAt?: string;
  expectedCompareFresh?: boolean;
}

interface DerivationVector {
  id: string;
  description: string;
  rule: PBRule;
  staleness: StalenessSetting;
  resetAt: string | null;
  evaluatedAt: string;
  records: DerivationRecord[];
  expectedCurrentId: string | null;
  expectedLifetimeId: string | null;
}

interface BadgeVector {
  id: string;
  description: string;
  rule: PBRule;
  records: DerivationRecord[];
  expectedBadgedIds: string[];
}

interface LifetimeVisibilityVector {
  id: string;
  description: string;
  rule: PBRule;
  current: SetState | null;
  lifetime: SetState | null;
  expectedShow: boolean;
}

interface VectorFile<T> {
  schemaVersion: number;
  vectors: T[];
}

const expiryFile = JSON.parse(
  await Deno.readTextFile(
    new URL("../../../tests/vectors/pb-expiry-vectors.json", import.meta.url),
  ),
) as VectorFile<ExpiryVector>;

const derivationFile = JSON.parse(
  await Deno.readTextFile(
    new URL(
      "../../../tests/vectors/pb-derivation-vectors.json",
      import.meta.url,
    ),
  ),
) as VectorFile<DerivationVector>;

const badgeFile = JSON.parse(
  await Deno.readTextFile(
    new URL("../../../tests/vectors/pb-badge-vectors.json", import.meta.url),
  ),
) as VectorFile<BadgeVector>;

const lifetimeVisibilityFile = JSON.parse(
  await Deno.readTextFile(
    new URL(
      "../../../tests/vectors/pb-lifetime-visibility-vectors.json",
      import.meta.url,
    ),
  ),
) as VectorFile<LifetimeVisibilityVector>;

Deno.test("PB reshape vector counts", () => {
  assertEquals(expiryFile.vectors.length, 24);
  assertEquals(derivationFile.vectors.length, 19);
  assertEquals(badgeFile.vectors.length, 8);
  assertEquals(lifetimeVisibilityFile.vectors.length, 8);
});

for (const vector of expiryFile.vectors) {
  Deno.test(`[${vector.id}] ${vector.description}`, () => {
    if (vector.staleness.enabled) {
      assertEquals(
        expiryDate(
          vector.achievedAt,
          vector.staleness.periods,
          vector.staleness.unit,
        ),
        vector.expectedExpiryAt,
        `[${vector.id}] expiry mismatch`,
      );
    } else {
      assertEquals(vector.expectedExpiryAt, null);
    }

    assertEquals(
      isFresh(vector.achievedAt, vector.staleness, vector.evaluatedAt),
      vector.expectedFresh,
      `[${vector.id}] fresh mismatch`,
    );

    if (vector.compareAchievedAt != null) {
      assertEquals(
        expiryDate(
          vector.compareAchievedAt,
          vector.staleness.periods,
          vector.staleness.unit,
        ),
        vector.expectedCompareExpiryAt,
        `[${vector.id}] compare expiry mismatch`,
      );
      assertEquals(
        isFresh(
          vector.compareAchievedAt,
          vector.staleness,
          vector.evaluatedAt,
        ),
        vector.expectedCompareFresh,
        `[${vector.id}] compare fresh mismatch`,
      );
    }
  });
}

for (const vector of derivationFile.vectors) {
  Deno.test(`[${vector.id}] ${vector.description}`, () => {
    const result = derivePBs({
      rule: vector.rule,
      records: vector.records,
      staleness: vector.staleness,
      resetAt: vector.resetAt,
      evaluatedAt: vector.evaluatedAt,
    });

    assertEquals(
      result.currentPB?.id ?? null,
      vector.expectedCurrentId,
      `[${vector.id}] currentPB mismatch`,
    );
    assertEquals(
      result.lifetimePB?.id ?? null,
      vector.expectedLifetimeId,
      `[${vector.id}] lifetimePB mismatch`,
    );
  });
}

for (const vector of badgeFile.vectors) {
  Deno.test(`[${vector.id}] ${vector.description}`, () => {
    assertEquals(
      badgeIds({ rule: vector.rule, records: vector.records }),
      vector.expectedBadgedIds,
      `[${vector.id}] badges mismatch`,
    );
  });
}

for (const vector of lifetimeVisibilityFile.vectors) {
  Deno.test(`[${vector.id}] ${vector.description}`, () => {
    assertEquals(
      shouldShowLifetimePB(vector.lifetime, vector.current, vector.rule),
      vector.expectedShow,
      `[${vector.id}] show mismatch`,
    );
  });
}
