import { describe, expect, test } from "bun:test";
import { memberStalenessPatchFields } from "./member-settings";

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
