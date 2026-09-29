/**
 * Europe/London wall-clock helpers for the log-reminder job.
 * Keep in sync with src/client/web/owner-api/src/london-schedule.ts
 * (Worker cron gate vs Edge Function job).
 *
 * Weekdays (Mon–Fri): 09:00 / 14:00 / 21:00 London → morning / lunch / evening.
 * Saturday: 10:00 London → morning. Sunday: 11:00 London → morning.
 */

/** UTC wakes covering weekday + weekend London slots under GMT and BST. */
export const LOG_REMINDER_CRON = "0 8,9,10,11,13,14,20,21 * * *";

export type ReminderSlot = "morning" | "lunch" | "evening";

/** JS weekday: 0 = Sunday … 6 = Saturday, in Europe/London. */
export function londonWeekday(epochMs: number): number {
  const formatted = new Intl.DateTimeFormat("en-US", {
    timeZone: "Europe/London",
    weekday: "short",
  }).format(new Date(epochMs));
  const map: Record<string, number> = {
    Sun: 0,
    Mon: 1,
    Tue: 2,
    Wed: 3,
    Thu: 4,
    Fri: 5,
    Sat: 6,
  };
  const day = map[formatted];
  if (day === undefined) {
    throw new Error(`Unexpected London weekday: ${formatted}`);
  }
  return day;
}

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

export function reminderSlotAt(epochMs: number): ReminderSlot | null {
  const hour = londonHour(epochMs);
  const weekday = londonWeekday(epochMs);
  if (weekday === 6) return hour === 10 ? "morning" : null;
  if (weekday === 0) return hour === 11 ? "morning" : null;
  if (hour === 9) return "morning";
  if (hour === 14) return "lunch";
  if (hour === 21) return "evening";
  return null;
}

export function shouldRunLogReminder(epochMs: number): boolean {
  return reminderSlotAt(epochMs) != null;
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
