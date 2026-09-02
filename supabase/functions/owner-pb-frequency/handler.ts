/**
 * Owner PB Frequency — per-member historic PB counts in a date window.
 *
 * Access is owner_surface_grants (same gate as owner-current-pbs). Counts
 * come from badgeIds on full history, then filtered by achievedAt in
 * [from, to]. Does not reimplement freshness / tie-break / running max.
 */

import {
  createEdgeRequestHandler,
  createUserClient,
  DATE_PATTERN,
  jsonResponse,
  todayUtcDateString,
} from "../_shared/member-edge.ts";
import {
  deriveGymPbFrequency,
  fetchOwnerSurfaceGrant,
} from "../_shared/edge-pb-reads.ts";

type PeriodShorthand = "this_week" | "this_month";

export interface FrequencyWindow {
  from: string;
  to: string;
}

function utcDate(iso: string): Date {
  const [year, month, day] = iso.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day));
}

function toIsoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function startOfIsoWeek(today: string): string {
  const date = utcDate(today);
  const weekday = date.getUTCDay();
  const offset = weekday === 0 ? 6 : weekday - 1;
  date.setUTCDate(date.getUTCDate() - offset);
  return toIsoDate(date);
}

function endOfIsoWeek(today: string): string {
  const start = utcDate(startOfIsoWeek(today));
  start.setUTCDate(start.getUTCDate() + 6);
  return toIsoDate(start);
}

function startOfMonth(today: string): string {
  return `${today.slice(0, 7)}-01`;
}

function endOfMonth(today: string): string {
  const year = Number(today.slice(0, 4));
  const month = Number(today.slice(5, 7));
  return toIsoDate(new Date(Date.UTC(year, month, 0)));
}

function parsePeriodShorthand(value: unknown): PeriodShorthand | null {
  if (value === "this_week" || value === "this_month") return value;
  return null;
}

export function resolveFrequencyWindow(
  body: unknown,
  todayISO: string,
): { ok: true; window: FrequencyWindow } | { ok: false; error: string } {
  if (typeof body !== "object" || body === null) {
    return {
      ok: false,
      error: "Invalid request body. Provide period or from and to dates.",
    };
  }

  const record = body as Record<string, unknown>;
  const shorthand = parsePeriodShorthand(record.period);
  const fromRaw = record.from;
  const toRaw = record.to;
  const hasExplicit =
    typeof fromRaw === "string" || typeof toRaw === "string";

  if (shorthand && hasExplicit) {
    return {
      ok: false,
      error: "Provide either period or from/to, not both.",
    };
  }

  if (shorthand === "this_week") {
    return {
      ok: true,
      window: { from: startOfIsoWeek(todayISO), to: endOfIsoWeek(todayISO) },
    };
  }
  if (shorthand === "this_month") {
    return {
      ok: true,
      window: { from: startOfMonth(todayISO), to: endOfMonth(todayISO) },
    };
  }

  if (typeof fromRaw !== "string" || typeof toRaw !== "string") {
    return {
      ok: false,
      error:
        "Invalid request body. Expected period (this_week | this_month) or from and to as YYYY-MM-DD.",
    };
  }
  if (!DATE_PATTERN.test(fromRaw) || !DATE_PATTERN.test(toRaw)) {
    return {
      ok: false,
      error: "from and to must be YYYY-MM-DD dates.",
    };
  }
  if (fromRaw > toRaw) {
    return { ok: false, error: "from must be on or before to." };
  }

  return { ok: true, window: { from: fromRaw, to: toRaw } };
}

export const handleOwnerPbFrequencyRequest = createEdgeRequestHandler(
  async (req, _claims, authHeader) => {
    const supabase = createUserClient(authHeader);
    const grantGymId = await fetchOwnerSurfaceGrant(supabase);
    if (grantGymId == null) {
      return jsonResponse({ error: "Forbidden" }, 403);
    }

    let body: unknown = {};
    const contentType = req.headers.get("content-type") ?? "";
    if (contentType.includes("application/json")) {
      try {
        body = await req.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON body" }, 400);
      }
    }

    const resolved = resolveFrequencyWindow(body, todayUtcDateString());
    if (!resolved.ok) {
      return jsonResponse({ error: resolved.error }, 400);
    }

    const members = await deriveGymPbFrequency(
      supabase,
      resolved.window.from,
      resolved.window.to,
    );
    return jsonResponse(
      {
        period: resolved.window,
        members,
      },
      200,
    );
  },
);
