/**
 * Why the board / progression has no *current* PB (#28 empty-state copy).
 * Mirrors iOS `CurrentPBEmptyCopy`.
 */

export type CurrentPBEmptyReason =
  | "neverTrained"
  | "reset"
  | "lapsed"
  | "noCurrent";

export function currentPBEmptyReason(params: {
  hasHistory: boolean;
  hasActiveReset: boolean;
  stalenessEnabled: boolean;
}): CurrentPBEmptyReason {
  if (!params.hasHistory) return "neverTrained";
  if (params.hasActiveReset) return "reset";
  if (params.stalenessEnabled) return "lapsed";
  return "noCurrent";
}

export function boardEmptyCaption(reason: CurrentPBEmptyReason): string {
  switch (reason) {
    case "neverTrained":
      return "No PB yet";
    case "reset":
      return "Reset";
    case "lapsed":
      return "Lapsed";
    case "noCurrent":
      return "No current PB";
  }
}

export function progressionEmptyTitle(reason: CurrentPBEmptyReason): string {
  switch (reason) {
    case "neverTrained":
      return "No PB yet";
    case "reset":
    case "lapsed":
    case "noCurrent":
      return "No current PB";
  }
}

export function progressionEmptyDetail(
  reason: CurrentPBEmptyReason,
): string | null {
  switch (reason) {
    case "neverTrained":
      return "Log a set to establish your first PB.";
    case "reset":
      return "You reset this lift — log a set when you're ready.";
    case "lapsed":
      return "Your last best has lapsed.";
    case "noCurrent":
      return null;
  }
}
