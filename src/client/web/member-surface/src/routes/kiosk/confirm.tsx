import { useEffect, useRef, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { AppShell } from "@/components/gp/app-shell";
import { useAuth } from "@/lib/gp/auth-provider";
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from "@/lib/gp/env";
import {
  KIOSK_CONFIRM_INVALID_MESSAGE,
  commitKioskPending,
  isKioskConfirmToken,
  stashKioskConfirmReturn,
  type CommitKioskPendingResult,
} from "@/lib/gp/kiosk-confirm";

type KioskConfirmSearch = {
  token?: string;
};

const inflight = new Map<string, Promise<CommitKioskPendingResult>>();

function commitOnce(rawToken: string, accessToken: string): Promise<CommitKioskPendingResult> {
  const existing = inflight.get(rawToken);
  if (existing) return existing;
  const promise = commitKioskPending({
    accessToken,
    rawToken,
    supabaseUrl: SUPABASE_URL,
    publishableKey: SUPABASE_PUBLISHABLE_KEY,
  });
  inflight.set(rawToken, promise);
  void promise.finally(() => {
    if (inflight.get(rawToken) === promise) inflight.delete(rawToken);
  });
  return promise;
}

export const Route = createFileRoute("/kiosk/confirm")({
  validateSearch: (search: Record<string, unknown>): KioskConfirmSearch => {
    const token = search.token;
    return typeof token === "string" ? { token } : {};
  },
  head: () => ({
    meta: [
      { title: "Confirm session — GymPerformance" },
      {
        name: "description",
        content: "Confirm a session logged on the gym kiosk.",
      },
    ],
  }),
  component: KioskConfirmScreen,
});

function KioskConfirmScreen() {
  const auth = useAuth();
  const { token } = Route.useSearch();
  const valid = isKioskConfirmToken(token);
  const [phase, setPhase] = useState<"pending" | "success" | "error">("pending");
  const [serverMessage, setServerMessage] = useState<string | null>(null);
  const [result, setResult] = useState<CommitKioskPendingResult | null>(null);
  const started = useRef(false);

  useEffect(() => {
    if (!valid || !token) return;
    if (auth.status !== "ready" || !auth.session?.token) return;
    if (started.current) return;
    started.current = true;

    const accessToken = auth.session.token;
    let cancelled = false;
    void commitOnce(token, accessToken).then(
      (value) => {
        if (cancelled) return;
        setResult(value);
        setPhase("success");
      },
      (error: unknown) => {
        if (cancelled) return;
        setServerMessage(
          error instanceof Error ? error.message : "Could not confirm this session.",
        );
        setPhase("error");
      },
    );
    return () => {
      cancelled = true;
    };
  }, [auth.session?.token, auth.status, token, valid]);

  function signInForThisLog() {
    if (valid && token) stashKioskConfirmReturn(token);
    auth.signIn();
  }

  return (
    <AppShell>
      <h1 className="text-2xl font-semibold tracking-tight text-foreground">Confirm session</h1>
      <div className="mt-6 rounded-[16px] bg-card p-4">
        {!valid ? (
          <p className="text-sm text-foreground">{KIOSK_CONFIRM_INVALID_MESSAGE}</p>
        ) : auth.status === "signed_out" ? (
          <SignedOut onSignIn={signInForThisLog} />
        ) : auth.status === "error" ? (
          <div>
            <p className="text-sm text-foreground">
              {auth.error?.message ?? "The session endpoint did not return a session."}
            </p>
            <SignInButton onSignIn={signInForThisLog} />
          </div>
        ) : auth.status !== "ready" || phase === "pending" ? (
          <p className="text-sm text-muted-foreground">
            {auth.status === "ready" ? "Saving this session…" : "Checking session…"}
          </p>
        ) : phase === "success" && result ? (
          <div>
            <p className="text-sm font-semibold text-foreground">Session confirmed.</p>
            <p className="mt-1 text-sm text-muted-foreground">Logged for {result.date}.</p>
            <Link
              to="/"
              className="mt-4 inline-flex h-10 items-center justify-center rounded-[12px] bg-primary px-4 text-sm font-semibold text-primary-foreground"
            >
              Back to your board
            </Link>
          </div>
        ) : (
          <p className="text-sm text-foreground">
            {serverMessage ?? "Could not confirm this session."}
          </p>
        )}
      </div>
    </AppShell>
  );
}

function SignedOut({ onSignIn }: { onSignIn: () => void }) {
  return (
    <div>
      <p className="text-sm text-foreground">Sign in as the member this log is for.</p>
      <SignInButton onSignIn={onSignIn} />
    </div>
  );
}

function SignInButton({ onSignIn }: { onSignIn: () => void }) {
  return (
    <button
      type="button"
      onClick={onSignIn}
      className="mt-3 inline-flex h-10 items-center justify-center rounded-[12px] bg-primary px-4 text-sm font-semibold text-primary-foreground"
    >
      Connect with TeamUp
    </button>
  );
}
