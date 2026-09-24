/**
 * Public GymPerformance runtime config. These values are baked into the
 * client bundle at build time via `vite.config.ts` `define`, sourced from
 * project env vars. The Supabase publishable (anon) key is safe to expose
 * to browsers — it identifies the project to PostgREST, but data access is
 * still gated by RLS + the session JWT.
 *
 * SESSION_SECRET is NOT listed here — it is a Cloudflare runtime secret
 * (wrangler secret / .dev.vars), never baked into the client.
 *
 * The project URL is the same one owner-api commits in wrangler.jsonc and
 * the live member web bundle. A missing build env, or the example host used
 * for a local stub, must not leave kiosk login pointed at a different store.
 */
export const WOLF_SUPABASE_URL = "https://ivrsxhuktebvypgtfoww.supabase.co";

/** Publishable key already shipped in the live member-web bundle. */
export const WOLF_SUPABASE_PUBLISHABLE_KEY =
  "sb_publishable_8exI94gG65l7izkBZtaGOw_Xi5Ui1H0";

export function resolveSupabasePublicValue(
  configured: string | undefined,
  fallback: string,
): string {
  const value = (configured ?? "").trim();
  if (
    !value ||
    value.includes("example.supabase.co") ||
    value === "example-publishable-key"
  ) {
    return fallback;
  }
  return value;
}

export const SUPABASE_URL = resolveSupabasePublicValue(
  import.meta.env.VITE_GYMPERF_SUPABASE_URL,
  WOLF_SUPABASE_URL,
);

export const SUPABASE_PUBLISHABLE_KEY = resolveSupabasePublicValue(
  import.meta.env.VITE_GYMPERF_SUPABASE_PUBLISHABLE_KEY,
  WOLF_SUPABASE_PUBLISHABLE_KEY,
);

/** Stub-broker only. Unused when real OAuth is active. */
export const TEST_DEVICE_MEMBER_ID =
  import.meta.env.VITE_GYMPERF_TEST_DEVICE_MEMBER_ID ?? "";

export const TOKEN_BROKER_URL = `${SUPABASE_URL}/functions/v1/token-broker`;
export const LOG_SET_URL = `${SUPABASE_URL}/functions/v1/log-set`;
export const LOG_SESSION_URL = `${SUPABASE_URL}/functions/v1/log-session`;
export const ADD_EXERCISES_TO_SESSION_URL =
  `${SUPABASE_URL}/functions/v1/add-exercises-to-session`;
export const ADD_MANUAL_PB_URL = `${SUPABASE_URL}/functions/v1/add-manual-pb`;
export const RESET_CURRENT_PB_URL = `${SUPABASE_URL}/functions/v1/reset-current-pb`;
export const DELETE_PERSONAL_BEST_URL = `${SUPABASE_URL}/functions/v1/delete-personal-best`;
export const DELETE_SESSION_URL = `${SUPABASE_URL}/functions/v1/delete-session`;
export const UPDATE_MANUAL_PB_URL = `${SUPABASE_URL}/functions/v1/update-manual-pb`;

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
