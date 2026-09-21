/**
 * Log-reminder job: TeamUp attendances → roster-id join → Resend.
 *
 * One email per member per London date. Three UTC wakes; the Worker
 * only invokes this when Europe/London hour is 9, 14, or 21.
 */

import { createServiceRoleClient } from "./member-edge.ts";
import {
  customerEmail,
  customerRosterId,
  detectTeamUpAuthPrefix,
} from "./teamup-customers.ts";
import {
  buildReminderCopy,
  REMINDER_FROM,
  type ReminderClass,
} from "./log-reminder-copy.ts";
import {
  londonCalendarDate,
  reminderSlotFromLondonHour,
  londonHour,
  type ReminderSlot,
} from "./log-reminder-schedule.ts";
import { signLogReminderOptOutToken } from "./log-reminder-token.ts";

/**
 * Statuses that count as "probably trained" for the log reminder.
 *
 * Today: registered + attended. Wolf rarely marks no-show (~0.5%),
 * and coaches often leave a real session as `registered` instead of
 * checking off `attended`. So `registered` is the working signal;
 * `attended` is a strict subset when they do confirm.
 *
 * When Steve's coaches confirm attendance consistently, tighten this
 * to `["attended"]` only. Do not scatter status checks elsewhere.
 */
export const PROBABLY_TRAINED_STATUSES = ["registered", "attended"] as const;

export const BACKOFF_SEND_DAYS = 3;
export const LOG_REMINDER_KIND = "booked_unlogged";

const TEAMUP_BASE = "https://goteamup.com/api/v2/";

export interface TeamUpAttendanceRow {
  customer: unknown;
  event: unknown;
  status?: unknown;
}

export interface ExpandedEvent {
  id?: unknown;
  name?: unknown;
  starts_at?: unknown;
  ends_at?: unknown;
}

export interface EndedClass {
  rosterId: string;
  name: string | null;
  startsAt: string;
  endsAt: string;
  email: string | null;
}

export function eventHasEnded(endsAt: string, nowMs: number): boolean {
  const end = Date.parse(endsAt);
  return Number.isFinite(end) && end <= nowMs;
}

export function attendanceRosterId(row: TeamUpAttendanceRow): string | null {
  const customer = row.customer;
  if (typeof customer === "number" && Number.isFinite(customer)) {
    return String(customer);
  }
  if (typeof customer === "string" && customer.trim()) return customer.trim();
  if (typeof customer === "object" && customer !== null) {
    return customerRosterId(customer as Record<string, unknown>);
  }
  return null;
}

export function expandedEvent(value: unknown): ExpandedEvent | null {
  if (typeof value !== "object" || value === null) return null;
  return value as ExpandedEvent;
}

export function collectEndedClasses(
  rows: TeamUpAttendanceRow[],
  nowMs: number,
): EndedClass[] {
  const allowed = new Set<string>(PROBABLY_TRAINED_STATUSES);
  const out: EndedClass[] = [];
  for (const row of rows) {
    if (typeof row.status !== "string" || !allowed.has(row.status)) continue;
    const rosterId = attendanceRosterId(row);
    const event = expandedEvent(row.event);
    const endsAt = typeof event?.ends_at === "string" ? event.ends_at : null;
    const startsAt = typeof event?.starts_at === "string" ? event.starts_at : null;
    if (!event || !rosterId || !endsAt || !startsAt) continue;
    if (!eventHasEnded(endsAt, nowMs)) continue;
    const email = typeof row.customer === "object" && row.customer !== null
      ? customerEmail(row.customer as Record<string, unknown>)
      : null;
    out.push({
      rosterId,
      name: typeof event.name === "string" ? event.name : null,
      startsAt,
      endsAt,
      email,
    });
  }
  out.sort((left, right) => left.startsAt.localeCompare(right.startsAt));
  return out;
}

export function groupClassesByRoster(
  classes: EndedClass[],
): Map<string, EndedClass[]> {
  const grouped = new Map<string, EndedClass[]>();
  for (const row of classes) {
    const list = grouped.get(row.rosterId) ?? [];
    list.push(row);
    grouped.set(row.rosterId, list);
  }
  return grouped;
}

export function sendDatesSinceLastLog(
  sends: Array<{ for_date: string; sent_at: string }>,
  lastLogCreatedAt: string | null,
): string[] {
  const cutoff = lastLogCreatedAt ? Date.parse(lastLogCreatedAt) : 0;
  const dates = new Set<string>();
  for (const send of sends) {
    const sent = Date.parse(send.sent_at);
    if (!Number.isFinite(sent) || sent <= cutoff) continue;
    dates.add(send.for_date);
  }
  return [...dates].sort();
}

