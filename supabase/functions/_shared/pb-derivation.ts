/**
 * Pure PB freshness / current-lifetime derivation / historic badges (#28).
 *
 * Must stay in sync with `src/core/member-performance/PBDerivation.swift`.
 * Governed by:
 * - tests/vectors/pb-expiry-vectors.json
 * - tests/vectors/pb-derivation-vectors.json
 * - tests/vectors/pb-badge-vectors.json
 * - tests/vectors/pb-lifetime-visibility-vectors.json
 *
 * "Best" uses `evaluatePB` from pb-evaluation.ts — the rule itself is not reimplemented.
 */

import { evaluatePB, type PBRule, type SetState } from "./pb-evaluation.ts";

export type StalenessUnit = "quarters" | "months";

export interface StalenessSetting {
  enabled: boolean;
  periods: number;
  unit: StalenessUnit;
}

export interface DerivationRecord extends SetState {
  id: string;
  /** ISO date `YYYY-MM-DD`, or null/undefined for undated manuals. */
  achievedAt?: string | null;
  entryKind?: string;
}

export interface DerivePBsInput {
  rule: PBRule;
  records: DerivationRecord[];
  staleness: StalenessSetting;
  resetAt?: string | null;
  evaluatedAt: string;
}

export interface DerivePBsResult {
  currentPB: DerivationRecord | null;
  lifetimePB: DerivationRecord | null;
}

export interface BadgeInput {
  rule: PBRule;
  records: DerivationRecord[];
}

/** Parse `YYYY-MM-DD` as a UTC calendar day. */
export function parseISODate(iso: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!match) {
    throw new Error(`Invalid ISO date: ${iso}`);
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  return new Date(Date.UTC(year, month - 1, day));
}

export function formatISODate(date: Date): string {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function startOfPeriod(date: Date, unit: StalenessUnit): Date {
  const year = date.getUTCFullYear();
  const month = date.getUTCMonth();
  if (unit === "months") {
    return new Date(Date.UTC(year, month, 1));
  }
  const quarterStartMonth = Math.floor(month / 3) * 3;
  return new Date(Date.UTC(year, quarterStartMonth, 1));
}

function addPeriods(date: Date, count: number, unit: StalenessUnit): Date {
  const year = date.getUTCFullYear();
  const month = date.getUTCMonth();
  if (unit === "months") {
    return new Date(Date.UTC(year, month + count, 1));
  }
  return new Date(Date.UTC(year, month + count * 3, 1));
}

/**
 * Expiry = start of the period after N complete periods following the
 * period that contains `achievedAt` = periodStart + (N + 1) periods.
 */
export function expiryDate(
  achievedAt: string,
  periods: number,
  unit: StalenessUnit,
): string {
  const start = startOfPeriod(parseISODate(achievedAt), unit);
  return formatISODate(addPeriods(start, periods + 1, unit));
}

/**
 * Fresh when evaluatedAt is strictly before expiry.
 * Expiry day itself is stale.
 *
 * Undated (`achievedAt` null) is **never** fresh — regardless of whether
 * staleness is enabled. Deliberate decision (2026-07-21 / TC-D20): “current”
 * is a claim about now, which an undated entry cannot support even when
 * time-filtering is off. Lifetime remains the only place undated entries appear.
 * Otherwise, staleness disabled => always fresh (dated records only).
 */
export function isFresh(
  achievedAt: string | null | undefined,
  staleness: StalenessSetting,
  evaluatedAt: string,
): boolean {
  if (achievedAt == null) {
    return false;
  }
  if (!staleness.enabled) {
    return true;
  }
  const expiry = expiryDate(achievedAt, staleness.periods, staleness.unit);
  return evaluatedAt < expiry;
}

function asSetState(record: SetState): SetState {
  return {
    weight: record.weight ?? null,
    reps: record.reps ?? null,
    time: record.time ?? null,
    distance: record.distance ?? null,
  };
}

/** True when challenger beats current under the PB rule (strict improvement). */
export function beats(
  challenger: SetState,
  current: SetState | null,
  rule: PBRule,
): boolean {
  return evaluatePB({
    rule,
    currentPB: current == null ? null : asSetState(current),
    newSet: asSetState(challenger),
  }).isPB;
}

function bestRecord(
  records: DerivationRecord[],
  rule: PBRule,
): DerivationRecord | null {
  let best: DerivationRecord | null = null;
  for (const record of records) {
    if (beats(record, best, rule)) {
      best = record;
    }
  }
  return best;
}

function tiesUnderRule(
  left: DerivationRecord,
  right: DerivationRecord,
  rule: PBRule,
): boolean {
  return !beats(left, right, rule) && !beats(right, left, rule);
}

function moreRecentAchievedAt(
  challenger: DerivationRecord,
  current: DerivationRecord | null,
): boolean {
  if (current == null) {
    return true;
  }
  if (challenger.achievedAt == null) {
    return false;
  }
  if (current.achievedAt == null) {
    return true;
  }
  return challenger.achievedAt > current.achievedAt;
}

function bestCurrentRecord(
  records: DerivationRecord[],
  rule: PBRule,
): DerivationRecord | null {
  let best: DerivationRecord | null = null;
  for (const record of records) {
    if (
      beats(record, best, rule) ||
      (best != null &&
        tiesUnderRule(record, best, rule) &&
        moreRecentAchievedAt(record, best))
    ) {
      best = record;
    }
  }
  return best;
}

function isAfterReset(
  achievedAt: string | null | undefined,
  resetAt: string | null | undefined,
): boolean {
  if (resetAt == null) {
    return true;
  }
  if (achievedAt == null) {
    return false;
  }
  return achievedAt > resetAt;
}

/**
 * currentPB = best where achievedAt > resetAt AND fresh.
 * lifetimePB = best overall (no reset / freshness filter).
 */
export function derivePBs(input: DerivePBsInput): DerivePBsResult {
  const { rule, records, staleness, resetAt, evaluatedAt } = input;

  const lifetimePB = bestRecord(records, rule);

  const currentCandidates = records.filter((record) =>
    isAfterReset(record.achievedAt, resetAt) &&
    isFresh(record.achievedAt, staleness, evaluatedAt)
  );
  const currentPB = bestCurrentRecord(currentCandidates, rule);

  return { currentPB, lifetimePB };
}

/**
 * Progression lifetime element: show iff lifetime strictly beats current
 * under the PB rule (#28). Ties hide. Uses `evaluatePB` via `beats` — not
 * record ids (equal values can have different ids after divergent tie-breaks).
 */
export function shouldShowLifetimePB(
  lifetime: SetState | null | undefined,
  current: SetState | null | undefined,
  rule: PBRule,
): boolean {
  if (lifetime == null) {
    return false;
  }
  if (current == null) {
    return true;
  }
  return beats(lifetime, current, rule);
}

/**
 * Historic badges: running maximum over dated records in achievedAt order.
 * Equal to running max is NOT badged. Undated excluded.
 */
export function badgeIds(input: BadgeInput): string[] {
  const dated = input.records
    .filter((record) => record.achievedAt != null)
    .slice()
    .sort((a, b) => {
      const left = a.achievedAt as string;
      const right = b.achievedAt as string;
      if (left !== right) {
        return left < right ? -1 : 1;
      }
      return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
    });

  const badged: string[] = [];
  let runningMax: DerivationRecord | null = null;

  for (const record of dated) {
    if (beats(record, runningMax, input.rule)) {
      badged.push(record.id);
      runningMax = record;
    }
  }

  return badged;
}
