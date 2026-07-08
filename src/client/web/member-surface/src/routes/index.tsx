import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { createFileRoute, Link, useRouterState } from "@tanstack/react-router";
import { Info, ChevronRight, Trophy } from "lucide-react";
import { PBCard } from "@/components/gp/pb-card";
import { CalendarHeatmap } from "@/components/gp/calendar-heatmap";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  AppShell,
  AuthGate,
  SectionHeader,
} from "@/components/gp/app-shell";
import { useAuth } from "@/lib/gp/auth-provider";
import {
  fetchBoard,
  fetchSessions,
  type BoardRow,
} from "@/lib/gp/queries";
import { formatBoardPBDate, formatBoardPBDisplay } from "@/lib/gp/format";
import { boardExerciseDestination } from "@/lib/gp/board-exercise-routing";
import {
  clearSessionSaveSummary,
  readSessionSaveSummary,
  sessionSaveSummaryFromLocationState,
  type SessionSaveSummary,
} from "@/lib/gp/session-save-summary";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "The Board — GymPerformance" },
      {
        name: "description",
        content: "Your current personal bests across every tracked lift.",
      },
      { property: "og:title", content: "The Board — GymPerformance" },
      {
        property: "og:description",
        content: "Your current personal bests across every tracked lift.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: BoardScreen,
});

function BoardScreen() {
  const auth = useAuth();
  const [aboutOpen, setAboutOpen] = useState(false);
  const [saveSummary, setSaveSummary] = useState<SessionSaveSummary | null>(
    null,
  );
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const locationState = useRouterState({ select: (s) => s.location.state });

  useEffect(() => {
    if (pathname !== "/") return;

    const fromNavigation = sessionSaveSummaryFromLocationState(locationState);
    const fromStorage = readSessionSaveSummary();
    const summary = fromNavigation ?? fromStorage;

    if (summary?.items.length) {
      setSaveSummary(summary);
    }
  }, [pathname, locationState]);

  function dismissSaveSummary() {
    clearSessionSaveSummary();
    setSaveSummary(null);
  }

  return (
    <AppShell>
      <div className="mb-6 flex items-center justify-between gap-4">
        <h1 className="text-2xl font-semibold tracking-tight text-foreground min-w-0">
          Personal Bests
        </h1>
        <button
          type="button"
          onClick={() => setAboutOpen(true)}
          aria-label="About"
          className="inline-flex size-9 shrink-0 items-center justify-center rounded-full text-muted-foreground hover:bg-muted hover:text-foreground"
        >
          <Info className="size-5" />
        </button>
      </div>
      <AuthGate
        status={auth.status}
        error={auth.error}
        onRetry={() => void auth.refresh()}
      >
        <BoardContent />
      </AuthGate>
      <AboutDialog open={aboutOpen} onClose={() => setAboutOpen(false)} />
      <SessionSavedDialog
        summary={saveSummary}
        onClose={dismissSaveSummary}
      />
    </AppShell>
  );
}

