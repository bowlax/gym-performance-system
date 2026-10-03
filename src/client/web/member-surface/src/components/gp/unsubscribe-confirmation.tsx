import { Link } from "@tanstack/react-router";
import { ChevronLeft } from "lucide-react";
import { AppShell } from "@/components/gp/app-shell";
import type { UnsubscribeResult } from "@/lib/gp/unsubscribe-proxy";

export function UnsubscribeConfirmation({ result }: { result: UnsubscribeResult }) {
  return (
    <AppShell>
      <div className="mb-6 flex items-center justify-between">
        <Link
          to="/"
          className="inline-flex items-center gap-1 text-sm font-medium text-primary"
        >
          <ChevronLeft className="size-4" />
          Back
        </Link>
        <h1 className="text-base font-semibold text-foreground">
          Email reminders
        </h1>
        <span className="w-12" aria-hidden />
      </div>

      <div className="rounded-[16px] bg-card p-4">
        <h2 className="text-sm font-semibold text-foreground">
          {result.ok ? "You're unsubscribed" : "Couldn't update reminders"}
        </h2>
        <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
          {result.message}
        </p>
        {result.ok ? (
          <p className="mt-3 text-xs text-muted-foreground">
            Open Settings on the board if you want reminder emails again.
          </p>
        ) : null}
        <Link
          to="/"
          className="mt-4 inline-flex h-10 items-center justify-center rounded-[12px] bg-primary px-4 text-sm font-semibold text-primary-foreground"
        >
          Go to board
        </Link>
      </div>
    </AppShell>
  );
}
