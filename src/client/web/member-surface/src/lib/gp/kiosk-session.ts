/** Separate from the member TeamUp cookie (`gp_auth`). */
export const KIOSK_SESSION_COOKIE = "gp_kiosk";

/**
 * Browser cap is 400 days. Each kiosk request rewrites the cookie, so a
 * device that is used at least that often stays signed in.
 */
export const KIOSK_SESSION_MAX_AGE_SECONDS = 60 * 60 * 24 * 400;
