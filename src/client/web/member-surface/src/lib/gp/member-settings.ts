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
  const identityId = await resolveOwnMemberId(supabase);

  const { data, error } = await supabase
    .from("members")
    .update(memberStalenessPatchFields(setting))
    .eq("id", identityId)
    .select("staleness_enabled, staleness_periods, staleness_unit")
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data) throw new Error("Could not update staleness settings");
  return stalenessFromMemberRow(data as Record<string, unknown>);
}

/** Default subscribed: null/`""` means reminder emails are on. */
export function logReminderEmailsEnabledFromRow(
  row: { log_reminder_email_opted_out_at?: unknown } | null,
): boolean {
  const value = row?.log_reminder_email_opted_out_at;
  return value == null || value === "";
}

/**
 * Dedicated reminder-opt-out PATCH. Must not be mixed into staleness saves —
 * rewriting this column on every PB-settings persist would undo an email
 * unsubscribe.
 */
export function memberLogReminderEmailsPatchFields(
  enabled: boolean,
  now: Date = new Date(),
): Record<string, unknown> {
  const iso = now.toISOString();
  return {
    log_reminder_email_opted_out_at: enabled ? null : iso,
    updated_at: iso,
    synced_at: iso,
  };
}

export async function fetchLogReminderEmailsEnabled(
  supabase: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabase
    .from("members")
    .select("log_reminder_email_opted_out_at")
    .maybeSingle();
  if (error) throw new Error(error.message);
  return logReminderEmailsEnabledFromRow(
    data as { log_reminder_email_opted_out_at?: unknown } | null,
  );
}

export async function updateLogReminderEmailsEnabled(
  supabase: SupabaseClient,
  enabled: boolean,
): Promise<boolean> {
  const identityId = await resolveOwnMemberId(supabase);

  const { data, error } = await supabase
    .from("members")
    .update(memberLogReminderEmailsPatchFields(enabled))
    .eq("id", identityId)
    .select("log_reminder_email_opted_out_at")
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data) throw new Error("Could not update reminder email settings");
  return logReminderEmailsEnabledFromRow(
    data as { log_reminder_email_opted_out_at?: unknown },
  );
}

async function resolveOwnMemberId(supabase: SupabaseClient): Promise<string> {
  // PostgREST requires an explicit WHERE on UPDATE (RLS alone is not enough).
  const { data: identity, error: identityError } = await supabase
    .from("members")
    .select("id")
    .maybeSingle();
  if (identityError) throw new Error(identityError.message);
  if (!identity?.id) throw new Error("Could not resolve member identity");
  return String(identity.id);
}
