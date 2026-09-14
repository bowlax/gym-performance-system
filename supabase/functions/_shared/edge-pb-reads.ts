/**
 * Edge-function helpers to derive current PB from sets + manual entries (#28 step 4).
 * Mirrors web `derive-pb-reads.ts` for write-time evaluation in add-manual-pb.
 */

import {
  badgeIds,
  derivePBs,
  type DerivationRecord,
  type StalenessSetting,
} from "./pb-derivation.ts";
import { evaluatePB, type PBRule, type SetState } from "./pb-evaluation.ts";
import type { ExerciseRow, PersonalBestRow, UserClient } from "./member-edge.ts";
import { todayUtcDateString } from "./member-edge.ts";

const MANUAL_ENTRY = "manualEntry";

function mapStalenessUnit(dbUnit: string): StalenessSetting["unit"] {
  return dbUnit === "month" ? "months" : "quarters";
}

export async function fetchMemberStaleness(
  supabase: UserClient,
  memberId: string,
): Promise<StalenessSetting> {
  const { data, error } = await supabase
    .from("members")
    .select("staleness_enabled, staleness_periods, staleness_unit")
    .eq("id", memberId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    return { enabled: false, periods: 2, unit: "quarters" };
  }

  const row = data as Record<string, unknown>;
  return {
    enabled: Boolean(row.staleness_enabled),
    periods:
      typeof row.staleness_periods === "number" && row.staleness_periods >= 1
        ? row.staleness_periods
        : 2,
    unit: mapStalenessUnit(
      typeof row.staleness_unit === "string" ? row.staleness_unit : "quarter",
    ),
  };
}

function optionalTimestamp(value: unknown): string | null {
  return typeof value === "string" && value !== "" ? value : null;
}

export type ExerciseResetLine = {
  resetAt: string;
  resetOccurredAt: string | null;
};

export async function fetchExerciseResetAt(
  supabase: UserClient,
  memberId: string,
  exerciseId: string,
): Promise<ExerciseResetLine | null> {
  const { data, error } = await supabase
    .from("exercise_resets")
    .select("reset_at, updated_at")
    .eq("member_id", memberId)
    .eq("exercise_id", exerciseId)
    .is("deleted_at", null)
    .maybeSingle();

  if (error) {
    throw error;
  }

  const row = data as { reset_at?: string; updated_at?: string } | null;
  if (typeof row?.reset_at !== "string") {
    return null;
  }
  return {
    resetAt: row.reset_at,
    resetOccurredAt: optionalTimestamp(row.updated_at),
  };
}

interface SetDerivationRow {
  id: string;
  session_date: string;
  created_at: string | null;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
}

export async function fetchExerciseSetsForDerivation(
  supabase: UserClient,
  exerciseId: string,
  memberId?: string,
): Promise<SetDerivationRow[]> {
  let query = supabase
    .from("exercise_entries")
    .select(
      "session:sessions!inner(date, member_id), sets(id, weight, reps, time_seconds, distance, deleted_at, created_at)",
    )
    .eq("exercise_id", exerciseId)
    .is("deleted_at", null)
    .is("session.deleted_at", null);
  if (memberId) {
    query = query.eq("session.member_id", memberId);
  }

  const { data, error } = await query;

  if (error) {
    throw error;
  }

  const rows: SetDerivationRow[] = [];
  for (const entry of data ?? []) {
    const record = entry as Record<string, unknown>;
    const session = Array.isArray(record.session)
      ? record.session[0]
      : record.session;
    const sessionDate =
      session && typeof (session as Record<string, unknown>).date === "string"
        ? (session as Record<string, unknown>).date as string
        : null;
    if (!sessionDate) continue;

    for (const set of (record.sets ?? []) as Array<Record<string, unknown>>) {
      if (set.deleted_at != null) continue;
      if (typeof set.id !== "string") continue;
      rows.push({
        id: set.id,
        session_date: sessionDate,
        created_at: optionalTimestamp(set.created_at),
        weight: typeof set.weight === "number" ? set.weight : null,
        reps: typeof set.reps === "number" ? set.reps : null,
        time_seconds: typeof set.time_seconds === "number" ? set.time_seconds : null,
        distance: typeof set.distance === "number" ? set.distance : null,
      });
    }
  }

  return rows;
}

