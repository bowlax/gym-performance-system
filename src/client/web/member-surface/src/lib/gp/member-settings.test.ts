import { describe, expect, test } from "bun:test";
import {
  logReminderEmailsEnabledFromRow,
  memberLogReminderEmailsPatchFields,
  memberStalenessPatchFields,
} from "./member-settings";

describe("memberStalenessPatchFields", () => {
  test("sets synced_at alongside updated_at so iOS pull can see the write", () => {
    const now = new Date("2026-08-04T20:00:00.000Z");
    const fields = memberStalenessPatchFields(
      { enabled: true, periods: 3, unit: "months" },
      now,
    );

    expect(fields.staleness_enabled).toBe(true);
    expect(fields.staleness_periods).toBe(3);
    expect(fields.staleness_unit).toBe("month");
    expect(fields.updated_at).toBe("2026-08-04T20:00:00.000Z");
    expect(fields.synced_at).toBe("2026-08-04T20:00:00.000Z");
  });

  test("clamps periods to at least 1 and maps quarters unit", () => {
    const fields = memberStalenessPatchFields({
      enabled: false,
      periods: 0,
      unit: "quarters",
    });
    expect(fields.staleness_periods).toBe(1);
    expect(fields.staleness_unit).toBe("quarter");
    expect(typeof fields.synced_at).toBe("string");
    expect(fields.synced_at).toBe(fields.updated_at);
  });
});

describe("log reminder email settings", () => {
  test("null opted-out timestamp means subscribed", () => {
    expect(logReminderEmailsEnabledFromRow(null)).toBe(true);
    expect(
      logReminderEmailsEnabledFromRow({ log_reminder_email_opted_out_at: null }),
    ).toBe(true);
    expect(
      logReminderEmailsEnabledFromRow({ log_reminder_email_opted_out_at: "" }),
    ).toBe(true);
  });

  test("a timestamp means opted out", () => {
    expect(
      logReminderEmailsEnabledFromRow({
        log_reminder_email_opted_out_at: "2026-09-21T15:00:00.000Z",
      }),
    ).toBe(false);
  });

  test("resubscribe PATCH clears opted_out_at and stamps synced_at", () => {
    const now = new Date("2026-09-21T16:00:00.000Z");
    const fields = memberLogReminderEmailsPatchFields(true, now);
    expect(fields.log_reminder_email_opted_out_at).toBeNull();
    expect(fields.updated_at).toBe("2026-09-21T16:00:00.000Z");
    expect(fields.synced_at).toBe("2026-09-21T16:00:00.000Z");
    expect(fields.staleness_enabled).toBeUndefined();
  });

  test("opt-out PATCH writes the timestamp", () => {
    const now = new Date("2026-09-21T16:00:00.000Z");
    const fields = memberLogReminderEmailsPatchFields(false, now);
    expect(fields.log_reminder_email_opted_out_at).toBe(
      "2026-09-21T16:00:00.000Z",
    );
  });
});
