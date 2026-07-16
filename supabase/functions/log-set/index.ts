/**
 * Log Set — Supabase Edge Function
 *
 * Logs a single set for a web member. PB evaluation is client-side via derivation (#28 step 4).
 *
 * Requires `Authorization: Bearer <supabase-jwt>` with claims: member_id, gym_id.
 */

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

interface JwtClaims {
  memberId: string;
  gymId: string;
}

interface SessionInput {
  id?: string;
  date: string;
  notes?: string | null;
  calories_burned?: number | null;
}

interface SetInput {
  id?: string;
  weight?: number | null;
  reps?: number | null;
  time_seconds?: number | null;
  distance?: number | null;
}

interface LogSetRequest {
  sessionId?: string;
  session?: SessionInput;
  exerciseId: string;
  exerciseEntryId?: string;
  set: SetInput;
}

interface SessionRow {
  id: string;
  date: string;
  gym_id: string;
  member_id: string;
}

interface ExerciseRow {
  id: string;
  gym_id: string;
  category: string;
  is_active: boolean;
}

interface ExerciseEntryRow {
  id: string;
  session_id: string;
  exercise_id: string;
  gym_id: string;
}

interface SetRow {
  id: string;
  gym_id: string;
  exercise_entry_id: string;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
  created_at: string;
  updated_at: string;
}