export async function fetchManualPBsForDerivation(
  supabase: UserClient,
  memberId: string,
  exerciseId: string,
): Promise<PersonalBestRow[]> {
  const { data, error } = await supabase
    .from("personal_bests")
    .select(
      "id, gym_id, member_id, exercise_id, set_id, weight, reps, time_seconds, distance, achieved_at, entry_type, created_at",
    )
    .eq("member_id", memberId)
    .eq("exercise_id", exerciseId)
    .eq("entry_type", MANUAL_ENTRY)
    .is("deleted_at", null);

  if (error) {
    throw error;
  }

  return (data as PersonalBestRow[] | null) ?? [];
}

export function recordsFromStore(
  sets: SetDerivationRow[],
  manuals: PersonalBestRow[],
): DerivationRecord[] {
  const records: DerivationRecord[] = [];

  for (const set of sets) {
    records.push({
      id: set.id,
      achievedAt: set.session_date,
      occurredAt: set.created_at,
      weight: set.weight,
      reps: set.reps,
      time: set.time_seconds,
      distance: set.distance,
      entryKind: "set",
    });
  }

  for (const pb of manuals) {
    records.push({
      id: pb.id,
      achievedAt: pb.achieved_at,
      occurredAt: pb.created_at ?? null,
      weight: pb.weight,
      reps: pb.reps,
      time: pb.time_seconds,
      distance: pb.distance,
      entryKind: "manual",
    });
  }

  return records;
}

export async function deriveCurrentPBState(
  supabase: UserClient,
  memberId: string,
  exercise: ExerciseRow,
): Promise<{
  currentPB: DerivationRecord | null;
  staleness: StalenessSetting;
  resetAt: string | null;
}> {
  if (!exercise.pb_rule) {
    return { currentPB: null, staleness: { enabled: false, periods: 2, unit: "quarters" }, resetAt: null };
  }

  const [staleness, resetLine, sets, manuals] = await Promise.all([
    fetchMemberStaleness(supabase, memberId),
    fetchExerciseResetAt(supabase, memberId, exercise.id),
    fetchExerciseSetsForDerivation(supabase, exercise.id, memberId),
    fetchManualPBsForDerivation(supabase, memberId, exercise.id),
  ]);

  const records = recordsFromStore(sets, manuals);
  const derived = derivePBs({
    rule: exercise.pb_rule as PBRule,
    records,
    staleness,
    resetAt: resetLine?.resetAt ?? null,
    resetOccurredAt: resetLine?.resetOccurredAt ?? null,
    evaluatedAt: todayUtcDateString(),
  });

  return { currentPB: derived.currentPB, staleness, resetAt: resetLine?.resetAt ?? null };
}

export function personalBestToEvaluationState(
  record: DerivationRecord | PersonalBestRow,
): SetState {
  if ("time_seconds" in record) {
    const pb = record as PersonalBestRow;
    return {
      weight: pb.weight,
      reps: pb.reps,
      time: pb.time_seconds,
      distance: pb.distance,
    };
  }
  const derived = record as DerivationRecord;
  return {
    weight: derived.weight ?? null,
    reps: derived.reps ?? null,
    time: derived.time ?? null,
    distance: derived.distance ?? null,
  };
}

export function isManualPB(
  exercise: ExerciseRow,
  currentPB: DerivationRecord | null,
  candidate: SetState,
): boolean {
  if (!exercise.pb_rule) {
    return false;
  }
  return evaluatePB({
    rule: exercise.pb_rule as PBRule,
    currentPB: currentPB ? personalBestToEvaluationState(currentPB) : null,
    newSet: candidate,
    ruleParameters: {
      targetReps: exercise.target_reps,
      minimumReps: exercise.minimum_reps,
    },
  }).isPB;
}

export function resetAtForToday(): string {
  return todayUtcDateString();
}

export function laterResetDate(existing: string, candidate: string): string {
  return candidate > existing ? candidate : existing;
}

