/**
 * Who appears on the kiosk name picker.
 *
 * A resolved name is the email-based roster match (teamup_email captured and
 * teamup_roster_id written by that lookup), plus a display_name that is not
 * the unresolved sentinel. No Deno or Supabase imports — the member web
 * server uses the same predicate.
 */

export const UNRESOLVED_DISPLAY_NAME = "Member";

export interface KioskNameRow {
  display_name: string | null;
  teamup_email: string | null;
  teamup_roster_id: string | null;
  deleted_at?: string | null;
}

export function hasResolvedKioskName(member: KioskNameRow): boolean {
  if (member.deleted_at) return false;
  const name = member.display_name?.trim() ?? "";
  if (name.length === 0 || name === UNRESOLVED_DISPLAY_NAME) return false;
  const email = member.teamup_email?.trim() ?? "";
  if (email.length === 0) return false;
  const rosterId = member.teamup_roster_id?.trim() ?? "";
  return rosterId.length > 0;
}

export interface KioskMemberOption {
  member_id: string;
  display_name: string;
}

export function kioskMemberOptions(
  rows: Array<KioskNameRow & { id?: string; member_id?: string }>,
): KioskMemberOption[] {
  const options: KioskMemberOption[] = [];
  for (const row of rows) {
    const memberId = row.member_id ?? row.id ?? "";
    if (!memberId || !hasResolvedKioskName(row)) continue;
    options.push({
      member_id: memberId,
      display_name: row.display_name!.trim(),
    });
  }
  options.sort((left, right) => left.display_name.localeCompare(right.display_name));
  return options;
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function isUuid(value: string): boolean {
  return UUID_PATTERN.test(value);
}

function optionalNumber(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return null;
}

function optionalString(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "string") return value;
  return null;
}

export interface KioskSetInput {
  id: string;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
}

export interface KioskExerciseInput {
  exerciseId: string;
  exerciseEntryId: string;
  sets: KioskSetInput[];
}

export interface KioskPendingPayload {
  sessionId: string;
  exercises: KioskExerciseInput[];
}

export interface KioskSubmitRequest {
  memberId: string;
  session: {
    date: string;
    notes: string | null;
    calories_burned: number | null;
  };
  payload: KioskPendingPayload;
}

type ParseResult =
  | { ok: true; request: KioskSubmitRequest }
  | { ok: false; error: string };

function newId(): string {
  return crypto.randomUUID();
}

function parseSet(raw: unknown): KioskSetInput | { error: string } {
  if (typeof raw !== "object" || raw === null) {
    return { error: "Each exercise must include exactly one set." };
  }
  const record = raw as Record<string, unknown>;
  if (record.id != null && (typeof record.id !== "string" || !isUuid(record.id))) {
    return { error: "Invalid set id." };
  }
  return {
    id: typeof record.id === "string" ? record.id : newId(),
    weight: optionalNumber(record.weight),
    reps: optionalNumber(record.reps),
    time_seconds: optionalNumber(record.time_seconds),
    distance: optionalNumber(record.distance),
  };
}

