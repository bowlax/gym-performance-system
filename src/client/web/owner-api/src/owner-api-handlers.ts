import { authorizeBotKey } from "./bot-auth";
import { refreshGoTrueSession } from "./gotrue-refresh";
import {
  isValidOwnerSessionData,
  readSealedOwnerSession,
  sessionNeedsRefresh,
  writeSealedOwnerSession,
  type OwnerSessionData,
  type OwnerSessionKv,
} from "./session-store";

const NO_STORE = { "Cache-Control": "private, no-store" };
const JSON_HEADERS = {
  ...NO_STORE,
  "Content-Type": "application/json",
};

export interface OwnerApiEnv {
  OWNER_BOT_KEY: string;
  OWNER_SESSION_SECRET: string;
  OWNER_SESSION: OwnerSessionKv;
  SUPABASE_URL: string;
  SUPABASE_PUBLISHABLE_KEY: string;
}

export interface OwnerApiDeps {
  fetchImpl?: typeof fetch;
  nowSeconds?: number;
}

const ROUTES: Record<string, string> = {
  "/api/owner/current-pbs": "owner-current-pbs",
  "/api/owner/pb-frequency": "owner-pb-frequency",
  "/api/owner/members": "owner-member-names",
};

function jsonError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: JSON_HEADERS,
  });
}

function containsSecret(haystack: string, secret: string | undefined): boolean {
  return Boolean(secret && secret.length > 0 && haystack.includes(secret));
}

function assertSafeBody(body: string, env: OwnerApiEnv, session: OwnerSessionData | null): void {
  if (containsSecret(body, env.OWNER_BOT_KEY)) {
    throw new Error("Refusing to return a body that contains the bot key");
  }
  if (containsSecret(body, env.OWNER_SESSION_SECRET)) {
    throw new Error("Refusing to return a body that contains the session secret");
  }
  if (session && containsSecret(body, session.refreshToken)) {
    throw new Error("Refusing to return a body that contains a refresh token");
  }
  if (session && containsSecret(body, session.accessToken)) {
    throw new Error("Refusing to return a body that contains an access token");
  }
}

async function resolveOwnerAccessToken(
  env: OwnerApiEnv,
  deps: OwnerApiDeps,
): Promise<{ token: string; session: OwnerSessionData }> {
  const nowSeconds = deps.nowSeconds ?? Math.floor(Date.now() / 1000);
  const existing = await readSealedOwnerSession(
    env.OWNER_SESSION,
    env.OWNER_SESSION_SECRET,
  );
  if (!existing) {
    throw jsonError(503, "Owner session not provisioned");
  }

  if (!sessionNeedsRefresh(existing.expiresAt, nowSeconds)) {
    return { token: existing.accessToken, session: existing };
  }

  const refreshed = await refreshGoTrueSession({
    refreshToken: existing.refreshToken,
    supabaseUrl: env.SUPABASE_URL,
    publishableKey: env.SUPABASE_PUBLISHABLE_KEY,
    fetchImpl: deps.fetchImpl,
    nowSeconds,
  });
  const next: OwnerSessionData = {
    accessToken: refreshed.accessToken,
    refreshToken: refreshed.refreshToken,
    expiresAt: refreshed.expiresAt,
    issuedAt: nowSeconds,
  };
  if (!isValidOwnerSessionData(next)) {
    throw jsonError(503, "Owner session refresh produced an invalid session");
  }
  await writeSealedOwnerSession(env.OWNER_SESSION, env.OWNER_SESSION_SECRET, next);
  return { token: next.accessToken, session: next };
}

export async function proxyOwnerFunction(
  env: OwnerApiEnv,
  functionSlug: string,
  accessToken: string,
  request: Request,
  deps: OwnerApiDeps,
): Promise<Response> {
  const fetchImpl = deps.fetchImpl ?? fetch;
  let upstreamBody = "{}";
  if (request.method === "POST") {
    const text = await request.text();
    upstreamBody = text.length > 0 ? text : "{}";
  }

  const url = new URL(request.url);
  const target = new URL(
    `functions/v1/${functionSlug}`,
    env.SUPABASE_URL.endsWith("/") ? env.SUPABASE_URL : `${env.SUPABASE_URL}/`,
  );
  if (url.searchParams.get("refresh") === "1") {
    target.searchParams.set("refresh", "1");
  }

  const upstream = await fetchImpl(target.toString(), {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      "Content-Type": "application/json",
    },
    body: upstreamBody,
  });

  const text = await upstream.text();
  return new Response(text, {
    status: upstream.status,
    headers: JSON_HEADERS,
  });
}

export async function handleOwnerFetch(
  request: Request,
  env: OwnerApiEnv,
  deps: OwnerApiDeps = {},
): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === "OPTIONS" && url.pathname.startsWith("/api/owner/")) {
    return new Response(null, { status: 204, headers: NO_STORE });
  }

  const functionSlug = ROUTES[url.pathname];
  if (!functionSlug) {
    return jsonError(404, "Not found");
  }
  if (request.method !== "POST") {
    return jsonError(405, "Method not allowed");
  }

  const auth = authorizeBotKey(request, env.OWNER_BOT_KEY);
  if (auth === "missing") return jsonError(401, "Unauthorized");
  if (auth !== "ok") return jsonError(403, "Forbidden");

  let session: OwnerSessionData | null = null;
  try {
    const resolved = await resolveOwnerAccessToken(env, deps);
    session = resolved.session;
    const response = await proxyOwnerFunction(
      env,
      functionSlug,
      resolved.token,
      request,
      deps,
    );
    const body = await response.text();
    assertSafeBody(body, env, session);
    return new Response(body, {
      status: response.status,
      headers: JSON_HEADERS,
    });
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonError(502, "Owner upstream failed");
  }
}

export async function handleOwnerScheduled(
  env: OwnerApiEnv,
  deps: OwnerApiDeps = {},
): Promise<void> {
  const resolved = await resolveOwnerAccessToken(env, deps);
  const refreshRequest = new Request("https://owner.local/api/owner/members?refresh=1", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh: true }),
  });
  const response = await proxyOwnerFunction(
    env,
    "owner-member-names",
    resolved.token,
    refreshRequest,
    deps,
  );
  if (!response.ok) {
    throw new Error(`Scheduled name refresh failed (HTTP ${response.status})`);
  }
}
