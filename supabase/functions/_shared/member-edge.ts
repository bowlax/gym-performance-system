/**
 * Shared helpers for member-scoped Edge Functions (JWT + RLS user client).
 */

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { PBRule, SetState } from "./pb-evaluation.ts";

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

export const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

export const PB_RULES: readonly PBRule[] = [
  "heaviestWeight",
  "heaviestWeightAtReps",
  "bestWeightAndReps",
  "fastestTime",
  "longestDistance",
  "mostReps",
];

export type MeasurementType =
  | "weightAndReps"
  | "weightAndTime"
  | "timeOnly"
  | "distanceOnly"
  | "repsOnly"
  | "weightAndDistance";

export interface JwtClaims {
  memberId: string;
  gymId: string;
}

export interface ExerciseRow {
  id: string;
  gym_id: string;
  pb_rule: string | null;
  target_reps: number | null;
  minimum_reps: number | null;
  category: string;
  measurement_type: string;
  is_active: boolean;
}

export interface PersonalBestRow {
  id: string;
  gym_id: string;
  member_id: string;
  exercise_id: string;
  set_id: string | null;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
  achieved_at: string | null;
  entry_type: string;
  deleted_at?: string | null;
}

export interface ExerciseResetRow {
  id: string;
  gym_id: string;
  member_id: string;
  exercise_id: string;
  reset_at: string;
  created_at: string;
  updated_at: string;
  deleted_at?: string | null;
}

export interface SetRow {
  id: string;
  gym_id: string;
  exercise_entry_id: string;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
  deleted_at?: string | null;
}

export type UserClient = SupabaseClient;

export function jsonResponse(
  body: Record<string, unknown>,
  status: number,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function isUuid(value: string): boolean {
  return UUID_PATTERN.test(value);
}

export function isPbRule(value: string): value is PBRule {
  return (PB_RULES as readonly string[]).includes(value);
}

export function optionalNumber(value: unknown): number | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return null;
}

export function optionalString(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === "string") {
    return value;
  }
  return null;
}

