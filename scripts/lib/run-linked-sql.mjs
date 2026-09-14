import { spawnSync } from "node:child_process";
import { unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Privileged hard-delete path: Postgres via `supabase db query --linked`.
 * Not PostgREST service_role.delete() (no GRANT DELETE).
 */
export function runLinkedSql(root, sql, label) {
  const file = join(root, "scripts", `.tmp-${label}.sql`);
  writeFileSync(file, sql, "utf8");
  try {
    const result = spawnSync(
      "npx",
      ["supabase", "db", "query", "--linked", "-f", file],
      { cwd: root, encoding: "utf8" },
    );
    if (result.status !== 0) {
      throw new Error(
        `${label} linked SQL failed (status ${result.status}): ${
          result.stderr || result.stdout || "no output"
        }`,
      );
    }
    return result.stdout;
  } finally {
    try {
      unlinkSync(file);
    } catch {
      // temp file already gone
    }
  }
}

export const WOLF_GYM_ID = "0abc9301-b048-40f5-8bdc-9bb389916b59";

export function isolatedGymWipeSql(gymId) {
  if (gymId === WOLF_GYM_ID) {
    throw new Error("refusing to wipe Wolf gym");
  }
  return `begin;
do $guard$
begin
  if '${gymId}'::uuid = '${WOLF_GYM_ID}'::uuid then
    raise exception 'refusing to wipe Wolf gym';
  end if;
end
$guard$;
delete from sets where gym_id = '${gymId}'::uuid;
delete from exercise_entries where gym_id = '${gymId}'::uuid;
delete from personal_bests where gym_id = '${gymId}'::uuid;
delete from exercise_resets where gym_id = '${gymId}'::uuid;
delete from sessions where gym_id = '${gymId}'::uuid;
delete from exercises where gym_id = '${gymId}'::uuid;
delete from members where gym_id = '${gymId}'::uuid;
delete from owner_surface_grants where gym_id = '${gymId}'::uuid;
delete from gyms where id = '${gymId}'::uuid;
commit;
`;
}
