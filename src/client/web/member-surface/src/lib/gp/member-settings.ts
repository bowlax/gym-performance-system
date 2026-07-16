import type { SupabaseClient } from "@supabase/supabase-js";
import type { StalenessSetting } from "@gp-shared/pb-derivation.ts";
import { stalenessFromMemberRow } from "./derive-pb-reads";

/** Updates the signed-in member's staleness settings under RLS. */
export async function updateMemberStaleness(
  supabase: SupabaseClient,
  setting: StalenessSetting,
): Promise<StalenessSetting> {
  const unit = setting.unit === "months" ? "month" : "quarter";
  const { data, error } = await supabase
    .from("members")
    .update({
      staleness_enabled: setting.enabled,
      staleness_periods: Math.max(1, setting.periods),
      staleness_unit: unit,
      updated_at: new Date().toISOString(),
    })
    .select("staleness_enabled, staleness_periods, staleness_unit")
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data) throw new Error("Could not update staleness settings");
  return stalenessFromMemberRow(data as Record<string, unknown>);
}