type UserClient = SupabaseClient;

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isUuid(value: string): boolean {
  return UUID_PATTERN.test(value);
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
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

function decodeJwtClaims(authHeader: string | null): JwtClaims | null {
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

function createUserClient(authHeader: string): UserClient {
  return createClient(requireEnv("SUPABASE_URL"), getAnonKey(), {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

function optionalNumber(value: unknown): number | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return null;
}

function optionalString(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === "string") {
    return value;
  }
  return null;
}

function parseLogSetRequest(body: unknown): LogSetRequest | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }

  const record = body as Record<string, unknown>;

  if (typeof record.exerciseId !== "string" || !isUuid(record.exerciseId)) {
    return null;
  }

  if (typeof record.set !== "object" || record.set === null) {
    return null;
  }

  const setRecord = record.set as Record<string, unknown>;
  if (setRecord.id != null && (typeof setRecord.id !== "string" || !isUuid(setRecord.id))) {
    return null;
  }

  const set: SetInput = {
    id: typeof setRecord.id === "string" ? setRecord.id : undefined,
    weight: optionalNumber(setRecord.weight),
    reps: optionalNumber(setRecord.reps),
    time_seconds: optionalNumber(setRecord.time_seconds),
    distance: optionalNumber(setRecord.distance),
  };

  let sessionId: string | undefined;
  if (record.sessionId != null) {
    if (typeof record.sessionId !== "string" || !isUuid(record.sessionId)) {
      return null;
    }
    sessionId = record.sessionId;
  }

  let session: SessionInput | undefined;
  if (record.session != null) {
    if (typeof record.session !== "object") {
      return null;
    }
    const sessionRecord = record.session as Record<string, unknown>;
    if (typeof sessionRecord.date !== "string" || !DATE_PATTERN.test(sessionRecord.date)) {
      return null;
    }
    if (
      sessionRecord.id != null &&
      (typeof sessionRecord.id !== "string" || !isUuid(sessionRecord.id))
    ) {
      return null;
    }
    session = {
      id: typeof sessionRecord.id === "string" ? sessionRecord.id : undefined,
      date: sessionRecord.date,
      notes: optionalString(sessionRecord.notes),
      calories_burned: optionalNumber(sessionRecord.calories_burned),
    };
  }

  if (!sessionId && !session) {
    return null;
  }

  let exerciseEntryId: string | undefined;
  if (record.exerciseEntryId != null) {
    if (typeof record.exerciseEntryId !== "string" || !isUuid(record.exerciseEntryId)) {
      return null;
    }
    exerciseEntryId = record.exerciseEntryId;
  }

  return {
    sessionId,
    session,
    exerciseId: record.exerciseId,
    exerciseEntryId,
    set,
  };
}

async function resolveSession(
  supabase: UserClient,
  request: LogSetRequest,
  claims: JwtClaims,
): Promise<SessionRow> {
  if (request.sessionId) {
    const { data, error } = await supabase
      .from("sessions")
      .select("id, date, gym_id, member_id")
      .eq("id", request.sessionId)
      .is("deleted_at", null)
      .maybeSingle();

    if (error) {
      throw error;
    }
    if (!data) {
      throw new Response(JSON.stringify({ error: "Session not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const session = data as SessionRow;
    if (session.gym_id !== claims.gymId || session.member_id !== claims.memberId) {
      throw new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return session;
  }

  const sessionInput = request.session!;
  const sessionId = sessionInput.id ?? crypto.randomUUID();

  const { data, error } = await supabase
    .from("sessions")
    .insert({
      id: sessionId,
      gym_id: claims.gymId,
      member_id: claims.memberId,
      date: sessionInput.date,
      notes: sessionInput.notes ?? null,
      calories_burned: sessionInput.calories_burned ?? null,
    })
    .select("id, date, gym_id, member_id")
    .single();

  if (error) {
    throw error;
  }

  return data as SessionRow;
}

async function fetchExercise(
  supabase: UserClient,
  exerciseId: string,
  gymId: string,
): Promise<ExerciseRow> {
  const { data, error } = await supabase
    .from("exercises")
    .select("id, gym_id, category, is_active")
    .eq("id", exerciseId)
    .is("deleted_at", null)
    .maybeSingle();

  if (error) {
    throw error;
  }
  if (!data) {
    throw new Response(JSON.stringify({ error: "Exercise not found" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const exercise = data as ExerciseRow;
  if (exercise.gym_id !== gymId) {
    throw new Response(JSON.stringify({ error: "Exercise not in member gym" }), {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  if (!exercise.is_active) {
    throw new Response(JSON.stringify({ error: "Exercise is not active" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  return exercise;
}

async function resolveExerciseEntry(
  supabase: UserClient,
  session: SessionRow,
  exerciseId: string,
  exerciseEntryId: string | undefined,
  gymId: string,
): Promise<ExerciseEntryRow> {
  if (exerciseEntryId) {
    const { data, error } = await supabase
      .from("exercise_entries")
      .select("id, session_id, exercise_id, gym_id")
      .eq("id", exerciseEntryId)
      .is("deleted_at", null)
      .maybeSingle();

    if (error) {
      throw error;
    }
    if (!data) {
      throw new Response(JSON.stringify({ error: "Exercise entry not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const entry = data as ExerciseEntryRow;
    if (
      entry.session_id !== session.id ||
      entry.exercise_id !== exerciseId ||
      entry.gym_id !== gymId
    ) {
      throw new Response(JSON.stringify({ error: "Exercise entry mismatch" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return entry;
  }

  const { data: existing, error: lookupError } = await supabase
    .from("exercise_entries")
    .select("id, session_id, exercise_id, gym_id")
    .eq("session_id", session.id)
    .eq("exercise_id", exerciseId)
    .is("deleted_at", null)
    .maybeSingle();

  if (lookupError) {
    throw lookupError;
  }
  if (existing) {
    return existing as ExerciseEntryRow;
  }

  const newEntryId = crypto.randomUUID();
  const { data: created, error: insertError } = await supabase
    .from("exercise_entries")
    .insert({
      id: newEntryId,
      gym_id: gymId,
      session_id: session.id,
      exercise_id: exerciseId,
    })
    .select("id, session_id, exercise_id, gym_id")
    .single();

  if (insertError) {
    throw insertError;
  }

  return created as ExerciseEntryRow;
}

async function insertSet(
  supabase: UserClient,
  exerciseEntryId: string,
  gymId: string,
  setInput: SetInput,
): Promise<SetRow> {
  const setId = setInput.id ?? crypto.randomUUID();

  const { data, error } = await supabase
    .from("sets")
    .insert({
      id: setId,
      gym_id: gymId,
      exercise_entry_id: exerciseEntryId,
      weight: setInput.weight ?? null,
      reps: setInput.reps ?? null,
      time_seconds: setInput.time_seconds ?? null,
      distance: setInput.distance ?? null,
    })
    .select("id, gym_id, exercise_entry_id, weight, reps, time_seconds, distance, created_at, updated_at")
    .single();

  if (error) {
    throw error;
  }

  return data as SetRow;
}

function logCaughtError(error: unknown): void {
  console.error("log-set failed");
  if (error instanceof Error) {
    console.error("log-set error message:", error.message);
    if (error.stack) {
      console.error("log-set error stack:", error.stack);
    }
    return;
  }
  if (error instanceof Response) {
    return;
  }
  console.error("log-set error value:", String(error));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  const claims = decodeJwtClaims(authHeader);
  if (!claims) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const request = parseLogSetRequest(body);
    if (!request) {
      return jsonResponse(
        {
          error:
            "Invalid request body. Provide exerciseId, set, and either sessionId or session.date.",
        },
        400,
      );
    }

    const supabase = createUserClient(authHeader!);

    const session = await resolveSession(supabase, request, claims);
    await fetchExercise(supabase, request.exerciseId, claims.gymId);
    const exerciseEntry = await resolveExerciseEntry(
      supabase,
      session,
      request.exerciseId,
      request.exerciseEntryId,
      claims.gymId,
    );
    const createdSet = await insertSet(
      supabase,
      exerciseEntry.id,
      claims.gymId,
      request.set,
    );

    return jsonResponse({ set: createdSet }, 200);
  } catch (error) {
    if (error instanceof Response) {
      return error;
    }
    logCaughtError(error);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
