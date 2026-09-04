/**
 * Allowed JSON filters for owner raw-fact views → PostgREST query params.
 * Unknown keys and malformed values are rejected (400), not forwarded.
 * Omitting filters is gym-wide — same as unfiltered owner-current-pbs.
 * Gym scope still comes from the owner JWT on the view, not from these params.
 */

export const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9 '&+\-]{0,99}$/;
const CATEGORY_PATTERN = /^[A-Za-z][A-Za-z0-9_]{0,63}$/;

export type OwnerViewName =
  | "owner_session_activity"
  | "owner_set_detail"
  | "owner_exercise_catalogue";

export interface OwnerViewRoute {
  view: OwnerViewName;
  allow: ReadonlySet<string>;
}

export const VIEW_ROUTES: Record<string, OwnerViewRoute> = {
  "/api/owner/session-activity": {
    view: "owner_session_activity",
    allow: new Set(["member_id", "from", "to"]),
  },
  "/api/owner/set-detail": {
    view: "owner_set_detail",
    allow: new Set(["member_id", "exercise_id", "from", "to"]),
  },
  "/api/owner/exercise-catalogue": {
    view: "owner_exercise_catalogue",
    allow: new Set(["name", "category"]),
  },
};

export type ParsedViewQuery =
  | { ok: true; view: OwnerViewName; search: URLSearchParams }
  | { ok: false; error: string };

function asRecord(text: string): { ok: true; record: Record<string, unknown> } | { ok: false; error: string } {
  const trimmed = text.trim();
  if (trimmed.length === 0) return { ok: true, record: {} };
  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    return { ok: false, error: "Invalid JSON body" };
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { ok: false, error: "Request body must be a JSON object" };
  }
  return { ok: true, record: parsed as Record<string, unknown> };
}

function requireUuid(label: string, value: unknown): string | { error: string } {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    return { error: `${label} must be a UUID` };
  }
  return value.toLowerCase();
}

function requireDate(label: string, value: unknown): string | { error: string } {
  if (typeof value !== "string" || !DATE_PATTERN.test(value)) {
    return { error: `${label} must be YYYY-MM-DD` };
  }
  return value;
}

export function parseOwnerViewQuery(route: OwnerViewRoute, bodyText: string): ParsedViewQuery {
  const parsed = asRecord(bodyText);
  if (!parsed.ok) return parsed;

  for (const key of Object.keys(parsed.record)) {
    if (!route.allow.has(key)) {
      return { ok: false, error: `Unknown filter '${key}'` };
    }
  }

  const search = new URLSearchParams();
  const record = parsed.record;

  if (route.allow.has("member_id") && record.member_id !== undefined) {
    const memberId = requireUuid("member_id", record.member_id);
    if (typeof memberId !== "string") return { ok: false, error: memberId.error };
    search.set("member_id", `eq.${memberId}`);
  }

  if (route.allow.has("exercise_id") && record.exercise_id !== undefined) {
    const exerciseId = requireUuid("exercise_id", record.exercise_id);
    if (typeof exerciseId !== "string") return { ok: false, error: exerciseId.error };
    search.set("exercise_id", `eq.${exerciseId}`);
  }

  let from: string | undefined;
  let to: string | undefined;
  if (route.allow.has("from") && record.from !== undefined) {
    const date = requireDate("from", record.from);
    if (typeof date !== "string") return { ok: false, error: date.error };
    from = date;
  }
  if (route.allow.has("to") && record.to !== undefined) {
    const date = requireDate("to", record.to);
    if (typeof date !== "string") return { ok: false, error: date.error };
    to = date;
  }
  if (from && to && from > to) {
    return { ok: false, error: "from must be on or before to" };
  }
  if (from) search.append("session_date", `gte.${from}`);
  if (to) search.append("session_date", `lte.${to}`);

  if (route.allow.has("name") && record.name !== undefined) {
    if (typeof record.name !== "string" || !NAME_PATTERN.test(record.name.trim())) {
      return { ok: false, error: "name must be a short alphanumeric label" };
    }
    search.set("name", `ilike.*${record.name.trim()}*`);
  }

  if (route.allow.has("category") && record.category !== undefined) {
    if (typeof record.category !== "string" || !CATEGORY_PATTERN.test(record.category)) {
      return { ok: false, error: "category must be an identifier" };
    }
    search.set("category", `eq.${record.category}`);
  }

  return { ok: true, view: route.view, search };
}
