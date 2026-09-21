/**
 * Europe/London wall-clock helpers for the log-reminder cron gate.
 * Cron itself is UTC-only; this converts the trigger instant.
 */

export const NAME_SYNC_CRON = "0 5 * * *";
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
