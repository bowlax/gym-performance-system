import "@tanstack/react-start/server-only";

import {
  clearSession,
  useSession,
  type SessionConfig,
} from "@tanstack/react-start/server";
import {
  AUTH_SESSION_COOKIE,
  type AuthSessionData,
  isValidAuthSessionData,
} from "./auth-session";

/**
 * Sealed auth session cookie (TanStack Start / h3 iron seal).
 *
 * Password = Cloudflare runtime secret `SESSION_SECRET` (min 32 chars).
 * Never bake this into the client bundle — read per-request via Worker env /
 * Nitro `__env__` (unenv maps that onto `process.env` under nodejs_compat).
 */
export function readSessionSecret(): string {
  const fromProcess =
    typeof process !== "undefined" ? process.env.SESSION_SECRET : undefined;
  const fromNitroEnv =
    typeof globalThis !== "undefined"
      ? (globalThis as { __env__?: { SESSION_SECRET?: string } }).__env__
          ?.SESSION_SECRET
      : undefined;
  const secret = fromProcess ?? fromNitroEnv ?? "";
  if (secret.length < 32) {
    throw new Error(
      "SESSION_SECRET must be set (Cloudflare runtime secret / .dev.vars) and at least 32 characters.",
    );
  }
  return secret;
}

export function authSessionConfig(password: string): SessionConfig {
  return {
    name: AUTH_SESSION_COOKIE,
    password,
    // Long-lived cookie; GoTrue refresh keeps access tokens fresh.
    maxAge: 60 * 60 * 24 * 30,
    cookie: {
      httpOnly: true,
      // Secure on production Workers; allow http://localhost during vite dev.
      secure: !import.meta.env.DEV,
      sameSite: "lax",
      path: "/",
    },
    // Prefer cookie only — no session header leakage.
    sessionHeader: false,
  };
}

export async function readAuthSession(): Promise<AuthSessionData | null> {
  const config = authSessionConfig(readSessionSecret());
  const session = await useSession<AuthSessionData>(config);
  const data = session.data;
  if (!isValidAuthSessionData(data)) return null;
  return {
    accessToken: data.accessToken,
    refreshToken: data.refreshToken,
    expiresAt: data.expiresAt,
    issuedAt: data.issuedAt,
  };
}

export async function writeAuthSession(data: AuthSessionData): Promise<void> {
  const config = authSessionConfig(readSessionSecret());
  const session = await useSession<AuthSessionData>(config);
  await session.update({
    accessToken: data.accessToken,
    refreshToken: data.refreshToken,
    expiresAt: data.expiresAt,
    issuedAt: data.issuedAt,
  });
}

export async function clearAuthSession(): Promise<void> {
  const config = authSessionConfig(readSessionSecret());
  await clearSession(config);
}
