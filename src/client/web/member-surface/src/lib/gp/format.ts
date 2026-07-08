export type MeasurementType =
  | "weightAndReps"
  | "weightAndTime"
  | "timeOnly"
  | "distanceOnly"
  | "repsOnly";

/** Format a scalar personal-best value based on its exercise measurement type. */
export function formatPBValue(
  value: number,
  measurementType: MeasurementType | string,
): { primary: string; unit: string } {
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

export function formatNumber(v: number): string {
  if (!Number.isFinite(v)) return "–";
  return Number.isInteger(v) ? String(v) : v.toFixed(1);
}

export function formatTime(totalSeconds: number): string {
  if (!Number.isFinite(totalSeconds) || totalSeconds < 0) return "–";
  if (totalSeconds < 60) return `${formatNumber(totalSeconds)}s`;
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = Math.round(totalSeconds % 60);
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
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