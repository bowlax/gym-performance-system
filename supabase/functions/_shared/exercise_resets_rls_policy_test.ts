/**
 * Regression guard for #40: exercise_resets_read must gate staff on `app_role`,
 * not PostgREST `role` (always "authenticated" on Auth-session JWTs).
 *
 * Walks migrations in order and asserts the final policy definition matches the
 * sessions / personal_bests staff-read pattern.
 */
import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";

const migrationsDir = new URL("../../migrations/", import.meta.url);

function extractExerciseResetsReadPolicy(sql: string): string | null {
  const match = sql.match(
    /create policy exercise_resets_read on exercise_resets[\s\S]*?;/i,
  );
  return match?.[0] ?? null;
}

Deno.test("exercise_resets_read final policy uses app_role for coach/owner", async () => {
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
    const policy = extractExerciseResetsReadPolicy(sql);
    if (policy) {
      latestPolicy = policy;
    }
  }

  if (latestPolicy === null) {
    throw new Error("No create policy exercise_resets_read found in migrations");
  }

  assertStringIncludes(
    latestPolicy,
    "(auth.jwt() ->> 'app_role') in ('coach','owner')",
  );
  assertEquals(
    latestPolicy.includes("(auth.jwt() ->> 'role') in ('coach','owner')"),
    false,
    "staff branch must not use JWT claim role (PostgREST session role)",
  );
  assertStringIncludes(
    latestPolicy,
    "member_id = (auth.jwt() ->> 'member_id')::uuid",
  );
  assertStringIncludes(
    latestPolicy,
    "gym_id = (auth.jwt() ->> 'gym_id')::uuid",
  );
});