export function isInSendDayBackoff(sendDatesSinceLog: string[]): boolean {
  return sendDatesSinceLog.length >= BACKOFF_SEND_DAYS;
}

export interface LogReminderRunResult {
  slot: ReminderSlot | null;
  forDate: string;
  considered: number;
  sent: number;
  skipped: Record<string, number>;
}

export interface LogReminderDeps {
  nowMs: number;
  fetchImpl: typeof fetch;
}

function skip(bucket: Record<string, number>, key: string): void {
  bucket[key] = (bucket[key] ?? 0) + 1;
}

async function teamUpGet(
  fetchImpl: typeof fetch,
  token: string,
  providerId: string,
  prefix: string,
  pathAndQuery: string,
): Promise<{ status: number; json: unknown }> {
  const res = await fetchImpl(new URL(pathAndQuery, TEAMUP_BASE), {
    headers: {
      Authorization: `${prefix} ${token}`,
      "TeamUp-Provider-ID": providerId,
      Accept: "application/json",
    },
  });
  return { status: res.status, json: await res.json() };
}

async function listDayAttendances(
  fetchImpl: typeof fetch,
  token: string,
  providerId: string,
  prefix: string,
  forDate: string,
): Promise<TeamUpAttendanceRow[]> {
  const status = PROBABLY_TRAINED_STATUSES.join(",");
  const rows: TeamUpAttendanceRow[] = [];
  for (let page = 1; page <= 20; page += 1) {
    const path =
      `attendances?page=${page}&page_size=100` +
      `&status=${status}` +
      `&expand=event,customer` +
      `&event_local_starts_at_gte=${forDate}T00:00:00` +
      `&event_local_starts_at_lte=${forDate}T23:59:59`;
    const attempt = await teamUpGet(fetchImpl, token, providerId, prefix, path);
    if (attempt.status < 200 || attempt.status >= 300) {
      throw new Error(`TeamUp attendances failed (${attempt.status})`);
    }
    const json = attempt.json as { results?: unknown[]; next?: unknown };
    const pageRows = Array.isArray(json.results) ? json.results : [];
    for (const row of pageRows) {
      if (typeof row === "object" && row !== null) {
        rows.push(row as TeamUpAttendanceRow);
      }
    }
    if (!json.next || pageRows.length === 0) break;
  }
  return rows;
}