function parseNamedKeys(envName: string): string | null {
  const raw = Deno.env.get(envName);
  if (!raw) {
    return null;
  }

  try {
    const keys = JSON.parse(raw) as Record<string, string>;
    const defaultKey = keys["default"];
    if (typeof defaultKey === "string" && defaultKey.length > 0) {
      return defaultKey;
    }
  } catch {
    if (raw.length > 0) {
      return raw;
    }
  }

  return null;
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function getAnonKey(): string {
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (anonKey) {
    return anonKey;
  }

  const publishableKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  if (publishableKey) {
    return publishableKey;
  }

  const namedPublishableKey = parseNamedKeys("SUPABASE_PUBLISHABLE_KEYS");
  if (namedPublishableKey) {
    return namedPublishableKey;
  }

  throw new Error(
    "Missing publishable API key (SUPABASE_ANON_KEY, SUPABASE_PUBLISHABLE_KEY, or SUPABASE_PUBLISHABLE_KEYS)",
  );
}

export function decodeJwtClaims(authHeader: string | null): JwtClaims | null {
  if (!authHeader?.startsWith("Bearer ")) {
    return null;
  }

  const token = authHeader.slice("Bearer ".length).trim();
  const parts = token.split(".");
  if (parts.length !== 3) {
    return null;
  }

  try {
    const payload = JSON.parse(
      atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")),
    ) as Record<string, unknown>;

    const memberId = payload.member_id;
    const gymId = payload.gym_id;

    if (typeof memberId !== "string" || !isUuid(memberId)) {
      return null;
    }
    if (typeof gymId !== "string" || !isUuid(gymId)) {
      return null;
    }

    return { memberId, gymId };
  } catch {
    return null;
  }
}

export function createUserClient(authHeader: string): UserClient {
  return createClient(requireEnv("SUPABASE_URL"), getAnonKey(), {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export function todayUtcDateString(): string {
  return new Date().toISOString().slice(0, 10);
}

export function isFutureDate(date: string): boolean {
  return date > todayUtcDateString();
}

export function personalBestToEvaluationState(pb: PersonalBestRow): SetState {
  return {
    weight: pb.weight,
    reps: pb.reps,
    time: pb.time_seconds,
    distance: pb.distance,
  };
}

export function validateMeasurementFields(
  measurementType: string,
  values: {
    weight: number | null;
    reps: number | null;
    time_seconds: number | null;
    distance: number | null;
  },
): boolean {
  switch (measurementType as MeasurementType) {
    case "weightAndReps":
      return values.weight != null && values.reps != null;
    case "weightAndTime":
      return values.weight != null && values.time_seconds != null;
    case "timeOnly":
      return values.time_seconds != null;
    case "distanceOnly":
      return values.distance != null;
    case "repsOnly":
      return values.reps != null;
    case "weightAndDistance":
      return values.weight != null && values.distance != null;
    default:
      return false;
  }
}

export async function fetchExercise(
  supabase: UserClient,
  exerciseId: string,
  gymId: string,
): Promise<ExerciseRow> {
  const { data, error } = await supabase
    .from("exercises")
    .select(
      "id, gym_id, pb_rule, target_reps, minimum_reps, category, measurement_type, is_active",
    )
    .eq("id", exerciseId)
    .is("deleted_at", null)
    .maybeSingle();

  if (error) {
    throw error;
  }
  if (!data) {
    throw jsonResponse({ error: "Exercise not found" }, 404);
  }

  const exercise = data as ExerciseRow;
  if (exercise.gym_id !== gymId) {
    throw jsonResponse({ error: "Exercise not in member gym" }, 403);
  }
  if (!exercise.is_active) {
    throw jsonResponse({ error: "Exercise is not active" }, 400);
  }

  return exercise;
}

export async function fetchPersonalBestById(
  supabase: UserClient,
  personalBestId: string,
  memberId: string,
  exerciseId: string,
  gymId: string,
): Promise<PersonalBestRow> {
  const { data, error } = await supabase
    .from("personal_bests")
    .select(
      "id, gym_id, member_id, exercise_id, set_id, weight, reps, time_seconds, distance, achieved_at, entry_type",
    )
    .eq("id", personalBestId)
    .eq("member_id", memberId)
    .eq("exercise_id", exerciseId)
    .eq("gym_id", gymId)
    .eq("entry_type", "manualEntry")
    .is("deleted_at", null)
    .maybeSingle();

  if (error) {
    throw error;
  }
  if (!data) {
    throw jsonResponse({ error: "Personal best not found" }, 404);
  }

  return data as PersonalBestRow;
}

export async function softDeletePersonalBest(
  supabase: UserClient,
  personalBestId: string,
): Promise<void> {
  const now = new Date().toISOString();
  const { error } = await supabase
    .from("personal_bests")
    .update({ deleted_at: now, updated_at: now })
    .eq("id", personalBestId);

  if (error) {
    throw error;
  }
}

export async function softDeleteSet(
  supabase: UserClient,
  setId: string,
): Promise<void> {
  const now = new Date().toISOString();
  const { error } = await supabase
    .from("sets")
    .update({ deleted_at: now, updated_at: now })
    .eq("id", setId);

  if (error) {
    throw error;
  }
}

interface PostgrestErrorLike {
  message?: string;
  details?: string;
  hint?: string;
  code?: string;
}

export function logSupabaseError(
  context: string,
  error: PostgrestErrorLike,
): void {
  console.error(`${context} supabase error message:`, error.message);
  if (error.details) {
    console.error(`${context} supabase error details:`, error.details);
  }
  if (error.hint) {
    console.error(`${context} supabase error hint:`, error.hint);
  }
  if (error.code) {
    console.error(`${context} supabase error code:`, error.code);
  }
}

export function logCaughtError(context: string, error: unknown): void {
  console.error(`${context} failed`);
  if (error instanceof Error) {
    console.error(`${context} error message:`, error.message);
    if (error.stack) {
      console.error(`${context} error stack:`, error.stack);
    }
    return;
  }
  if (error instanceof Response) {
    return;
  }
  if (typeof error === "object" && error !== null) {
    logSupabaseError(context, error as PostgrestErrorLike);
    return;
  }
  console.error(`${context} error value:`, String(error));
}

export function handleEdgeRequest(
  handler: (req: Request, claims: JwtClaims, authHeader: string) => Promise<Response>,
): void {
  Deno.serve(async (req) => {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    const authHeader = req.headers.get("Authorization");
    const claims = decodeJwtClaims(authHeader);
    if (!claims || !authHeader) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    try {
      return await handler(req, claims, authHeader);
    } catch (error) {
      if (error instanceof Response) {
        return error;
      }
      logCaughtError("edge", error);
      return jsonResponse({ error: "Internal server error" }, 500);
    }
  });
}
