import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  buildBrokerAuthorizeUrl,
  type SessionJsonResponse,
} from "./auth-session";
import { getOrCreateDeviceMemberId } from "./device-member-id";
import { oauthCallbackUrl, TOKEN_BROKER_URL } from "./env";
import { createGymPerfClient } from "./supabase-client";
import { isStubBrokerAllowed } from "./stub-broker-guard";
import { StubTeamUpBroker, type BrokerSession, type TokenBroker } from "./token-broker";

export type AuthStatus = "idle" | "loading" | "ready" | "signed_out" | "error";

interface AuthState {
  status: AuthStatus;
  session: BrokerSession | null;
  supabase: SupabaseClient | null;
  error: Error | null;
  refresh: () => Promise<void>;
  signIn: () => void;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);

interface AuthProviderProps {
  /** Override for tests; production ignores and uses /api/auth/session. */
  broker?: TokenBroker;
  children: ReactNode;
}

/**
 * AuthProvider holds the access token for createGymPerfClient.
 *
 * Production: GET /api/auth/session (sealed cookie + server-side GoTrue refresh).
 * Sign-in navigates to the TeamUp OAuth broker authorize URL.
 * Dev stub: only when VITE_GYMPERF_USE_STUB_BROKER=true in a non-PROD build.
 */
export function AuthProvider({ broker, children }: AuthProviderProps) {
  const [status, setStatus] = useState<AuthStatus>("idle");
  const [session, setSession] = useState<BrokerSession | null>(null);
  const [error, setError] = useState<Error | null>(null);
  const mintingRef = useRef<Promise<void> | null>(null);

  const useStub = broker != null || isStubBrokerAllowed();
  const stubBroker = useMemo(
    () => broker ?? (isStubBrokerAllowed() ? new StubTeamUpBroker() : null),
    [broker],
  );

  const refresh = useCallback(async () => {
    if (mintingRef.current) return mintingRef.current;
    setStatus("loading");
    setError(null);
    const p = (async () => {
      try {
        if (useStub && stubBroker) {
          const s = await stubBroker.mint();
          setSession(s);
          setStatus("ready");
          return;
        }

        const response = await fetch("/api/auth/session", {
          method: "GET",
          credentials: "same-origin",
          headers: { Accept: "application/json" },
        });

        if (response.status === 401) {
          setSession(null);
          setStatus("signed_out");
          return;
        }

        if (!response.ok) {
          const detail = await response.text().catch(() => "");
          throw new Error(
            `Session endpoint failed (${response.status}). ${detail}`,
          );
        }

        const json = (await response.json()) as SessionJsonResponse;
        if (typeof json.token !== "string" || json.token.length === 0) {
          throw new Error("Session endpoint returned no token");
        }
        // Defense: never treat a refresh_token field as usable client state.
        if (
          "refresh_token" in (json as object) ||
          "refreshToken" in (json as object)
        ) {
          throw new Error("Session endpoint leaked refresh_token");
        }

        setSession({
          token: json.token,
          expiresAt: json.expiresAt,
          raw: { token: json.token, expiresAt: json.expiresAt },
        });
        setStatus("ready");
      } catch (e) {
        setSession(null);
        setError(e instanceof Error ? e : new Error(String(e)));
        setStatus("error");
      } finally {
        mintingRef.current = null;
      }
    })();
    mintingRef.current = p;
    return p;
  }, [stubBroker, useStub]);

  const signIn = useCallback(() => {
    if (useStub && stubBroker) {
      void refresh();
      return;
    }
    if (!TOKEN_BROKER_URL) {
      setError(new Error("Token broker URL is not configured"));
      setStatus("error");
      return;
    }
    const deviceMemberId = getOrCreateDeviceMemberId();
    const url = buildBrokerAuthorizeUrl({
      brokerBaseUrl: TOKEN_BROKER_URL,
      deviceMemberId,
      returnUrl: oauthCallbackUrl(),
      surface: "memberWeb",
    });
    window.location.assign(url);
  }, [refresh, stubBroker, useStub]);

  const signOut = useCallback(async () => {
    try {
      if (!useStub) {
        await fetch("/api/auth/signout", {
          method: "POST",
          credentials: "same-origin",
        });
      }
    } finally {
      setSession(null);
      setStatus("signed_out");
      setError(null);
    }
  }, [useStub]);

  useEffect(() => {
    if (status === "idle" && typeof window !== "undefined") {
      void refresh();
    }
  }, [status, refresh]);

  const supabase = useMemo(
    () => (session ? createGymPerfClient(session.token) : null),
    [session],
  );

  const value = useMemo<AuthState>(
    () => ({ status, session, supabase, error, refresh, signIn, signOut }),
    [status, session, supabase, error, refresh, signIn, signOut],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside <AuthProvider>");
  return ctx;
}

/**
 * Convenience for screens that require a live session. Callers can render
 * loading/error UI based on the returned state, or use the supabase client
 * directly once ready.
 */
export function useSupabase(): SupabaseClient | null {
  return useAuth().supabase;
}