export async function fetchOwnerSurfaceGrant(
  supabase: UserClient,
): Promise<string | null> {
  const { data, error } = await supabase
    .from("owner_surface_grants")
    .select("gym_id")
    .maybeSingle();

  if (error) {
    throw error;
  }

  const gymId = (data as { gym_id?: string } | null)?.gym_id;
  return typeof gymId === "string" ? gymId : null;
}

export interface OwnerCurrentPBSummary {
  member_id: string;
  teamup_customer_id: string | null;
  exercise_id: string;
  exercise_name: string;
  value: number;
  reps: number | null;
  achieved_at: string | null;
}

interface GymMemberSource {
  id: string;
  teamup_customer_id: string | null;
  staleness: StalenessSetting;
}

interface GymExerciseSource {
  id: string;
  name: string;
  pb_rule: PBRule;
  measurement_type: string;
}

function scalarValueForMeasurement(
  record: DerivationRecord,
  measurementType: string,
): number {
  switch (measurementType) {
    case "timeOnly":
      return record.time ?? NaN;
    case "distanceOnly":
      return record.distance ?? NaN;
    case "repsOnly":
      return record.reps ?? NaN;
    default:
      return record.weight ?? NaN;
  }
}

function stalenessFromMemberRow(row: Record<string, unknown>): StalenessSetting {
  return {
    enabled: Boolean(row.staleness_enabled),
    periods:
      typeof row.staleness_periods === "number" && row.staleness_periods >= 1
        ? row.staleness_periods
        : 2,
    unit: mapStalenessUnit(
      typeof row.staleness_unit === "string" ? row.staleness_unit : "quarter",
    ),
  };
}

interface GymDerivationSources {
  members: GymMemberSource[];
  exercises: GymExerciseSource[];
  recordsByMemberExercise: Map<string, DerivationRecord[]>;
  resetLineByMemberExercise: Map<string, ExerciseResetLine>;
}

