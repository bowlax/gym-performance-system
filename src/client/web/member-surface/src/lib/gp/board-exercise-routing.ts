export type BoardExerciseDestination = "progression" | "manual";

/** Mirrors iOS `BoardExerciseRouting.destination`. */
export function boardExerciseDestination(
  hasCurrentPB: boolean,
  hasHistory: boolean,
): BoardExerciseDestination {
  if (hasCurrentPB || hasHistory) return "progression";
  return "manual";
}
