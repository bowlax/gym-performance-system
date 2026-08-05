import type { SupabaseClient } from "@supabase/supabase-js";
import type { StalenessSetting } from "@gp-shared/pb-derivation.ts";
import { stalenessFromMemberRow } from "./derive-pb-reads";

/**
 * Fields written on a members settings PATCH.
 *
 * Must set `synced_at` as well as `updated_at` so iOS incremental pull
 * (`synced_at > last-pull marker`) can see the row. LWW still decides the
 * winner from `updated_at` only — `synced_at` is the pull watermark, not
 * an iOS-sync-engine-only signal.
 */
export function memberStalenessPatchFields(
  setting: StalenessSetting,
  now: Date = new Date(),
): Record<string, unknown> {
  const unit = setting.unit === "months" ? "month" : "quarter";
  const iso = now.toISOString();
  return {
    staleness_enabled: setting.enabled,
    staleness_periods: Math.max(1, setting.periods),
    staleness_unit: unit,
    updated_at: iso,
    synced_at: iso,
  };
}

/** Updates the signed-in member's staleness settings under RLS. */
export async function updateMemberStaleness(
  supabase: SupabaseClient,
  setting: StalenessSetting,
): Promise<StalenessSetting> {
  // PostgREST requires an explicit WHERE on UPDATE (RLS alone is not enough).
  const { data: identity, error: identityError } = await supabase
    .from("members")
    .select("id")
    .maybeSingle();
  if (identityError) throw new Error(identityError.message);
  if (!identity?.id) throw new Error("Could not resolve member identity");

  const { data, error } = await supabase
    .from("members")
    .update(memberStalenessPatchFields(setting))
    .eq("id", identity.id)
    .select("staleness_enabled, staleness_periods, staleness_unit")
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data) throw new Error("Could not update staleness settings");
  return stalenessFromMemberRow(data as Record<string, unknown>);
}
