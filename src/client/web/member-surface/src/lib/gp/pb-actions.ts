import {
  ADD_MANUAL_PB_URL,
  DELETE_PERSONAL_BEST_URL,
  RESET_CURRENT_PB_URL,
} from "./env";

export interface PersonalBestRecord {
  id: string;
  exercise_id: string;
  set_id: string | null;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
  achieved_at: string | null;
  entry_type: string;
}

export interface ExerciseResetRecord {
  id: string;
  exercise_id: string;
  reset_at: string;
}

export interface AddManualPBInput {
  exerciseId: string;
  /** Null / omit = undated lifetime entry. */
  achievedAt?: string | null;
  weight?: number;
  reps?: number;
  time_seconds?: number;
  distance?: number;
}

export interface AddManualPBResult {
  isNewPB: boolean;
  personalBest: PersonalBestRecord | null;
}

export interface ResetCurrentPBResult {
  success: boolean;
  exerciseReset: ExerciseResetRecord | null;
}

export interface DeletePersonalBestInput {
  exerciseId: string;
  personalBestId: string;
}

export interface DeletePersonalBestResult {
  deleted: PersonalBestRecord | null;
}

async function postJson<T>(
  url: string,
  token: string,
  body: Record<string, unknown>,
): Promise<T> {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });

  const raw = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  if (!response.ok) {
    const msg =
      (typeof raw.error === "string" && raw.error) ||
      (typeof raw.message === "string" && raw.message) ||
      `Request failed (${response.status})`;
    throw new Error(msg);
  }

  return raw as T;
}

export async function addManualPB(
  token: string,
  input: AddManualPBInput,
): Promise<AddManualPBResult> {
  const body: Record<string, unknown> = {
    exerciseId: input.exerciseId,
    achievedAt: input.achievedAt ?? null,
  };
  if (typeof input.weight === "number") body.weight = input.weight;
  if (typeof input.reps === "number") body.reps = input.reps;
  if (typeof input.time_seconds === "number") body.time_seconds = input.time_seconds;
  if (typeof input.distance === "number") body.distance = input.distance;

  const raw = await postJson<Record<string, unknown>>(ADD_MANUAL_PB_URL, token, body);
  return {
    isNewPB: Boolean(raw.isNewPB),
    personalBest: (raw.personalBest as PersonalBestRecord | null) ?? null,
  };
}

export async function resetCurrentPB(
  token: string,
  exerciseId: string,
  options?: { undo?: boolean },
): Promise<ResetCurrentPBResult> {
  const raw = await postJson<Record<string, unknown>>(RESET_CURRENT_PB_URL, token, {
    exerciseId,
    ...(options?.undo ? { undo: true } : {}),
  });
  return {
    success: Boolean(raw.success ?? true),
    exerciseReset: (raw.exerciseReset as ExerciseResetRecord | null) ?? null,
  };
}

export async function deletePersonalBest(
  token: string,
  input: DeletePersonalBestInput,
): Promise<DeletePersonalBestResult> {
  const raw = await postJson<Record<string, unknown>>(
    DELETE_PERSONAL_BEST_URL,
    token,
    {
      exerciseId: input.exerciseId,
      personalBestId: input.personalBestId,
    },
  );
  return {
    deleted: (raw.deleted as PersonalBestRecord | null) ?? null,
  };
}
