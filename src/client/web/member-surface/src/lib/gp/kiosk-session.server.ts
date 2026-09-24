import "@tanstack/react-start/server-only";

import {
  clearSession,
  useSession,
  type SessionConfig,
} from "@tanstack/react-start/server";
import {
  isValidAuthSessionData,
  sessionNeedsRefresh,
  type AuthSessionData,
} from "./auth-session";
import {
  KIOSK_SESSION_COOKIE,
  KIOSK_SESSION_MAX_AGE_SECONDS,
} from "./kiosk-session";
import { readSessionSecret } from "./session.server";
import { refreshGoTrueSession } from "./gotrue-refresh.server";
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from "./env";

export function kioskSessionConfig(password: string): SessionConfig {
  return {
    name: KIOSK_SESSION_COOKIE,
    password,
    maxAge: KIOSK_SESSION_MAX_AGE_SECONDS,
    cookie: {
      httpOnly: true,
      secure: !import.meta.env.DEV,
      sameSite: "lax",
      path: "/",
    },
    sessionHeader: false,
  };
}

export async function readKioskSession(): Promise<AuthSessionData | null> {
  const session = await useSession<AuthSessionData>(
    kioskSessionConfig(readSessionSecret()),
  );
  const data = session.data;
  if (!isValidAuthSessionData(data)) return null;
  return {
    accessToken: data.accessToken,
    refreshToken: data.refreshToken,
    expiresAt: data.expiresAt,
    issuedAt: data.issuedAt,
  };
}

export async function writeKioskSession(data: AuthSessionData): Promise<void> {
  const session = await useSession<AuthSessionData>(
    kioskSessionConfig(readSessionSecret()),
  );
  await session.update(data);
}

export async function clearKioskSession(): Promise<void> {
  await clearSession(kioskSessionConfig(readSessionSecret()));
}

/** Refresh the owner access token when needed and slide the cookie. */
export async function readFreshKioskSession(): Promise<AuthSessionData | null> {
  const existing = await readKioskSession();
  if (!existing) return null;
  const nowSeconds = Math.floor(Date.now() / 1000);
  let next = existing;
  if (sessionNeedsRefresh(existing.expiresAt, nowSeconds)) {
    if (!SUPABASE_URL || !SUPABASE_PUBLISHABLE_KEY) {
      await clearKioskSession();
      return null;
    }
    try {
      const refreshed = await refreshGoTrueSession({
        refreshToken: existing.refreshToken,
        supabaseUrl: SUPABASE_URL,
        publishableKey: SUPABASE_PUBLISHABLE_KEY,
        nowSeconds,
      });
      next = {
        accessToken: refreshed.accessToken,
        refreshToken: refreshed.refreshToken,
        expiresAt: refreshed.expiresAt,
        issuedAt: nowSeconds,
      };
    } catch {
      await clearKioskSession();
      return null;
    }
  }
  await writeKioskSession(next);
  return next;
}