async function fetchGymDerivationSources(
  supabase: UserClient,
): Promise<GymDerivationSources> {
  const [membersResult, exercisesResult, entriesResult, manualsResult, resetsResult] =
    await Promise.all([
      supabase
        .from("members")
        .select(
          "id, teamup_customer_id, staleness_enabled, staleness_periods, staleness_unit",
        )
        .is("deleted_at", null),
      supabase
        .from("exercises")
        .select("id, name, pb_rule, measurement_type")
        .eq("is_active", true)
        .not("pb_rule", "is", null)
        .is("deleted_at", null),
      // sessions!inner does not imply deleted_at is null; a session-only
      // tombstone would otherwise still feed its live child sets into
      // owner-current-pbs and owner-pb-frequency.
      supabase
        .from("exercise_entries")
        .select(
          "exercise_id, session:sessions!inner(date, member_id), sets(id, weight, reps, time_seconds, distance, deleted_at, created_at)",
        )
        .is("deleted_at", null)
        .is("session.deleted_at", null),
      supabase
        .from("personal_bests")
        .select(
          "id, member_id, exercise_id, weight, reps, time_seconds, distance, achieved_at, entry_type, created_at",
        )
        .eq("entry_type", MANUAL_ENTRY)
        .is("deleted_at", null),
      supabase
        .from("exercise_resets")
        .select("member_id, exercise_id, reset_at, updated_at")
        .is("deleted_at", null),
    ]);

  if (membersResult.error) throw membersResult.error;
  if (exercisesResult.error) throw exercisesResult.error;
  if (entriesResult.error) throw entriesResult.error;
  if (manualsResult.error) throw manualsResult.error;
  if (resetsResult.error) throw resetsResult.error;

  const members: GymMemberSource[] = (membersResult.data ?? []).map((row) => {
    const record = row as Record<string, unknown>;
    return {
      id: String(record.id),
      teamup_customer_id:
        typeof record.teamup_customer_id === "string"
          ? record.teamup_customer_id
          : null,
      staleness: stalenessFromMemberRow(record),
    };
  });

  const exercises: GymExerciseSource[] = [];
  for (const row of exercisesResult.data ?? []) {
    const record = row as Record<string, unknown>;
    if (typeof record.id !== "string" || typeof record.pb_rule !== "string") {
      continue;
    }
    if (typeof record.name !== "string") continue;
    exercises.push({
      id: record.id,
      name: record.name,
      pb_rule: record.pb_rule as PBRule,
      measurement_type:
        typeof record.measurement_type === "string" ? record.measurement_type : "",
    });
  }

  const recordsByMemberExercise = new Map<string, DerivationRecord[]>();
  const addRecord = (
    memberId: string,
    exerciseId: string,
    record: DerivationRecord,
  ) => {
    const key = `${memberId}:${exerciseId}`;
    const bucket = recordsByMemberExercise.get(key) ?? [];
    bucket.push(record);
    recordsByMemberExercise.set(key, bucket);
  };

  for (const entry of entriesResult.data ?? []) {
    const record = entry as Record<string, unknown>;
    const exerciseId =
      typeof record.exercise_id === "string" ? record.exercise_id : null;
    const session = Array.isArray(record.session)
      ? record.session[0]
      : record.session;
    const sessionRecord = session as Record<string, unknown> | null;
    const memberId =
      sessionRecord && typeof sessionRecord.member_id === "string"
        ? sessionRecord.member_id
        : null;
    const sessionDate =
      sessionRecord && typeof sessionRecord.date === "string"
        ? sessionRecord.date
        : null;
    if (!exerciseId || !memberId || !sessionDate) continue;

    for (const set of (record.sets ?? []) as Array<Record<string, unknown>>) {
      if (set.deleted_at != null) continue;
      if (typeof set.id !== "string") continue;
      addRecord(memberId, exerciseId, {
        id: set.id,
        achievedAt: sessionDate,
        occurredAt: optionalTimestamp(set.created_at),
        weight: typeof set.weight === "number" ? set.weight : null,
        reps: typeof set.reps === "number" ? set.reps : null,
        time: typeof set.time_seconds === "number" ? set.time_seconds : null,
        distance: typeof set.distance === "number" ? set.distance : null,
        entryKind: "set",
      });
    }
  }

  for (const pb of manualsResult.data ?? []) {
    const record = pb as Record<string, unknown>;
    if (typeof record.id !== "string") continue;
    if (typeof record.member_id !== "string") continue;
    if (typeof record.exercise_id !== "string") continue;
    addRecord(record.member_id, record.exercise_id, {
      id: record.id,
      achievedAt: typeof record.achieved_at === "string" ? record.achieved_at : null,
      occurredAt: optionalTimestamp(record.created_at),
      weight: typeof record.weight === "number" ? record.weight : null,
      reps: typeof record.reps === "number" ? record.reps : null,
      time: typeof record.time_seconds === "number" ? record.time_seconds : null,
      distance: typeof record.distance === "number" ? record.distance : null,
      entryKind: "manual",
    });
  }

  const resetLineByMemberExercise = new Map<string, ExerciseResetLine>();
  for (const row of resetsResult.data ?? []) {
    const record = row as Record<string, unknown>;
    if (typeof record.member_id !== "string") continue;
    if (typeof record.exercise_id !== "string") continue;
    if (typeof record.reset_at !== "string") continue;
    resetLineByMemberExercise.set(
      `${record.member_id}:${record.exercise_id}`,
      {
        resetAt: record.reset_at,
        resetOccurredAt: optionalTimestamp(record.updated_at),
      },
    );
  }

  return {
    members,
    exercises,
    recordsByMemberExercise,
    resetLineByMemberExercise,
  };
}

/**
 * Gym-wide current PBs for the owner surface. Loads source rows under the
 * caller's JWT (RLS) and runs `derivePBs` per member × exercise.
 */
