/**
 * Public GymPerformance runtime config. These values are baked into the
 * client bundle at build time via `vite.config.ts` `define`, sourced from
 * project env vars. The Supabase publishable (anon) key is safe to expose
 * to browsers — it identifies the project to PostgREST, but data access is
 * still gated by RLS + the broker-minted JWT.
 */
export const SUPABASE_URL =
  import.meta.env.VITE_GYMPERF_SUPABASE_URL ?? "";

export const SUPABASE_PUBLISHABLE_KEY =
  import.meta.env.VITE_GYMPERF_SUPABASE_PUBLISHABLE_KEY ?? "";

export const TEST_DEVICE_MEMBER_ID =
  import.meta.env.VITE_GYMPERF_TEST_DEVICE_MEMBER_ID ?? "";

export const TOKEN_BROKER_URL = `${SUPABASE_URL}/functions/v1/token-broker`;
export const LOG_SET_URL = `${SUPABASE_URL}/functions/v1/log-set`;

export function assertConfigured() {
  if (!SUPABASE_URL) {
    throw new Error(
      "Missing GYMPERF_SUPABASE_URL. Add it in Project Settings → Secrets.",
    );
  }
  if (!SUPABASE_PUBLISHABLE_KEY) {
    throw new Error(
      "Missing GYMPERF_SUPABASE_PUBLISHABLE_KEY. Add it in Project Settings → Secrets.",
    );
  }
  if (!TEST_DEVICE_MEMBER_ID) {
    throw new Error(
      "Missing TEST_DEVICE_MEMBER_ID. Add it in Project Settings → Secrets.",
    );
  }
}