export function parseKioskSubmitBody(body: unknown): ParseResult {
  if (typeof body !== "object" || body === null) {
    return { ok: false, error: "Invalid request body." };
  }
  const record = body as Record<string, unknown>;
  if (typeof record.memberId !== "string" || !isUuid(record.memberId)) {
    return { ok: false, error: "Invalid memberId." };
  }
  if (typeof record.session !== "object" || record.session === null) {
    return { ok: false, error: "Invalid request body. Provide session and exercises." };
  }
  const session = record.session as Record<string, unknown>;
  if (typeof session.date !== "string" || !DATE_PATTERN.test(session.date)) {
    return { ok: false, error: "Invalid request body. Provide session.date as YYYY-MM-DD." };
  }
  if (!Array.isArray(record.exercises) || record.exercises.length === 0) {
    return { ok: false, error: "At least one exercise is required." };
  }
  if (record.exercises.length > 50) {
    return { ok: false, error: "A session may include at most 50 exercises." };
  }

  const sessionId = typeof session.id === "string" && isUuid(session.id)
    ? session.id
    : newId();
  const exercises: KioskExerciseInput[] = [];
  const ids = new Set<string>([sessionId]);

  for (const item of record.exercises) {
    if (typeof item !== "object" || item === null) {
      return {
        ok: false,
        error: "Each exercise needs exerciseId and exactly one set.",
      };
    }
    const exercise = item as Record<string, unknown>;
    if (typeof exercise.exerciseId !== "string" || !isUuid(exercise.exerciseId)) {
      return { ok: false, error: "Invalid exerciseId." };
    }
    if (
      exercise.exerciseEntryId != null &&
      (typeof exercise.exerciseEntryId !== "string" || !isUuid(exercise.exerciseEntryId))
    ) {
      return { ok: false, error: "Invalid exerciseEntryId." };
    }
    if (!Array.isArray(exercise.sets) || exercise.sets.length !== 1) {
      return { ok: false, error: "Each exercise must include exactly one set." };
    }
    const parsedSet = parseSet(exercise.sets[0]);
    if ("error" in parsedSet) {
      return { ok: false, error: parsedSet.error };
    }
    const entryId = typeof exercise.exerciseEntryId === "string"
      ? exercise.exerciseEntryId
      : newId();
    if (ids.has(exercise.exerciseId) || ids.has(entryId) || ids.has(parsedSet.id)) {
      return { ok: false, error: "Duplicate ids in session payload." };
    }
    ids.add(exercise.exerciseId);
    ids.add(entryId);
    ids.add(parsedSet.id);
    exercises.push({
      exerciseId: exercise.exerciseId,
      exerciseEntryId: entryId,
      sets: [parsedSet],
    });
  }

  return {
    ok: true,
    request: {
      memberId: record.memberId,
      session: {
        date: session.date,
        notes: optionalString(session.notes),
        calories_burned: optionalNumber(session.calories_burned),
      },
      payload: { sessionId, exercises },
    },
  };
}

export async function hashKioskToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function newKioskToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

export interface KioskEmailExercise {
  name: string;
  weight: number | null;
  reps: number | null;
  time_seconds: number | null;
  distance: number | null;
}

export interface KioskEmailCopy {
  subject: string;
  text: string;
  html: string;
}

function formatSetLine(exercise: KioskEmailExercise): string {
  const parts: string[] = [];
  if (exercise.weight != null) parts.push(`${exercise.weight} kg`);
  if (exercise.reps != null) parts.push(`${exercise.reps} reps`);
  if (exercise.time_seconds != null) parts.push(`${exercise.time_seconds}s`);
  if (exercise.distance != null) parts.push(`${exercise.distance} m`);
  const detail = parts.length > 0 ? parts.join(", ") : "logged";
  return `${exercise.name}: ${detail}`;
}

export function buildKioskConfirmEmail(args: {
  displayName: string;
  sessionDate: string;
  exercises: KioskEmailExercise[];
  confirmUrl: string;
}): KioskEmailCopy {
  const lines = args.exercises.map(formatSetLine);
  const subject = "Confirm your Wolf session";
  const text = [
    `Hi ${args.displayName},`,
    "",
    `A session on ${args.sessionDate} was entered at the gym kiosk:`,
    ...lines.map((line) => `- ${line}`),
    "",
    "It is not on your board until you confirm it.",
    args.confirmUrl,
    "",
    "After that, change it in the app if you need to.",
  ].join("\n");

  const items = lines
    .map((line) => `<li style="margin:0 0 6px;">${escapeHtml(line)}</li>`)
    .join("");
  const html =
    `<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#111;line-height:1.5;">` +
    `<p>Hi ${escapeHtml(args.displayName)},</p>` +
    `<p>A session on ${escapeHtml(args.sessionDate)} was entered at the gym kiosk:</p>` +
    `<ul style="padding-left:18px;">${items}</ul>` +
    `<p>It is not on your board until you confirm it.</p>` +
    `<p><a href="${escapeHtml(args.confirmUrl)}" style="color:#1A5BA6;">Confirm this session</a></p>` +
    `<p>After that, change it in the app if you need to.</p>` +
    `</div>`;

  return { subject, text, html };
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
