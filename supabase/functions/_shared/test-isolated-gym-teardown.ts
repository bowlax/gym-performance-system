/**
 * Isolated gym teardown for HTTP tests.
 *
 * service_role has no GRANT DELETE (GDPR / privileged-path boundary).
 * supabase-js .delete() therefore 403s and does NOT throw unless .error is
 * checked — that is how leftover test gyms landed on live.
 *
 * These tests do not need rows hard-gone; they need them excluded from
 * owner/member reads. service_role CAN UPDATE, so teardown tombstones the
 * gym tree (deleted_at) and FAILS if any update errors or any targeted
 * gym/member/session is still live.
 *
 * Mutating tests must target loopback Supabase only. Hosted inserts cannot
 * be hard-deleted via PostgREST and must not run from Deno test env.
 */

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const TOMBSTONE_TABLES_BY_GYM_ID = [
  "sets",
  "exercise_entries",
  "personal_bests",
  "exercise_resets",
  "sessions",
  "exercises",
  "members",
] as const;

export function isLoopbackSupabaseUrl(url: string): boolean {
  try {
    const host = new URL(url).hostname;
    return host === "localhost" || host === "127.0.0.1" || host === "::1" ||
      host === "[::1]";
  } catch {
    return false;
  }
}

/** Mutating HTTP tests must not insert into hosted PostgREST. */
export function onlyIfLoopback<T extends { url: string }>(env: T): T | null {
  return isLoopbackSupabaseUrl(env.url) ? env : null;
}

export function throwIfPostgrestError(
  label: string,
  error: { message: string; code?: string } | null | undefined,
): void {
  if (!error) return;
  const code = error.code ? `[${error.code}] ` : "";
  throw new Error(
    `${label} failed: ${code}${error.message}. ` +
      "service_role has no DELETE grant (intentional GDPR boundary). " +
      "Do not ignore PostgREST errors. Wipe leftovers with: " +
      "npx supabase db query --linked (or --local).",
  );
}

export async function tombstoneIsolatedGymTree(
  admin: SupabaseClient,
  gymIds: string[],
): Promise<void> {
  const ids = gymIds.filter((id) => id.length > 0);
  if (ids.length === 0) return;

  const now = new Date().toISOString();

  for (const table of TOMBSTONE_TABLES_BY_GYM_ID) {
    const { error } = await admin.from(table).update({ deleted_at: now }).in(
      "gym_id",
      ids,
    );
    throwIfPostgrestError(`tombstone ${table}`, error);
  }

  const gymUpdate = await admin.from("gyms").update({ deleted_at: now }).in(
    "id",
    ids,
  );
  throwIfPostgrestError("tombstone gyms", gymUpdate.error);

  await assertNoLiveRows(admin, "gyms", "id", ids);
  await assertNoLiveRows(admin, "members", "gym_id", ids);
  await assertNoLiveRows(admin, "sessions", "gym_id", ids);
}

async function assertNoLiveRows(
  admin: SupabaseClient,
  table: string,
  column: string,
  ids: string[],
): Promise<void> {
  const { data, error } = await admin
    .from(table)
    .select("id, deleted_at")
    .in(column, ids)
    .is("deleted_at", null);
  throwIfPostgrestError(`verify ${table} excluded from reads`, error);
  const leftover = data ?? [];
  if (leftover.length > 0) {
    throw new Error(
      `teardown left live ${table} rows: ${
        leftover.map((row) => row.id).join(", ")
      }. ` +
        "Cleanup did not exclude them from reads.",
    );
  }
}
