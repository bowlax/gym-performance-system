import type { ReminderSlot } from "./log-reminder-schedule.ts";
import { formatLondonClock } from "./log-reminder-schedule.ts";

export const REMINDER_FROM = "Wolf Reminders <reminders@lbconsulting.tech>";
export const WOLF_LOGO_URL =
  "https://bowlax.github.io/gym-performance-system/landing/app-icon.png";

export interface ReminderClass {
  name: string | null;
  startsAt: string;
}

export interface ReminderCopy {
  subject: string;
  intro: string;
  classPhrase: string;
  greeting: string;
  text: string;
  html: string;
}

const SLOT_COPY: Record<ReminderSlot, { subject: string; intro: string }> = {
  morning: {
    subject: "Log your Wolf morning session",
    intro: "You were booked in this morning",
  },
  lunch: {
    subject: "Log your Wolf lunch session",
    intro: "You were booked in at lunch",
  },
  evening: {
    subject: "Log your Wolf evening session",
    intro: "You were booked in this evening",
  },
};

export function formatClassPhrase(classes: ReminderClass[]): string {
  const timed = classes
    .map((row) => ({
      name: row.name?.trim() || null,
      clock: formatLondonClock(row.startsAt),
    }))
    .filter((row) => row.clock.length > 0);
  if (timed.length === 0) return "";
  if (timed.length === 1) {
    const only = timed[0]!;
    return only.name ? `${only.name} at ${only.clock}` : only.clock;
  }
  return timed.map((row) => row.clock).join(" and ");
}

export function greetingForName(memberName: string | null): string {
  const trimmed = memberName?.trim() ?? "";
  if (!trimmed || trimmed.toLowerCase() === "member") return "Hi,";
  const first = trimmed.split(/\s+/)[0]!;
  return `Hi ${first},`;
}

export function buildReminderCopy(
  slot: ReminderSlot,
  classes: ReminderClass[],
  logUrl: string,
  unsubscribeUrl: string,
  memberName: string | null,
): ReminderCopy {
  const { subject, intro } = SLOT_COPY[slot];
  const classPhrase = formatClassPhrase(classes);
  const bookedLine = classPhrase ? `${intro} (${classPhrase}).` : `${intro}.`;
  const greeting = greetingForName(memberName);
  const body =
    `${greeting}\n\n` +
    `${bookedLine} There's no session in GymPerformance yet.\n\n` +
    `Log it while the numbers are still in your head.\n${logUrl}\n\n` +
    `— Wolf\n\nStop these emails: ${unsubscribeUrl}`;
  const html = buildHtmlEmail({
    greeting,
    bookedLine,
    logUrl,
    unsubscribeUrl,
  });
  return { subject, intro, classPhrase, greeting, text: body, html };
}

function buildHtmlEmail(args: {
  greeting: string;
  bookedLine: string;
  logUrl: string;
  unsubscribeUrl: string;
}): string {
  const greeting = escapeHtml(args.greeting);
  const booked = escapeHtml(args.bookedLine);
  const logUrl = escapeHtml(args.logUrl);
  const unsub = escapeHtml(args.unsubscribeUrl);
  const logo = escapeHtml(WOLF_LOGO_URL);
  return (
    `<!DOCTYPE html><html lang="en"><body style="margin:0;padding:0;background:#f4f4f4;">` +
    `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f4f4;">` +
    `<tr><td align="center" style="padding:24px 12px;">` +
    `<table role="presentation" width="560" cellspacing="0" cellpadding="0" style="max-width:560px;width:100%;background:#ffffff;border-radius:12px;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#222222;">` +
    `<tr><td align="center" style="background:#000000;padding:20px;">` +
    `<img src="${logo}" alt="Wolf" width="72" height="72" style="display:block;border:0;width:72px;height:72px;">` +
    `</td></tr>` +
    `<tr><td style="padding:28px 32px 8px;font-size:16px;line-height:1.5;">` +
    `<p style="margin:0 0 16px;">${greeting}</p>` +
    `<p style="margin:0 0 16px;">${booked} There's no session in GymPerformance yet.</p>` +
    `<p style="margin:0 0 24px;">Log it while the numbers are still in your head.</p>` +
    `<table role="presentation" cellspacing="0" cellpadding="0"><tr>` +
    `<td align="center" bgcolor="#1A5BA6" style="border-radius:8px;">` +
    `<a href="${logUrl}" style="display:inline-block;padding:12px 24px;font-size:16px;font-weight:600;color:#ffffff;text-decoration:none;">Log session</a>` +
    `</td></tr></table>` +
    `</td></tr>` +
    `<tr><td style="padding:28px 32px;font-size:13px;line-height:1.5;color:#666666;">` +
    `<p style="margin:0 0 8px;">— Wolf</p>` +
    `<p style="margin:0;"><a href="${unsub}" style="color:#1A5BA6;">Stop these emails</a></p>` +
    `</td></tr>` +
    `</table></td></tr></table></body></html>`
  );
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
