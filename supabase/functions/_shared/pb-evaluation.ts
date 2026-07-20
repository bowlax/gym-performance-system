/**
 * Personal-best evaluation logic for server-side use (Supabase Edge Functions).
 *
 * Must stay in sync with the Swift implementation in
 * `src/core/exercise-registry/DefaultExerciseRegistry.swift`. Both are
 * governed by the shared contract in `tests/vectors/pb-evaluation-vectors.json`.
 */

export type PBRule =
  | "heaviestWeight"
  | "heaviestWeightThenLongestTime"
  | "heaviestWeightAtReps"
  | "bestWeightAndReps"
  | "fastestTime"
  | "longestDistance"
  | "mostReps";

export interface SetState {
  weight?: number | null;
  reps?: number | null;
  time?: number | null;
  distance?: number | null;
}

export interface PBRuleParameters {
  targetReps?: number | null;
  minimumReps?: number | null;
}

export interface PBEvaluationInput {
  rule: PBRule;
  currentPB: SetState | null;
  newSet: SetState;
  ruleParameters?: PBRuleParameters;
}

export interface PBEvaluationResult {
  isPB: boolean;
  /** When isPB is true, the measurements that would become the new current PB. */
  resultingPB: SetState | null;
}

function isBestWeightAndRepsPB(
  newSet: SetState,
  currentPB: SetState | null,
): boolean {
  const setReps = newSet.reps;
  const setWeight = newSet.weight;

  if (setReps == null || setReps <= 0) {
    return false;
  }
  if (setWeight == null) {
    return false;
  }

  if (currentPB == null) {
    return true;
  }

  const currentWeight = currentPB.weight;
  if (currentWeight == null) {
    return true;
  }

  if (setWeight < currentWeight) {
    return false;
  }

  if (setWeight > currentWeight) {
    return true;
  }

  const currentReps = currentPB.reps;
  if (currentReps == null) {
    return false;
  }

  return setReps > currentReps;
}

function isHeaviestWeightPB(
  newSet: SetState,
  currentPB: SetState | null,
): boolean {
  const setWeight = newSet.weight;
  if (setWeight == null) {
    return false;
  }

  if (currentPB == null) {
    return true;
  }

  const currentWeight = currentPB.weight;
  if (currentWeight == null) {
    return true;
  }

  return setWeight > currentWeight;
}

function isHeaviestWeightThenLongestTimePB(
  newSet: SetState,
  currentPB: SetState | null,
): boolean {
  const setWeight = newSet.weight;
  const setTime = newSet.time;
  if (setWeight == null || setTime == null) {
    return false;
  }

  if (currentPB == null) {
    return true;
  }

  const currentWeight = currentPB.weight;
  if (currentWeight == null) {
    return true;
  }

  if (setWeight < currentWeight) {
    return false;
  }

  if (setWeight > currentWeight) {
    return true;
  }

  const currentTime = currentPB.time;
  if (currentTime == null) {
    return false;
  }

  return setTime > currentTime;
}

function isFastestTimePB(
  newSet: SetState,
  currentPB: SetState | null,
): boolean {
  const setTime = newSet.time;
  if (setTime == null) {
    return false;
  }

  if (currentPB == null) {
    return true;
  }

  const currentTime = currentPB.time;
  if (currentTime == null) {
    return true;
  }

  return setTime < currentTime;
}

function isLongestDistancePB(
  newSet: SetState,
  currentPB: SetState | null,
): boolean {
  const setDistance = newSet.distance;
  if (setDistance == null) {
    return false;
  }

  if (currentPB == null) {
    return true;
  }

  const currentDistance = currentPB.distance;
  if (currentDistance == null) {
    return true;
  }

  return setDistance > currentDistance;
}

function isMostRepsPB(
  newSet: SetState,
  currentPB: SetState | null,
): boolean {
  const setReps = newSet.reps;
  if (setReps == null) {
    return false;
  }

  if (currentPB == null) {
    return true;
  }

  const currentReps = currentPB.reps;
  if (currentReps == null) {
    return true;
  }

  return setReps > currentReps;
}

function resultingPBFromNewSet(newSet: SetState): SetState {
  return {
    weight: newSet.weight ?? null,
    reps: newSet.reps ?? null,
    time: newSet.time ?? null,
    distance: newSet.distance ?? null,
  };
}

/**
 * Evaluates whether `newSet` is a personal best under `rule`.
 *
 * `targetReps` and `minimumReps` are accepted for API parity with exercise
 * definitions but are not used by the current Swift isPB implementation
 * (heaviestWeightAtReps and bestWeightAndReps share the same logic).
 */
export function evaluatePB(input: PBEvaluationInput): PBEvaluationResult {
  const { rule, currentPB, newSet } = input;

  let isPB: boolean;

  switch (rule) {
    case "heaviestWeightAtReps":
    case "bestWeightAndReps":
      isPB = isBestWeightAndRepsPB(newSet, currentPB);
      break;
    case "heaviestWeight":
      isPB = isHeaviestWeightPB(newSet, currentPB);
      break;
    case "heaviestWeightThenLongestTime":
      isPB = isHeaviestWeightThenLongestTimePB(newSet, currentPB);
      break;
    case "fastestTime":
      isPB = isFastestTimePB(newSet, currentPB);
      break;
    case "longestDistance":
      isPB = isLongestDistancePB(newSet, currentPB);
      break;
    case "mostReps":
      isPB = isMostRepsPB(newSet, currentPB);
      break;
  }

  return {
    isPB,
    resultingPB: isPB ? resultingPBFromNewSet(newSet) : null,
  };
}
