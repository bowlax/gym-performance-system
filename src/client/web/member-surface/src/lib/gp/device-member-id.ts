import {
  DEVICE_MEMBER_ID_COOKIE,
  isDeviceMemberId,
} from "./auth-session";

/**
 * Web analog of iOS AccessControl.persistedMemberId():
 * generate a UUID once per browser profile, persist it, reuse forever.
 *
 * Stored in a non-httpOnly cookie so client JS can put it on the broker
 * authorize URL (separate from the sealed httpOnly auth session cookie).
 */
const MAX_AGE_SECONDS = 60 * 60 * 24 * 365 * 10;

export function getOrCreateDeviceMemberId(
  cookieSource: string = typeof document !== "undefined" ? document.cookie : "",
  writeCookie: (value: string) => void = writeDeviceMemberIdCookie,
): string {
  const existing = readDeviceMemberIdFromCookie(cookieSource);
  if (existing) return existing;

  const id = crypto.randomUUID();
  writeCookie(id);
  return id;
}

export function readDeviceMemberIdFromCookie(
  cookieSource: string,
): string | null {
  const parts = cookieSource.split(";").map((p) => p.trim());
  for (const part of parts) {
    const eq = part.indexOf("=");
    if (eq < 0) continue;
    const name = part.slice(0, eq);
    const value = decodeURIComponent(part.slice(eq + 1));
    if (name === DEVICE_MEMBER_ID_COOKIE && isDeviceMemberId(value)) {
      return value;
    }
  }
  return null;
}

export function writeDeviceMemberIdCookie(id: string): void {
  if (typeof document === "undefined") return;
  if (!isDeviceMemberId(id)) {
    throw new Error("deviceMemberId must be a UUID");
  }
  const secure =
    typeof location !== "undefined" && location.protocol === "https:"
      ? "; Secure"
      : "";
  document.cookie = `${DEVICE_MEMBER_ID_COOKIE}=${encodeURIComponent(id)}; Path=/; Max-Age=${MAX_AGE_SECONDS}; SameSite=Lax${secure}`;
}
