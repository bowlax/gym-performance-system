import {
  evaluatePB,
  type PBRule,
  type SetState,
} from "@gp-shared/pb-evaluation.ts";
import type { SessionSetRow } from "./queries";

const KNOWN_RULES = new Set<string>([
  "heaviestWeightAtReps",
  "bestWeightAndReps",
  "heaviestWeight",
  "heaviestWeightThenLongestTime",
  "fastestTime",
  "longestDistance",
  "mostReps",
]);

function toSetState(set: SessionSetRow): SetState {
  return {
    weight: set.weight,
    reps: set.reps,
    time: set.time_seconds,
    distance: set.distance,
  };
}

/**
 * Pick the best set in a session for progression history (iOS `bestSet` parity).
 *
 * Concern is session ranking for display, not board/lifetime PB derivation — but
 * comparisons use the single `evaluatePB` rule (no local switch duplicate).
 */
export function bestSetFromSets(
  sets: SessionSetRow[],
  pbRule: string | null | undefined,
): SessionSetRow | null {
  if (!pbRule || sets.length === 0 || !KNOWN_RULES.has(pbRule)) return null;

  const rule = pbRule as PBRule;
  let best: SessionSetRow | null = null;

  for (const candidate of sets) {
    const { isPB } = evaluatePB({
      rule,
      currentPB: best == null ? null : toSetState(best),
      newSet: toSetState(candidate),
    });
    if (isPB) {
      best = candidate;
    }
  }

  return best;
}
