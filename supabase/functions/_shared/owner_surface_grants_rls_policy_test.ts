/**
 * Regression guard: owner_surface_grants_read must be owner-only, gym-scoped,
 * and must use app_role (not PostgREST `role`).
 */
import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";

const migrationsDir = new URL("../../migrations/", import.meta.url);

function extractOwnerSurfaceGrantsReadPolicy(sql: string): string | null {
  const match = sql.match(
    /create policy owner_surface_grants_read on owner_surface_grants[\s\S]*?;/i,
  );
  return match?.[0] ?? null;
}

Deno.test("owner_surface_grants_read is owner-only via app_role", async () => {
  const entries: string[] = [];
  for await (const entry of Deno.readDir(migrationsDir)) {
    if (entry.isFile && entry.name.endsWith(".sql")) {
      entries.push(entry.name);
    }
  }
  entries.sort();

  let latestPolicy: string | null = null;
  for (const name of entries) {
    const sql = await Deno.readTextFile(new URL(name, migrationsDir));
    const policy = extractOwnerSurfaceGrantsReadPolicy(sql);
    if (policy) {
      latestPolicy = policy;
    }
  }

  if (latestPolicy === null) {
    throw new Error("No create policy owner_surface_grants_read found in migrations");
  }

  assertStringIncludes(
    latestPolicy,
    "(auth.jwt() ->> 'app_role') = 'owner'",
  );
  assertEquals(
    latestPolicy.includes("(auth.jwt() ->> 'role')"),
    false,
    "must not use JWT claim role (PostgREST session role)",
  );
  assertEquals(
    latestPolicy.includes("'coach'"),
    false,
    "owner-surface grants are owner-only, not coach+owner",
  );
  assertStringIncludes(
    latestPolicy,
    "gym_id = (auth.jwt() ->> 'gym_id')::uuid",
  );
});
