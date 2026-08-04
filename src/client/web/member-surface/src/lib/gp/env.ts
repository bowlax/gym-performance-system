/**
 * Public GymPerformance runtime config. These values are baked into the
 * client bundle at build time via `vite.config.ts` `define`, sourced from
 * project env vars. The Supabase publishable (anon) key is safe to expose
 * to browsers — it identifies the project to PostgREST, but data access is
 * still gated by RLS + the session JWT.
 *
 * SESSION_SECRET is NOT listed here — it is a Cloudflare runtime secret
 * (wrangler secret / .dev.vars), never baked into the client.
 */
export const SUPABASE_URL =
  import.meta.env.VITE_GYMPERF_SUPABASE_URL ?? "";

export const SUPABASE_PUBLISHABLE_KEY =
  import.meta.env.VITE_GYMPERF_SUPABASE_PUBLISHABLE_KEY ?? "";

/** Stub-broker only. Unused when real OAuth is active. */
export const TEST_DEVICE_MEMBER_ID =
  import.meta.env.VITE_GYMPERF_TEST_DEVICE_MEMBER_ID ?? "";

export const TOKEN_BROKER_URL = `${SUPABASE_URL}/functions/v1/token-broker`;
export const LOG_SET_URL = `${SUPABASE_URL}/functions/v1/log-set`;
export const ADD_MANUAL_PB_URL = `${SUPABASE_URL}/functions/v1/add-manual-pb`;
export const RESET_CURRENT_PB_URL = `${SUPABASE_URL}/functions/v1/reset-current-pb`;
export const DELETE_PERSONAL_BEST_URL = `${SUPABASE_URL}/functions/v1/delete-personal-best`;

/** OAuth return target for the broker redirect (server route). */
export function oauthCallbackUrl(origin: string = defaultOrigin()): string {
  return `${origin.replace(/\/$/, "")}/auth/callback`;
}

function defaultOrigin(): string {
  if (typeof window !== "undefined" && window.location?.origin) {
    return window.location.origin;
  }
  return "";
}

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
}