export async function deriveGymCurrentPBs(
  supabase: UserClient,
): Promise<OwnerCurrentPBSummary[]> {
  const sources = await fetchGymDerivationSources(supabase);
  const evaluatedAt = todayUtcDateString();
  const summaries: OwnerCurrentPBSummary[] = [];

  for (const member of sources.members) {
    for (const exercise of sources.exercises) {
      const key = `${member.id}:${exercise.id}`;
      const records = sources.recordsByMemberExercise.get(key) ?? [];
      const reset = sources.resetLineByMemberExercise.get(key);
      const { currentPB } = derivePBs({
        rule: exercise.pb_rule,
        records,
        staleness: member.staleness,
        resetAt: reset?.resetAt ?? null,
        resetOccurredAt: reset?.resetOccurredAt ?? null,
        evaluatedAt,
      });
      if (!currentPB) continue;

      const value = scalarValueForMeasurement(currentPB, exercise.measurement_type);
      if (!Number.isFinite(value)) continue;

      summaries.push({
        member_id: member.id,
        teamup_customer_id: member.teamup_customer_id,
        exercise_id: exercise.id,
        exercise_name: exercise.name,
        value,
        reps: currentPB.reps ?? null,
        achieved_at: currentPB.achievedAt ?? null,
      });
    }
  }

  return summaries;
}

export interface OwnerPbFrequencyHit {
  exercise_id: string;
  exercise_name: string;
  achieved_at: string;
  measurement_type: string;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
}

export interface OwnerPbFrequencyRow {
  member_id: string;
  teamup_customer_id: string | null;
  count: number;
  exercises: string[];
  hits: OwnerPbFrequencyHit[];
}

function achievedInWindow(
  achievedAt: string | null | undefined,
  from: string,
  to: string,
): boolean {
  if (achievedAt == null) return false;
  return achievedAt >= from && achievedAt <= to;
}

export interface GymPbFrequencySources {
  members: Array<{
    id: string;
    teamup_customer_id: string | null;
  }>;
  exercises: Array<{
    id: string;
    name: string;
    pb_rule: PBRule;
    measurement_type: string;
  }>;
  recordsByMemberExercise: ReadonlyMap<string, DerivationRecord[]>;
}

/**
 * Per-member historic PB counts in [from, to] (inclusive ISO dates).
 * Runs `badgeIds` on full dated history (running max needs pre-window
 * records), then keeps badges whose achievedAt falls in the window.
 * `hits` is that same filtered badge list — not a second PB definition.
 * Resets and staleness are not inputs; they do not affect badges.
 * Members with no in-window badges are omitted.
 */
export function gymPbFrequencyFromSources(
  sources: GymPbFrequencySources,
  from: string,
  to: string,
): OwnerPbFrequencyRow[] {
  const rows: OwnerPbFrequencyRow[] = [];

  for (const member of sources.members) {
    const exerciseNames: string[] = [];
    const hits: OwnerPbFrequencyHit[] = [];
    let count = 0;

    for (const exercise of sources.exercises) {
      const key = `${member.id}:${exercise.id}`;
      const records = sources.recordsByMemberExercise.get(key) ?? [];
      const badged = new Set(badgeIds({ rule: exercise.pb_rule, records }));
      const inWindow = records.filter(
        (record) =>
          badged.has(record.id) &&
          achievedInWindow(record.achievedAt, from, to),
      );
      if (inWindow.length === 0) continue;
      count += inWindow.length;
      exerciseNames.push(exercise.name);
      for (const record of inWindow) {
        if (record.achievedAt == null) continue;
        hits.push({
          exercise_id: exercise.id,
          exercise_name: exercise.name,
          achieved_at: record.achievedAt,
          measurement_type: exercise.measurement_type,
          weight: record.weight ?? null,
          reps: record.reps ?? null,
          time_seconds: record.time ?? null,
          distance: record.distance ?? null,
        });
      }
    }

    if (count === 0) continue;
    hits.sort((left, right) => {
      if (left.achieved_at !== right.achieved_at) {
        return left.achieved_at < right.achieved_at ? -1 : 1;
      }
      return left.exercise_name.localeCompare(right.exercise_name);
    });
    rows.push({
      member_id: member.id,
      teamup_customer_id: member.teamup_customer_id,
      count,
      exercises: exerciseNames,
      hits,
    });
  }

  rows.sort((left, right) => {
    if (right.count !== left.count) return right.count - left.count;
    return left.member_id.localeCompare(right.member_id);
  });
  return rows;
}

export async function deriveGymPbFrequency(
  supabase: UserClient,
  from: string,
  to: string,
): Promise<OwnerPbFrequencyRow[]> {
  const sources = await fetchGymDerivationSources(supabase);
  return gymPbFrequencyFromSources(sources, from, to);
}