export async function runLogReminderJob(
  deps: LogReminderDeps,
): Promise<LogReminderRunResult> {
  const slot = reminderSlotFromLondonHour(londonHour(deps.nowMs));
  if (!slot) {
    return {
      slot: null,
      forDate: londonCalendarDate(deps.nowMs),
      considered: 0,
      sent: 0,
      skipped: { not_slot_hour: 1 },
    };
  }

  const forDate = londonCalendarDate(deps.nowMs);
  const skipped: Record<string, number> = {};
  const token = Deno.env.get("TEAMUP_M2M_TOKEN")?.trim();
  const providerId = Deno.env.get("TEAMUP_OAUTH_PROVIDER_ID")?.trim();
  const resendKey = Deno.env.get("RESEND_API_KEY")?.trim();
  const memberWeb = Deno.env.get("MEMBER_WEB_ORIGIN")?.trim()?.replace(/\/$/, "");
  const unsubSecret = Deno.env.get("LOG_REMINDER_UNSUBSCRIBE_SECRET")?.trim();
  if (!token || !providerId) throw new Error("TeamUp M2M is not configured");
  if (!resendKey) throw new Error("RESEND_API_KEY is not configured");
  if (!memberWeb) throw new Error("MEMBER_WEB_ORIGIN is not configured");
  if (!unsubSecret) {
    throw new Error("LOG_REMINDER_UNSUBSCRIBE_SECRET is not configured");
  }

  const prefix = await detectTeamUpAuthPrefix(token, providerId);
  const attendances = await listDayAttendances(
    deps.fetchImpl,
    token,
    providerId,
    prefix,
    forDate,
  );
  const ended = collectEndedClasses(attendances, deps.nowMs);
  const grouped = groupClassesByRoster(ended);
  const rosterIds = [...grouped.keys()];
  const service = createServiceRoleClient();

  const { data: gym, error: gymError } = await service
    .from("gyms")
    .select("id")
    .eq("teamup_provider_id", providerId)
    .is("deleted_at", null)
    .maybeSingle();
  if (gymError) throw gymError;
  const gymId = (gym as { id?: string } | null)?.id;
  if (!gymId) throw new Error("Gym not found for TeamUp provider");

  if (rosterIds.length === 0) {
    return { slot, forDate, considered: 0, sent: 0, skipped };
  }

  const { data: memberRows, error: memberError } = await service
    .from("members")
    .select(
      "id, gym_id, teamup_roster_id, teamup_email, display_name, log_reminder_email_opted_out_at",
    )
    .eq("gym_id", gymId)
    .is("deleted_at", null)
    .in("teamup_roster_id", rosterIds);
  if (memberError) throw memberError;

  const members = (memberRows ?? []) as Array<{
    id: string;
    gym_id: string;
    teamup_roster_id: string | null;
    teamup_email: string | null;
    display_name: string | null;
    log_reminder_email_opted_out_at: string | null;
  }>;
  const byRoster = new Map(members.map((row) => [row.teamup_roster_id, row]));

  let sent = 0;
  let considered = 0;
  for (const [rosterId, classes] of grouped) {
    considered += 1;
    const member = byRoster.get(rosterId);
    if (!member) {
      skip(skipped, "unmatched_roster");
      continue;
    }
    if (member.log_reminder_email_opted_out_at) {
      skip(skipped, "opted_out");
      continue;
    }

    const { data: existingSend, error: sendLookupError } = await service
      .from("log_reminder_sends")
      .select("id")
      .eq("member_id", member.id)
      .eq("for_date", forDate)
      .eq("kind", LOG_REMINDER_KIND)
      .maybeSingle();
    if (sendLookupError) throw sendLookupError;
    if (existingSend) {
      skip(skipped, "already_sent_today");
      continue;
    }

    const { data: todaySession, error: sessionError } = await service
      .from("sessions")
      .select("id")
      .eq("member_id", member.id)
      .eq("date", forDate)
      .is("deleted_at", null)
      .limit(1)
      .maybeSingle();
    if (sessionError) throw sessionError;
    if (todaySession) {
      skip(skipped, "already_logged");
      continue;
    }

    const { data: lastLog, error: lastLogError } = await service
      .from("sessions")
      .select("created_at")
      .eq("member_id", member.id)
      .is("deleted_at", null)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (lastLogError) throw lastLogError;
    const { data: priorSends, error: priorError } = await service
      .from("log_reminder_sends")
      .select("for_date, sent_at")
      .eq("member_id", member.id)
      .eq("kind", LOG_REMINDER_KIND);
    if (priorError) throw priorError;
    const sendDates = sendDatesSinceLastLog(
      (priorSends ?? []) as Array<{ for_date: string; sent_at: string }>,
      (lastLog as { created_at?: string } | null)?.created_at ?? null,
    );
    if (isInSendDayBackoff(sendDates)) {
      skip(skipped, "backoff");
      continue;
    }

    const toEmail = classes[0]?.email ?? member.teamup_email;
    if (!toEmail) {
      skip(skipped, "no_email");
      continue;
    }

    const optOutToken = await signLogReminderOptOutToken(
      member.id,
      unsubSecret,
    );
    const unsubscribeUrl =
      `${memberWeb}/reminders/unsubscribe?token=${encodeURIComponent(optOutToken)}`;
    const logUrl = `${memberWeb}/log`;
    const reminderClasses: ReminderClass[] = classes.map((row) => ({
      name: row.name,
      startsAt: row.startsAt,
    }));
    const copy = buildReminderCopy(
      slot,
      reminderClasses,
      logUrl,
      unsubscribeUrl,
      member.display_name,
    );

    const { error: insertError } = await service.from("log_reminder_sends").insert({
      gym_id: member.gym_id,
      member_id: member.id,
      for_date: forDate,
      kind: LOG_REMINDER_KIND,
      slot,
    });
    if (insertError) {
      if (insertError.code === "23505") {
        skip(skipped, "already_sent_today");
        continue;
      }
      throw insertError;
    }

    const resendRes = await deps.fetchImpl("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: REMINDER_FROM,
        to: [toEmail],
        subject: copy.subject,
        text: copy.text,
        html: copy.html,
        headers: {
          "List-Unsubscribe": `<${unsubscribeUrl}>`,
          "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
        },
      }),
    });
    if (!resendRes.ok) {
      skip(skipped, "resend_failed");
      continue;
    }
    sent += 1;
  }

  return { slot, forDate, considered, sent, skipped };
}
