import { bestSetFromSets } from "./best-set";
import { chartValue, formatSetValues } from "./format";
import type {
  DerivedManualPBRow,
  DerivedPBDisplay,
} from "./derive-pb-reads";
import type { StalenessSetting } from "@gp-shared/pb-derivation.ts";
import type { ExerciseRow, SessionSetRow } from "./queries";

export interface ExerciseSetSummary {
  sessionDate: string;
  set: SessionSetRow;
  isPB: boolean;
}

export interface ProgressionEntryRow {
  id: string;
  date: string;
  formattedValue: string;
  chartValue: number;
  isPB: boolean;
  isResetMarker: boolean;
  setId: string | null;
  personalBestId: string | null;
  reps: number | null;
}

const SESSION_DERIVED = "sessionDerived";

function setChartInput(set: SessionSetRow) {
  return {
    weight: set.weight,
    reps: set.reps,
    timeSeconds: set.time_seconds,
    distance: set.distance,
  };
}

function manualPbChartInput(pb: DerivedManualPBRow) {
  return {
    weight: pb.weight,
    reps: pb.reps,
    timeSeconds: pb.time_seconds,
    distance: pb.distance,
  };
}

export function mergeProgressionEntries(params: {
  sessionHistory: ExerciseSetSummary[];
  manualPersonalBests: DerivedManualPBRow[];
  exercise: ExerciseRow;
  badgeIdSet: ReadonlySet<string>;
  resetAt: string | null;
  from: Date;
}): ProgressionEntryRow[] {
  const { sessionHistory, manualPersonalBests, exercise, badgeIdSet, resetAt, from } =
    params;
  const measurementType = exercise.measurement_type ?? "";
  const fromTime = from.getTime();
  const representedSetIds = new Set<string>();
  const merged: ProgressionEntryRow[] = [];

  for (const summary of sessionHistory) {
    representedSetIds.add(summary.set.id);
    const isPB = badgeIdSet.has(summary.set.id);
    const personalBestId = isPB ? summary.set.id : null;

    merged.push({
      id: summary.set.id,
      date: summary.sessionDate,
      formattedValue: formatSetValues({
        ...setChartInput(summary.set),
        measurementType,
        exerciseName: exercise.name,
      }),
      chartValue: chartValue({
        ...setChartInput(summary.set),
        measurementType,
      }),
      isPB,
      isResetMarker: false,
      setId: summary.set.id,
      personalBestId,
      reps: summary.set.reps,
    });
  }

  // Undated manuals never appear in history (#28).
  for (const pb of manualPersonalBests) {
    if (pb.achieved_at == null) continue;
    const achievedTime = new Date(pb.achieved_at).getTime();
    if (achievedTime < fromTime) continue;
    if (pb.entry_type === SESSION_DERIVED) continue;
    if (pb.set_id && representedSetIds.has(pb.set_id)) continue;

    const chartInput = manualPbChartInput(pb);
    merged.push({
      id: pb.id,
      date: pb.achieved_at,
      formattedValue: formatSetValues({
        ...chartInput,
        measurementType,
        exerciseName: exercise.name,
      }),
      chartValue: chartValue({
        ...chartInput,
        measurementType,
      }),
      isPB: badgeIdSet.has(pb.id),
      isResetMarker: false,
      setId: pb.set_id,
      personalBestId: pb.id,
      reps: pb.reps,
    });
  }

  if (resetAt) {
    const resetTime = new Date(resetAt).getTime();
    if (resetTime >= fromTime) {
      merged.push({
        id: `reset:${exercise.id}`,
        date: resetAt,
        formattedValue: "Reset",
        chartValue: NaN,
        isPB: false,
        isResetMarker: true,
        setId: null,
        personalBestId: null,
        reps: null,
      });
    }
  }

  return merged.sort((left, right) => {
    const leftTime = new Date(left.date).getTime();
    const rightTime = new Date(right.date).getTime();
    return leftTime - rightTime;
  });
}

export type { DerivedPBDisplay, StalenessSetting };
