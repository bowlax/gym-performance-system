import { useState, useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { createFileRoute, Link } from "@tanstack/react-router";
import { Info, ChevronRight } from "lucide-react";
import {
  format,
  startOfMonth,
  addMonths,
  differenceInDays,
} from "date-fns";
import { PBCard } from "@/components/gp/pb-card";
import {
  Dialog,
  DialogContent,
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
  type SessionRow,
} from "@/lib/gp/queries";
import { formatPBValue } from "@/lib/gp/format";

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
    </AppShell>
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
  const { exercise, pb } = row;
  const measurement = exercise.measurement_type ?? "";
  const formatted = pb ? formatPBValue(pb.value, measurement) : null;
  const numeric = formatted ? Number(formatted.primary) : NaN;
  return (
    <Link
      to="/progression/$exerciseId"
      params={{ exerciseId: exercise.id }}
      className="block rounded-[16px] transition-transform hover:-translate-y-0.5 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-primary/20"
      aria-label={`Open progression for ${exercise.name}`}
    >
      {pb && formatted ? (
        <PBCard
          lift={exercise.name}
          value={
            Number.isFinite(numeric)
              ? numeric
              : (formatted.primary as unknown as number)
          }
          unit={formatted.unit || " "}
          achievedAt={
            pb.achieved_at
              ? `Set on ${new Date(pb.achieved_at).toLocaleDateString(undefined, {
                  day: "numeric",
                  month: "short",
                  year: "numeric",
                })}`
              : undefined
          }
          isPB
        />
      ) : (
        <EmptyExerciseCard name={exercise.name} />
      )}
    </Link>
  );
}

function EmptyExerciseCard({ name }: { name: string }) {
  return (
    <div className="relative overflow-hidden rounded-[16px] bg-card p-4 pl-5 text-card-foreground before:absolute before:inset-y-0 before:left-0 before:w-1 before:bg-primary">
      <div className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
        {name}
      </div>
      <div className="mt-3 flex items-baseline gap-1.5">
        <span className="font-numeric text-5xl font-semibold leading-none text-muted-foreground/60">
          –
        </span>
      </div>
      <div className="mt-3 text-xs text-muted-foreground">No PB yet</div>
    </div>
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
        <SessionDotPlot sessions={sessions} />
      </div>
    </div>
  );
}

function SessionDotPlot({ sessions }: { sessions: SessionRow[] }) {
  const { minMs, maxMs, rangeMs } = useMemo(() => {
    const dates = sessions.map((s) => new Date(s.date).getTime());
    const min = Math.min(...dates);
    const max = Math.max(...dates);

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const endMs = Math.max(max, today.getTime());

    const padMs = 1 * 24 * 60 * 60 * 1000;
    return {
      minMs: min - padMs,
      maxMs: endMs + padMs,
      rangeMs: endMs + padMs - (min - padMs),
    };
  }, [sessions]);

  const dayGroups = useMemo(() => {
    const groups = new Map<string, SessionRow[]>();
    for (const s of sessions) {
      const key = s.date.slice(0, 10);
      const arr = groups.get(key) ?? [];
      arr.push(s);
      groups.set(key, arr);
    }
    return groups;
  }, [sessions]);

  const months = useMemo(() => {
    const markers: { label: string; left: number }[] = [];
    const minDate = new Date(minMs);
    const maxDate = new Date(maxMs);
    let m = startOfMonth(minDate);
    while (m.getTime() <= maxDate.getTime()) {
      const pct =
        rangeMs > 0 ? ((m.getTime() - minMs) / rangeMs) * 100 : 0;
      if (pct >= -5 && pct <= 105) {
        markers.push({ label: format(m, "MMM"), left: pct });
      }
      m = addMonths(m, 1);
    }
    return markers;
  }, [minMs, maxMs, rangeMs]);

  const trackY = 56;

  return (
    <div className="relative h-20">
      <div
        className="absolute left-0 right-0 h-px bg-border"
        style={{ top: `${trackY}px` }}
      />

      {Array.from(dayGroups.entries()).map(([dateKey, daySessions]) => {
        const d = new Date(dateKey).getTime();
        const pct = rangeMs > 0 ? ((d - minMs) / rangeMs) * 100 : 50;

        return daySessions.map((s, i) => (
          <div
            key={s.id}
            className="absolute size-2 rounded-full bg-primary"
            style={{
              left: `${pct}%`,
              top: `${trackY - 6 - i * 14}px`,
              transform: "translateX(-50%)",
            }}
            title={format(new Date(s.date), "MMM d, yyyy")}
          />
        ));
      })}

      {months.map((m) => (
        <span
          key={m.label + m.left}
          className="absolute text-[10px] text-muted-foreground"
          style={{
            left: `${m.left}%`,
            top: `${trackY + 8}px`,
            transform: "translateX(-50%)",
          }}
        >
          {m.label}
        </span>
      ))}
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