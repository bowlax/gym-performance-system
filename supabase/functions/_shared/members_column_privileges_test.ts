/**
 * authenticated may update member settings only. Identity columns stay
 * broker-owned (service role).
 */
import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";

const migrationsDir = new URL("../../migrations/", import.meta.url);

const MEMBER_SETTINGS_COLUMNS = [
  "staleness_enabled",
  "staleness_periods",
  "staleness_unit",
  "log_reminder_email_opted_out_at",
  "updated_at",
  "synced_at",
  "source_device_id",
];

const IDENTITY_COLUMNS = [
  "auth_user_id",
  "teamup_customer_id",
  "teamup_email",
  "teamup_roster_id",
  "gym_id",
  "display_name",
];

function grantedUpdateColumns(sql: string): string[] | null {
  const match = sql.match(
    /grant update\s*\(([^)]+)\)\s*on table public\.members to authenticated/i,
  );
  if (!match?.[1]) return null;
  return match[1]
    .split(",")
    .map((column) => column.trim())
    .filter((column) => column.length > 0);
}

Deno.test("authenticated update on members is limited to settings columns", async () => {
  const entries: string[] = [];
  for await (const entry of Deno.readDir(migrationsDir)) {
    if (entry.isFile && entry.name.endsWith(".sql")) entries.push(entry.name);
  }
  entries.sort();

  let revoked = false;
  let columns: string[] | null = null;
  for (const name of entries) {
    const sql = await Deno.readTextFile(new URL(name, migrationsDir));
    if (/revoke update on table public\.members from authenticated/i.test(sql)) {
      revoked = true;
      columns = null;
    }
    const granted = grantedUpdateColumns(sql);
    if (granted) columns = granted;
    if (
      revoked &&
      /grant update on\s+(table\s+)?public\.members to authenticated/i.test(sql)
    ) {
      throw new Error(
        `${name} restores table-level UPDATE on members for authenticated`,
      );
    }
  }

  assertEquals(revoked, true);
  assertEquals(columns, MEMBER_SETTINGS_COLUMNS);
  for (const column of IDENTITY_COLUMNS) {
    assertEquals(columns?.includes(column) ?? false, false);
  }
  assertStringIncludes(
    (columns ?? []).join(","),
    "log_reminder_email_opted_out_at",
  );
});