function SessionSavedDialog({
  summary,
  onClose,
}: {
  summary: SessionSaveSummary | null;
  onClose: () => void;
}) {
  const open = summary != null && summary.items.length > 0;
  const newPBCount =
    summary?.items.filter((item) => item.isPersonalBest).length ?? 0;
  const title =
    newPBCount > 0
      ? newPBCount === 1
        ? "New personal best!"
        : "New personal bests!"
      : "Session saved";

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-md gap-4">
        <DialogHeader>
          <div className="mx-auto mb-1 flex size-14 items-center justify-center rounded-full bg-pb-badge/20">
            <Trophy
              className={
                newPBCount > 0
                  ? "size-7 text-pb-foreground"
                  : "size-7 text-primary"
              }
              strokeWidth={2}
            />
          </div>
          <DialogTitle className="text-center text-xl">{title}</DialogTitle>
          <DialogDescription className="text-center">
            {newPBCount > 0
              ? "Here’s what you logged this session."
              : "Your session was recorded. Keep training."}
          </DialogDescription>
        </DialogHeader>
        {summary && (
          <ul className="space-y-2">
            {summary.items.map((item) => (
              <li
                key={item.exerciseId}
                className="flex items-center justify-between rounded-[12px] bg-muted/60 px-3 py-2.5 text-sm"
              >
                <span className="font-medium text-foreground">
                  {item.exerciseName}
                </span>
                {item.isPersonalBest ? (
                  <span className="inline-flex items-center gap-1 rounded-full bg-pb-badge px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wider text-pb-foreground">
                    <Trophy className="size-3" strokeWidth={2.5} />
                    New PB
                  </span>
                ) : (
                  <span className="text-xs text-muted-foreground">Logged</span>
                )}
              </li>
            ))}
          </ul>
        )}
        <DialogFooter>
          <Button type="button" onClick={onClose} className="w-full">
            Done
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function AboutDialog({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent
        className="max-w-md gap-0 p-0 [&>button]:hidden"
      >
        <div className="flex items-center justify-between border-b border-border px-4 py-3">
          <span className="w-12" aria-hidden />
          <DialogTitle className="text-base font-semibold">About</DialogTitle>
          <button
            type="button"
            onClick={onClose}
            className="text-sm font-semibold text-primary"
          >
            Done
          </button>
        </div>
        <div className="p-2">
          <Link
            to="/privacy"
            onClick={onClose}
            className="flex items-center justify-between rounded-[10px] px-3 py-3 text-sm font-medium text-foreground hover:bg-muted"
          >
            Privacy Policy
            <ChevronRight className="size-4 text-muted-foreground" />
          </Link>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function BoardContent() {
  const { supabase, session } = useAuth();

  const query = useQuery({
    queryKey: ["board", session?.token?.slice(-8) ?? "anon"],
    queryFn: () => {
      if (!supabase) throw new Error("Not signed in");
      return fetchBoard(supabase);
    },
    enabled: !!supabase,
  });

  if (query.isLoading) return <SkeletonGrid />;
  if (query.isError) {
    return (
      <div className="rounded-[16px] bg-card p-4">
        <div className="text-sm font-semibold text-foreground">
          Couldn't load your PBs
        </div>
        <p className="mt-1 text-xs text-muted-foreground">
          {(query.error as Error).message}
        </p>
      </div>
    );
  }

  const rows = query.data ?? [];
  if (rows.length === 0) return <EmptyBoard />;

  return (
    <div>
      <ConsistencySection />
      <div className="mt-8">
        <SectionHeader
          title="Current personal bests"
          caption={`${rows.length} exercise${rows.length === 1 ? "" : "s"}`}
        />
      </div>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {rows.map((row) => (
          <BoardCard key={row.exercise.id} row={row} />
        ))}
      </div>
    </div>
  );
}

function BoardCard({ row }: { row: BoardRow }) {
  const { exercise, pb, hasHistory } = row;
  const pbDisplay = pb ? formatBoardPBDisplay(pb, exercise) : undefined;
  const achievedAt =
    pb?.achieved_at != null ? formatBoardPBDate(pb.achieved_at) : undefined;
  const destination = boardExerciseDestination(!!pb, hasHistory);

  return (
    <Link
      to="/progression/$exerciseId"
      params={{ exerciseId: exercise.id }}
      search={destination === "manual" ? { manual: true } : {}}
      className="block rounded-[16px] transition-transform hover:-translate-y-0.5 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-primary/20"
      aria-label={
        destination === "manual"
          ? `Add first personal best for ${exercise.name}`
          : `Open progression for ${exercise.name}`
      }
    >
      <PBCard
        lift={exercise.name}
        value={pbDisplay}
        achievedAt={achievedAt}
      />
    </Link>
  );
}

function EmptyBoard() {
  return (
    <div>
      <ConsistencySection />
      <div className="rounded-[16px] bg-card p-6 text-center">
        <div className="text-sm font-semibold text-foreground">
          No personal bests yet
        </div>
        <p className="mt-1 text-xs text-muted-foreground">
          Log your first set and it'll show up here.
        </p>
      </div>
    </div>
  );
}

function ConsistencySection() {
  const { supabase, session } = useAuth();
  const query = useQuery({
    queryKey: ["sessions", session?.token?.slice(-8) ?? "anon"],
    queryFn: () => {
      if (!supabase) throw new Error("Not signed in");
      return fetchSessions(supabase);
    },
    enabled: !!supabase,
  });

  if (query.isLoading) {
    return (
      <div className="mt-8">
        <SectionHeader title="Training consistency" caption="Loading…" />
        <div className="h-24 animate-pulse rounded-[16px] bg-card" />
      </div>
    );
  }

  if (query.isError) {
    return (
      <div className="mt-8">
        <SectionHeader title="Training consistency" />
        <div className="rounded-[16px] bg-card p-4">
          <p className="text-sm text-muted-foreground">
            {(query.error as Error).message}
          </p>
        </div>
      </div>
    );
  }

  const sessions = query.data ?? [];
  if (sessions.length === 0) {
    return (
      <div className="mt-8">
        <SectionHeader title="Training consistency" />
        <div className="rounded-[16px] bg-card p-6 text-center">
          <p className="text-sm font-semibold text-foreground">
            No sessions yet
          </p>
          <p className="mt-1 text-xs text-muted-foreground">
            Log your first workout to see your consistency here.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="mt-8">
      <SectionHeader
        title="Training consistency"
        caption={`${sessions.length} session${sessions.length === 1 ? "" : "s"}`}
      />
      <div className="rounded-[16px] bg-card p-4">
        <CalendarHeatmap sessionDates={sessions.map((s) => s.date)} />
      </div>
    </div>
  );
}

function SkeletonGrid() {
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {Array.from({ length: 3 }).map((_, i) => (
        <div key={i} className="h-32 animate-pulse rounded-[16px] bg-card" aria-hidden />
      ))}
    </div>
  );
}