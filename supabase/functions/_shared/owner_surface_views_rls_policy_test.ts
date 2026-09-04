/**
 * Regression guard: owner raw-fact views must be owner-only, gym-scoped,
 * security_invoker, SELECT-only, and must not embed names or TeamUp calls.
 */
import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";

const migrationsDir = new URL("../../migrations/", import.meta.url);

const VIEW_NAMES = [
  "owner_session_activity",
  "owner_set_detail",
  "owner_exercise_catalogue",
] as const;

async function latestMigrationSql(): Promise<string> {
  const entries: string[] = [];
  for await (const entry of Deno.readDir(migrationsDir)) {
    if (entry.isFile && entry.name.endsWith(".sql")) {
      entries.push(entry.name);
    }
  }
  entries.sort();

  const chunks: string[] = [];
  for (const name of entries) {
    chunks.push(await Deno.readTextFile(new URL(name, migrationsDir)));
  }
  return chunks.join("\n");
}

function extractCreateView(sql: string, viewName: string): string {
  const pattern = new RegExp(
    `create(?: or replace)? view public\\.${viewName}[\\s\\S]*?;`,
    "gi",
  );
  const matches = [...sql.matchAll(pattern)];
  if (matches.length === 0) {
    throw new Error(`No create view public.${viewName} found in migrations`);
  }
  return matches[matches.length - 1][0];
}

function grantsFor(sql: string, viewName: string): string[] {
  const grants: string[] = [];
  const pattern = new RegExp(
    `grant\\s+([^;]+)\\s+on table public\\.${viewName}\\s+to\\s+([^;]+);`,
    "gi",
  );
  for (const match of sql.matchAll(pattern)) {
    grants.push(`${match[1].trim().toLowerCase()} -> ${match[2].trim().toLowerCase()}`);
  }
  return grants;
}

Deno.test("owner raw-fact views are security_invoker and owner-gated via grants", async () => {
  const sql = await latestMigrationSql();

  for (const viewName of VIEW_NAMES) {
    const view = extractCreateView(sql, viewName);
    assertStringIncludes(view, "security_invoker = true");
    assertStringIncludes(view, "join public.owner_surface_grants");
    assertStringIncludes(view, "(auth.jwt() ->> 'app_role') = 'owner'");
    assertStringIncludes(
      view,
      "gym_id = (auth.jwt() ->> 'gym_id')::uuid",
    );
    assertEquals(
      view.includes("(auth.jwt() ->> 'role')"),
      false,
      `${viewName} must not use JWT claim role (PostgREST session role)`,
    );
    assertEquals(
      view.includes("'coach'"),
      false,
      `${viewName} must be owner-only, not coach+owner`,
    );
    assertEquals(
      /display_name/i.test(view),
      false,
      `${viewName} must not expose display_name`,
    );
    assertEquals(
      /goteamup|teamup_m2m|teamup-oauth/i.test(view),
      false,
      `${viewName} must not depend on TeamUp`,
    );

    const grants = grantsFor(sql, viewName);
    assertEquals(grants.length > 0, true, `${viewName} must grant SELECT`);
    for (const grant of grants) {
      assertEquals(
        grant.startsWith("select ->"),
        true,
        `${viewName} must GRANT SELECT only, got: ${grant}`,
      );
      assertEquals(
        /insert|update|delete|all/.test(grant),
        false,
        `${viewName} must not grant writes, got: ${grant}`,
      );
    }
  }

  assertEquals(/create function .*owner-member-exercise-history/i.test(sql), false);
  assertEquals(/goteamup\.com/i.test(sql), false);

  const sessionView = extractCreateView(sql, "owner_session_activity");
  assertStringIncludes(sessionView, "s.calories_burned");
});
