import { bestSetFromSets } from "./best-set";
import { chartValue, formatSetValues } from "./format";
import type {
  ExerciseRow,
  PersonalBestHistoryRow,
  SessionSetRow,
} from "./queries";

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
  wasReset: boolean;
  setId: string | null;
  personalBestId: string | null;
  reps: number | null;
}

const SESSION_DERIVED = "sessionDerived";

function pickPbBySetId(
  personalBests: PersonalBestHistoryRow[],
): Map<string, string> {
  const pbBySetId = new Map<string, string>();

  for (const pb of personalBests) {
    if (!pb.set_id) continue;
    const existingId = pbBySetId.get(pb.set_id);
    if (!existingId) {
      pbBySetId.set(pb.set_id, pb.id);
      continue;
    }

    const existing = personalBests.find((candidate) => candidate.id === existingId);
    if (!existing) {
      pbBySetId.set(pb.set_id, pb.id);
      continue;
    }

    const pbDate = pb.achieved_at ? new Date(pb.achieved_at).getTime() : 0;
    const existingDate = existing.achieved_at
      ? new Date(existing.achieved_at).getTime()
      : 0;
    if (pbDate < existingDate || (!pb.is_current && existing.is_current)) {
      continue;
    }
    pbBySetId.set(pb.set_id, pb.id);
  }

  return pbBySetId;
}

function setChartInput(set: SessionSetRow) {
  return {
    weight: set.weight,
    reps: set.reps,
    timeSeconds: set.time_seconds,
    distance: set.distance,
  };
}

function pbChartInput(pb: PersonalBestHistoryRow) {
  const raw = pb.raw;
  return {
    weight: typeof raw.weight === "number" ? raw.weight : null,
    reps: pb.reps,
    timeSeconds:
      typeof raw.time_seconds === "number"
        ? raw.time_seconds
        : typeof raw.time === "number"
          ? raw.time
          : null,
    distance: typeof raw.distance === "number" ? raw.distance : null,
  };
}

export function mergeProgressionEntries(params: {
  sessionHistory: ExerciseSetSummary[];
  personalBests: PersonalBestHistoryRow[];
  exercise: ExerciseRow;
  from: Date;
}): ProgressionEntryRow[] {
  const { sessionHistory, personalBests, exercise, from } = params;
  const measurementType = exercise.measurement_type ?? "";
  const fromTime = from.getTime();
  const pbBySetId = pickPbBySetId(personalBests);
  const pbById = new Map(personalBests.map((pb) => [pb.id, pb]));
  const representedSetIds = new Set<string>();
  const merged: ProgressionEntryRow[] = [];

  for (const summary of sessionHistory) {
    representedSetIds.add(summary.set.id);
    const personalBestId = pbBySetId.get(summary.set.id) ?? null;
    const linkedPB = personalBestId ? (pbById.get(personalBestId) ?? null) : null;

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
      isPB: summary.isPB,
      wasReset: linkedPB?.was_reset ?? false,
      setId: summary.set.id,
      personalBestId,
      reps: summary.set.reps,
    });
  }

  for (const pb of personalBests) {
    const achievedTime = pb.achieved_at ? new Date(pb.achieved_at).getTime() : 0;
    if (achievedTime < fromTime) continue;
    if (pb.entry_type === SESSION_DERIVED) continue;
    if (pb.set_id && representedSetIds.has(pb.set_id)) continue;

    const chartInput = pbChartInput(pb);
    merged.push({
      id: pb.id,
      date: pb.achieved_at ?? new Date(0).toISOString(),
      formattedValue: formatSetValues({
        ...chartInput,
        measurementType,
        exerciseName: exercise.name,
      }),
      chartValue: chartValue({
        ...chartInput,
        measurementType,
      }),
      isPB: true,
      wasReset: pb.was_reset,
      setId: pb.set_id,
      personalBestId: pb.id,
      reps: pb.reps,
    });
  }

  return merged.sort((left, right) => {
    const leftTime = new Date(left.date).getTime();
    const rightTime = new Date(right.date).getTime();
    return leftTime - rightTime;
  });
}
