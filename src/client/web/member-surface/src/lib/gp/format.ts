export type MeasurementType =
  | "weightAndReps"
  | "weightAndTime"
  | "timeOnly"
  | "distanceOnly"
  | "repsOnly";

export const CABLE_ROW_NAME = "Cable Row";

export function isCableRow(exerciseName: string | null | undefined): boolean {
  return exerciseName === CABLE_ROW_NAME;
}

export interface FormatPBOptions {
  /** Exercise name — used for Cable Row stack formatting. */
  exerciseName?: string | null;
  /** Reps when formatting weightAndReps display (e.g. `80kg × 5` or `12 × 8`). */
  reps?: number | null;
}

/** Format a scalar personal-best value based on its exercise measurement type. */
export function formatPBValue(
  value: number,
  measurementType: MeasurementType | string,
  options?: FormatPBOptions,
): { primary: string; unit: string } {
  if (isCableRow(options?.exerciseName) && measurementType === "weightAndReps") {
    const reps = options?.reps;
    if (typeof reps === "number") {
      return { primary: `${formatNumber(value)} × ${reps}`, unit: "" };
    }
    return { primary: formatNumber(value), unit: "" };
  }

  switch (measurementType) {
    case "weightAndReps":
    case "weightAndTime":
      return { primary: formatNumber(value), unit: "kg" };
    case "timeOnly":
      return { primary: formatTime(value), unit: "" };
    case "distanceOnly":
      return { primary: formatNumber(value), unit: "m" };
    case "repsOnly":
      return { primary: formatNumber(value), unit: "reps" };
    default:
      return { primary: formatNumber(value), unit: "" };
  }
}

/**
 * Full set / PB display string matching iOS `PBFormatter.formatValues`.
 */
export function formatSetValues(params: {
  weight?: number | null;
  reps?: number | null;
  timeSeconds?: number | null;
  distance?: number | null;
  measurementType: MeasurementType | string;
  exerciseName?: string | null;
}): string {
  const {
    weight,
    reps,
    timeSeconds,
    distance,
    measurementType,
    exerciseName,
  } = params;

  if (isCableRow(exerciseName)) {
    return `${formatNumber(weight ?? 0)} × ${reps ?? 0}`;
  }

  switch (measurementType) {
    case "weightAndReps":
      return `${formatNumber(weight ?? 0)}kg × ${reps ?? 0}`;
    case "weightAndTime":
      return `${formatNumber(weight ?? 0)}kg × ${formatRawSeconds(timeSeconds)}`;
    case "timeOnly":
      return formatTime(timeSeconds ?? 0);
    case "distanceOnly":
      return `${Math.round(distance ?? 0)}m`;
    case "repsOnly":
      return `${reps ?? 0} reps`;
    default: {
      const parts: string[] = [];
      if (typeof weight === "number") parts.push(`${formatNumber(weight)}kg`);
      if (typeof reps === "number") parts.push(`${reps} reps`);
      if (typeof timeSeconds === "number") parts.push(formatTime(timeSeconds));
      if (typeof distance === "number") parts.push(`${distance} m`);
      return parts.length > 0 ? parts.join(" × ") : "—";
    }
  }
}

export function formatNumber(v: number): string {
  if (!Number.isFinite(v)) return "–";
  return Number.isInteger(v) ? String(v) : v.toFixed(1);
}

/** Board row date label — iOS `PBFormatter.shortDate` parity (`d MMM`). */
export function formatBoardPBDate(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleDateString(undefined, {
    day: "numeric",
    month: "short",
  });
}

/** Full PB string for board cards — iOS `PBFormatter.formatPB` parity. */
export function formatBoardPBDisplay(
  pb: {
    value: number;
    reps?: number | null;
    raw?: Record<string, unknown>;
  },
  exercise: {
    name: string;
    measurement_type?: string | null;
  },
): string {
  const measurementType = exercise.measurement_type ?? "";
  const raw = pb.raw ?? {};

  const weight =
    measurementType === "weightAndReps" ||
    measurementType === "weightAndTime" ||
    measurementType === "weightAndDistance"
      ? pb.value
      : typeof raw.weight === "number"
        ? raw.weight
        : typeof raw.weight_kg === "number"
          ? raw.weight_kg
          : null;

  const timeSeconds =
    measurementType === "timeOnly" || measurementType === "weightAndTime"
      ? pb.value
      : typeof raw.time_seconds === "number"
        ? raw.time_seconds
        : typeof raw.time === "number"
          ? raw.time
          : null;

  const distance =
    measurementType === "distanceOnly"
      ? pb.value
      : typeof raw.distance === "number"
        ? raw.distance
        : typeof raw.distance_meters === "number"
          ? raw.distance_meters
          : null;

  const reps =
    pb.reps ??
    (typeof raw.reps === "number"
      ? raw.reps
      : typeof raw.rep_count === "number"
        ? raw.rep_count
        : measurementType === "repsOnly"
          ? pb.value
          : null);

  return formatSetValues({
    weight,
    reps,
    timeSeconds,
    distance,
    measurementType,
    exerciseName: exercise.name,
  });
}

