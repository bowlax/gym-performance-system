import {
  evaluatePB,
  type PBRule,
  type SetState,
} from "@gp-shared/pb-evaluation.ts";
import type { DerivedPBDisplay } from "./derive-pb-reads";

export function derivedCurrentAsSetState(
  current: DerivedPBDisplay | null,
): SetState | null {
  if (!current) return null;
  return {
    weight: typeof current.raw.weight === "number" ? current.raw.weight : null,
    reps: typeof current.raw.reps === "number" ? current.raw.reps : null,
    time:
      typeof current.raw.time_seconds === "number"
        ? current.raw.time_seconds
        : typeof current.raw.time === "number"
          ? current.raw.time
          : null,
    distance: typeof current.raw.distance === "number" ? current.raw.distance : null,
  };
}

export function measurementAsSetState(values: {
  weight?: number | null;
  reps?: number | null;
  time_seconds?: number | null;
  time?: number | null;
  distance?: number | null;
}): SetState {
  const time =
    typeof values.time_seconds === "number"
      ? values.time_seconds
      : typeof values.time === "number"
        ? values.time
        : null;
  return {
    weight: values.weight ?? null,
    reps: values.reps ?? null,
    time,
    distance: values.distance ?? null,
  };
}

/**
 * True when `loggedSet` strictly beats the pre-save derived current PB under the
 * PB rule. Equal records are NOT a PB (same contract as badges / evaluatePB).
 */
export function isStrictPBImprovement(params: {
  rule: PBRule;
  beforeCurrent: DerivedPBDisplay | null;
  loggedSet: SetState;
}): boolean {
  return evaluatePB({
    rule: params.rule,
    currentPB: derivedCurrentAsSetState(params.beforeCurrent),
    newSet: params.loggedSet,
  }).isPB;
}

/**
 * Session save celebration: the post-save derived current PB must come from a
 * set logged this session AND strictly beat the pre-save current PB.
 */
export function sessionSetEarnedCelebration(params: {
  rule: PBRule;
  beforeCurrent: DerivedPBDisplay | null;
  afterCurrent: DerivedPBDisplay | null;
  loggedSetIds: ReadonlySet<string>;
  loggedSet: SetState;
}): boolean {
  const { afterCurrent, loggedSetIds } = params;
  if (!afterCurrent?.set_id || !loggedSetIds.has(afterCurrent.set_id)) {
    return false;
  }
  return isStrictPBImprovement({
    rule: params.rule,
    beforeCurrent: params.beforeCurrent,
    loggedSet: params.loggedSet,
  });
}
