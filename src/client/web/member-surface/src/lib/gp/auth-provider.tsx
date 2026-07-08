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
import { defaultBroker, type BrokerSession, type TokenBroker } from "./token-broker";
import { createGymPerfClient } from "./supabase-client";

interface AuthState {
  status: "idle" | "loading" | "ready" | "error";
  session: BrokerSession | null;
  supabase: SupabaseClient | null;
  error: Error | null;
  refresh: () => Promise<void>;
  signOut: () => void;
}

const AuthContext = createContext<AuthState | null>(null);

interface AuthProviderProps {
  broker?: TokenBroker;
  children: ReactNode;
}

/**
 * AuthProvider mints and holds the broker session on the client. It runs
 * only in the browser — SSR renders children with a loading state.
 *
 * Later, swap `broker` for a real TeamUp OAuth broker without touching
 * consumers.
 */
export function AuthProvider({ broker = defaultBroker, children }: AuthProviderProps) {
  const [status, setStatus] = useState<AuthState["status"]>("idle");
  const [session, setSession] = useState<BrokerSession | null>(null);
  const [error, setError] = useState<Error | null>(null);
  const mintingRef = useRef<Promise<void> | null>(null);

  const refresh = useCallback(async () => {
    if (mintingRef.current) return mintingRef.current;
    setStatus("loading");
    setError(null);
    const p = (async () => {
      try {
        const s = await broker.mint();
        setSession(s);
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
  }, [broker]);

  const signOut = useCallback(() => {
    setSession(null);
    setStatus("idle");
    setError(null);
  }, []);

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
    () => ({ status, session, supabase, error, refresh, signOut }),
    [status, session, supabase, error, refresh, signOut],
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