/** iOS-parity display: always `m:ss` (e.g. `0:52`, `1:52`). */
export function formatTime(totalSeconds: number): string {
  if (!Number.isFinite(totalSeconds) || totalSeconds < 0) return "–";
  const total = Math.round(totalSeconds);
  const minutes = Math.floor(total / 60);
  const seconds = total % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

function formatRawSeconds(seconds: number | null | undefined): string {
  if (seconds == null || !Number.isFinite(seconds)) return "0s";
  return `${Math.round(seconds)}s`;
}

/** Scalar used for progression charts (iOS `PBFormatter.chartValue` parity). */
export function chartValue(params: {
  weight?: number | null;
  reps?: number | null;
  timeSeconds?: number | null;
  distance?: number | null;
  measurementType: MeasurementType | string;
}): number {
  const { weight, reps, timeSeconds, distance, measurementType } = params;
  switch (measurementType) {
    case "weightAndReps":
    case "weightAndTime":
      return weight ?? 0;
    case "timeOnly":
      return timeSeconds ?? 0;
    case "distanceOnly":
      return distance ?? 0;
    case "repsOnly":
      return reps ?? 0;
    default:
      return weight ?? timeSeconds ?? distance ?? reps ?? 0;
  }
}

export function fieldsForMeasurement(measurementType: MeasurementType | string) {
  switch (measurementType) {
    case "weightAndReps":
      return ["weight", "reps"] as const;
    case "weightAndTime":
      return ["weight", "time"] as const;
    case "timeOnly":
      return ["time"] as const;
    case "distanceOnly":
      return ["distance"] as const;
    case "repsOnly":
      return ["reps"] as const;
    default:
      return [] as const;
  }
}

/** Split total seconds into mm / ss for form inputs. */
export function splitMmSs(totalSeconds: number | null | undefined): {
  mm: string;
  ss: string;
} {
  if (totalSeconds == null || !Number.isFinite(totalSeconds) || totalSeconds < 0) {
    return { mm: "", ss: "" };
  }
  const total = Math.round(totalSeconds);
  return {
    mm: String(Math.floor(total / 60)),
    ss: String(total % 60),
  };
}

/**
 * Combine mm + ss form strings into total seconds.
 * Returns null if either part is missing/invalid.
 */
export function combineMmSs(
  mmRaw: string | undefined,
  ssRaw: string | undefined,
): number | null {
  const mmTrim = mmRaw?.trim() ?? "";
  const ssTrim = ssRaw?.trim() ?? "";
  if (mmTrim === "" && ssTrim === "") return null;
  const mm = mmTrim === "" ? 0 : Number(mmTrim);
  const ss = ssTrim === "" ? 0 : Number(ssTrim);
  if (!Number.isFinite(mm) || !Number.isFinite(ss) || mm < 0 || ss < 0) {
    return null;
  }
  if (ss >= 60) return null;
  return Math.round(mm) * 60 + Math.round(ss);
}

export function fieldLabel(
  field: string,
  measurementType: MeasurementType | string,
  exerciseName?: string | null,
): string {
  if (field === "weight" && isCableRow(exerciseName)) return "Stack";
  if (field === "time" && measurementType === "timeOnly") return "Time";
  const labels: Record<string, string> = {
    weight: "Weight",
    reps: "Reps",
    time: "Time",
    distance: "Distance",
  };
  return labels[field] ?? field;
}

export function fieldUnit(
  field: string,
  measurementType: MeasurementType | string,
  exerciseName?: string | null,
): string {
  if (field === "weight" && isCableRow(exerciseName)) return "";
  if (field === "time" && measurementType === "timeOnly") return "";
  const units: Record<string, string> = {
    weight: "kg",
    reps: "",
    time: "s",
    distance: "m",
  };
  return units[field] ?? "";
}
