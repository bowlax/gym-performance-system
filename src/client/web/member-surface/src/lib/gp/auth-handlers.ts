/**
 * Injectable OAuth callback + session resolution — unit-tested without h3 ALS.
 * Route files wire these to real sealed-cookie + GoTrue helpers.
 */

import {
  assertCleanRedirectLocation,
  parseCallbackSessionParams,
  sessionNeedsRefresh,
  toSessionJson,
  type AuthSessionData,
  type GoTrueRefreshedSession,
  type SessionJsonResponse,
} from "./auth-session";

const NO_STORE = { "Cache-Control": "private, no-store" };

export interface AuthSessionStore {
  read(): Promise<AuthSessionData | null>;
  write(data: AuthSessionData): Promise<void>;
  clear(): Promise<void>;
}

export async function handleOAuthCallback(
  request: Request,
  store: Pick<AuthSessionStore, "write">,
): Promise<Response> {
  const url = new URL(request.url);
  const session = parseCallbackSessionParams(url);

  if (!session) {
    return Response.json(
      {
        error:
          "OAuth callback missing access_token/token, refresh_token, or expires_at",
      },
      { status: 400, headers: NO_STORE },
    );
  }

  await store.write(session);

  const location = "/";
  assertCleanRedirectLocation(location);

  return new Response(null, {
    status: 302,
    headers: {
      Location: location,
      "Cache-Control": "private, no-store",
    },
  });
}

export async function handleAuthSessionGet(params: {
  store: AuthSessionStore;
  refresh: (refreshToken: string) => Promise<GoTrueRefreshedSession>;
  nowSeconds?: number;
}): Promise<Response> {
  const nowSeconds = params.nowSeconds ?? Math.floor(Date.now() / 1000);
  const existing = await params.store.read();
  if (!existing) {
    return Response.json({ error: "Unauthorized" }, { status: 401, headers: NO_STORE });
  }

  if (!sessionNeedsRefresh(existing.expiresAt, nowSeconds)) {
    return Response.json(toSessionJson(existing), { headers: NO_STORE });
  }

  try {
    const refreshed = await params.refresh(existing.refreshToken);
    const next: AuthSessionData = {
      accessToken: refreshed.accessToken,
      refreshToken: refreshed.refreshToken,
      expiresAt: refreshed.expiresAt,
      issuedAt: nowSeconds,
    };
    await params.store.write(next);
    return Response.json(toSessionJson(next), { headers: NO_STORE });
  } catch (error) {
    await params.store.clear().catch(() => undefined);
    const message =
      error instanceof Error ? error.message : "Session refresh failed";
    return Response.json({ error: message }, { status: 401, headers: NO_STORE });
  }
}

/** Compile-time + runtime check: client JSON never carries refresh_token. */
export function assertSessionJsonSafe(body: SessionJsonResponse): void {
  const keys = Object.keys(body);
  if (keys.includes("refresh_token") || keys.includes("refreshToken")) {
    throw new Error("Session JSON must never include refresh_token");
  }
  if (!("token" in body) || typeof body.token !== "string") {
    throw new Error("Session JSON must include token");
  }
}
