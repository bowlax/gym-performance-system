/**
 * Personal-best cascade ranking for server-side use (Supabase Edge Functions).
 *
 * Must stay in sync with the Swift implementation in
 * `src/core/member-performance/PersonalBestRanking.swift`. Both are
 * governed by the shared contract in `tests/vectors/pb-cascade-vectors.json`.
 */

import type { PBRule, PBRuleParameters } from "./pb-evaluation.ts";

export interface PBRecord {
  id: string;
  weight?: number | null;
  reps?: number | null;
  time?: number | null;
  distance?: number | null;
  wasReset?: boolean | null;
  setId?: string | null;
}

export interface BestRestorableInput {
  rule: PBRule;
  records: PBRecord[];
  excludingIds?: string[];
  excludingSetIds?: string[];
  ruleParameters?: PBRuleParameters;
}

function isCandidate(
  record: PBRecord,
  excludingIds: Set<string>,
  excludingSetIds: Set<string>,
): boolean {
  if (record.wasReset === true) {
    return false;
  }
  if (excludingIds.has(record.id)) {
    return false;
  }
  if (record.setId != null && excludingSetIds.has(record.setId)) {
    return false;
  }
  return true;
}

function bestByWeightAndReps(records: PBRecord[]): PBRecord | null {
  if (records.length === 0) {
    return null;
  }

  return records.reduce((best, current) => {
    const bestWeight = best.weight ?? 0;
    const currentWeight = current.weight ?? 0;
    if (currentWeight !== bestWeight) {
      return currentWeight > bestWeight ? current : best;
    }
    return (current.reps ?? 0) > (best.reps ?? 0) ? current : best;
  });
}

function bestByWeight(records: PBRecord[]): PBRecord | null {
  if (records.length === 0) {
    return null;
  }

  return records.reduce((best, current) =>
    (current.weight ?? 0) > (best.weight ?? 0) ? current : best
  );
}

function bestByFastestTime(records: PBRecord[]): PBRecord | null {
  if (records.length === 0) {
    return null;
  }

  return records.reduce((best, current) =>
    (current.time ?? Number.POSITIVE_INFINITY) <
      (best.time ?? Number.POSITIVE_INFINITY)
      ? current
      : best
  );
}

function bestByLongestDistance(records: PBRecord[]): PBRecord | null {
  if (records.length === 0) {
    return null;
  }

  return records.reduce((best, current) =>
    (current.distance ?? 0) > (best.distance ?? 0) ? current : best
  );
}

function bestByMostReps(records: PBRecord[]): PBRecord | null {
  if (records.length === 0) {
    return null;
  }

  return records.reduce((best, current) =>
    (current.reps ?? 0) > (best.reps ?? 0) ? current : best
  );
}

function best(records: PBRecord[], rule: PBRule): PBRecord | null {
  switch (rule) {
    case "heaviestWeightAtReps":
    case "bestWeightAndReps":
      return bestByWeightAndReps(records);
    case "heaviestWeight":
      return bestByWeight(records);
    case "fastestTime":
      return bestByFastestTime(records);
    case "longestDistance":
      return bestByLongestDistance(records);
    case "mostReps":
      return bestByMostReps(records);
  }
}

/**
 * Selects which remaining PB record should become current after deletion or
 * reset. Returns the record id, or null when no eligible candidate remains.
 *
 * `targetReps` and `minimumReps` are accepted for API parity with exercise
 * definitions but are not used by the current Swift ranking implementation.
 */
export function bestRestorable(input: BestRestorableInput): string | null {
  const {
    rule,
    records,
    excludingIds = [],
    excludingSetIds = [],
  } = input;

  const excludingIdSet = new Set(excludingIds);
  const excludingSetIdSet = new Set(excludingSetIds);

  const candidates = records.filter((record) =>
    isCandidate(record, excludingIdSet, excludingSetIdSet)
  );

  const selected = best(candidates, rule);
  return selected?.id ?? null;
}
