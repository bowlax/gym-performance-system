/**
 * Europe/London wall-clock helpers for the log-reminder job.
 * Keep in sync with src/client/web/owner-api/src/london-schedule.ts
 * (Worker cron gate vs Edge Function job).
 */

export const LOG_REMINDER_CRON = "0 8,9,13,14,20,21 * * *";

export type ReminderSlot = "morning" | "lunch" | "evening";

export function londonHour(epochMs: number): number {
  const formatted = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/London",
    hour: "numeric",
    hourCycle: "h23",
  }).format(new Date(epochMs));
  return Number(formatted);
}

export function londonCalendarDate(epochMs: number): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/London",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(epochMs));
}

export function reminderSlotFromLondonHour(
  hour: number,
): ReminderSlot | null {
  if (hour === 9) return "morning";
  if (hour === 14) return "lunch";
  if (hour === 21) return "evening";
  return null;
}

export function shouldRunLogReminder(epochMs: number): boolean {
  return reminderSlotFromLondonHour(londonHour(epochMs)) != null;
}

export function formatLondonClock(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/London",
    hour: "numeric",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(date);
}
