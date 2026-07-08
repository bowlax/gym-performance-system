import type { SessionSetRow } from "./queries";

export type PbRule =
  | "heaviestWeightAtReps"
  | "bestWeightAndReps"
  | "heaviestWeight"
  | "fastestTime"
  | "longestDistance"
  | "mostReps";

/** Pick the best set in a session for progression history (iOS `bestSet` parity). */
export function bestSetFromSets(
  sets: SessionSetRow[],
  pbRule: string | null | undefined,
): SessionSetRow | null {
  if (!pbRule || sets.length === 0) return null;

  switch (pbRule as PbRule) {
    case "heaviestWeightAtReps":
    case "bestWeightAndReps": {
      const eligible = sets.filter((s) => s.weight != null && s.reps != null);
      return eligible.reduce<SessionSetRow | null>((best, candidate) => {
        if (!best) return candidate;
        const leftWeight = best.weight ?? 0;
        const rightWeight = candidate.weight ?? 0;
        if (leftWeight !== rightWeight) {
          return rightWeight > leftWeight ? candidate : best;
        }
        return (candidate.reps ?? 0) > (best.reps ?? 0) ? candidate : best;
      }, null);
    }
    case "heaviestWeight": {
      const eligible = sets.filter((s) => s.weight != null);
      return eligible.reduce<SessionSetRow | null>((best, candidate) => {
        if (!best) return candidate;
        return (candidate.weight ?? 0) > (best.weight ?? 0) ? candidate : best;
      }, null);
    }
    case "fastestTime": {
      const eligible = sets.filter((s) => s.time_seconds != null);
      return eligible.reduce<SessionSetRow | null>((best, candidate) => {
        if (!best) return candidate;
        return (candidate.time_seconds ?? Infinity) < (best.time_seconds ?? Infinity)
          ? candidate
          : best;
      }, null);
    }
    case "longestDistance": {
      const eligible = sets.filter((s) => s.distance != null);
      return eligible.reduce<SessionSetRow | null>((best, candidate) => {
        if (!best) return candidate;
        return (candidate.distance ?? 0) > (best.distance ?? 0) ? candidate : best;
      }, null);
    }
    case "mostReps": {
      const eligible = sets.filter((s) => s.reps != null);
      return eligible.reduce<SessionSetRow | null>((best, candidate) => {
        if (!best) return candidate;
        return (candidate.reps ?? 0) > (best.reps ?? 0) ? candidate : best;
      }, null);
    }
    default:
      return null;
  }
}
