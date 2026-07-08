import { Link, useRouterState } from "@tanstack/react-router";
import { type ReactNode } from "react";
import { ListChecks, PlusCircle } from "lucide-react";
import { cn } from "@/lib/utils";

const NAV = [
  { to: "/", label: "Board", icon: ListChecks },
  { to: "/log", label: "Log a Session", icon: PlusCircle },
] as const;

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = useRouterState({ select: (s) => s.location.pathname });

  return (
    <div className="min-h-screen bg-background text-foreground">
      <header className="sticky top-0 z-10 border-b border-border bg-background/85 backdrop-blur-md">
        <div className="mx-auto flex max-w-3xl items-center gap-2 px-4 py-3">
          <Link to="/" className="flex items-center gap-2">
            <span className="inline-block size-2 rounded-full bg-primary" />
            <span className="text-sm font-semibold tracking-tight text-foreground">
              GymPerformance
            </span>
          </Link>
        </div>
      </header>
      <main className="mx-auto max-w-3xl px-4 pt-6 pb-28">{children}</main>
      <nav
        aria-label="Primary"
        className="fixed inset-x-0 bottom-0 z-20 border-t border-border bg-background/95 backdrop-blur-md pb-[env(safe-area-inset-bottom)]"
      >
        <ul className="mx-auto flex max-w-3xl items-stretch justify-center gap-8 px-4 py-2">
          {NAV.map((item) => {
            const active =
              item.to === "/"
                ? pathname === "/"
                : pathname.startsWith(item.to);
            const Icon = item.icon;
            return (
              <li key={item.to}>
                <Link
                  to={item.to}
                  className={cn(
                    "flex min-w-[72px] flex-col items-center justify-center gap-1 rounded-lg px-3 py-1.5 transition-colors",
                    active
                      ? "text-primary"
                      : "text-muted-foreground hover:text-foreground",
                  )}
                  aria-current={active ? "page" : undefined}
                >
                  <Icon
                    className="size-6"
                    strokeWidth={active ? 2.4 : 2}
                    aria-hidden
                  />
                  <span className="text-[11px] font-medium leading-none">
                    {item.label}
                  </span>
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>
    </div>
  );
}

export function SectionHeader({
  title,
  caption,
}: {
  title: string;
  caption?: string;
}) {
  return (
    <div className="mb-3 flex items-end justify-between gap-4">
      <h2 className="text-xs font-semibold uppercase tracking-[0.08em] text-muted-foreground">
        {title}
      </h2>
      {caption && <p className="text-xs text-muted-foreground">{caption}</p>}
    </div>
  );
}

export function PlaceholderScreen({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight text-foreground">
          {title}
        </h1>
        <p className="mt-1 text-sm text-muted-foreground">{description}</p>
      </div>
      <div className="rounded-[16px] bg-card p-4">
        <div className="flex items-center justify-between border-b border-border/50 py-3 last:border-0">
          <div className="text-sm font-medium text-foreground">Coming next stage</div>
          <div className="text-xs text-muted-foreground">Not wired</div>
        </div>
        <div className="flex items-center justify-between border-b border-border/50 py-3 last:border-0">
          <div className="text-sm font-medium text-foreground">Design already established</div>
          <div className="text-xs text-muted-foreground">Placeholder</div>
        </div>
        <div className="flex items-center justify-between py-3">
          <div className="text-sm font-medium text-foreground">Data reads deferred</div>
          <div className="text-xs text-muted-foreground">Stage 2</div>
        </div>
      </div>
    </div>
  );
}

export function AuthGate({
  status,
  error,
  onRetry,
  children,
}: {
  status: "idle" | "loading" | "ready" | "error";
  error: Error | null;
  onRetry: () => void;
  children: ReactNode;
}) {
  if (status === "ready") return <>{children}</>;
  if (status === "error") {
    return (
      <div className="rounded-[16px] bg-card p-4">
        <div className="text-sm font-semibold text-foreground">
          Couldn't sign you in
        </div>
        <p className="mt-1 text-xs text-muted-foreground">
          {error?.message ?? "The token broker did not return a session."}
        </p>
        <button
          type="button"
          onClick={onRetry}
          className="mt-3 inline-flex h-10 items-center justify-center rounded-[12px] bg-primary px-4 text-sm font-semibold text-primary-foreground"
        >
          Try again
        </button>
      </div>
    );
  }
  return (
    <div className="rounded-[16px] bg-card p-4 text-sm text-muted-foreground">
      Signing you in…
    </div>
  );
}