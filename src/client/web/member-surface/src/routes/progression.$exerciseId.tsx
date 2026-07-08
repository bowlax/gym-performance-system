import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { AppShell, AuthGate, SectionHeader } from "@/components/gp/app-shell";
import { useAuth } from "@/lib/gp/auth-provider";
import {
  fetchExercise,
  fetchExerciseHistory,
  type PersonalBestHistoryRow,
  type ExerciseRow,
} from "@/lib/gp/queries";
import { formatPBValue } from "@/lib/gp/format";

export const Route = createFileRoute("/progression/$exerciseId")({
  head: () => ({
    meta: [
      { title: "Progression — GymPerformance" },
      { name: "description", content: "Personal-best progression for this lift." },
    ],
  }),
  component: ProgressionScreen,
});

function ProgressionScreen() {
  const auth = useAuth();
  return (
    <AppShell>
      <div className="mb-4">
        <Link
          to="/"
          className="text-sm font-medium text-primary hover:underline"
        >
          ← Back to the Board
        </Link>
      </div>
      <AuthGate
        status={auth.status}
        error={auth.error}
        onRetry={() => void auth.refresh()}
      >
        <ProgressionContent />
      </AuthGate>
    </AppShell>
  );
}

function ProgressionContent() {
  const { supabase, session } = useAuth();
  const { exerciseId } = Route.useParams();
  const tokenTag = session?.token?.slice(-8) ?? "anon";

  const exerciseQuery = useQuery({
    queryKey: ["exercise", exerciseId],
    queryFn: () => {
      if (!supabase) throw new Error("Not signed in");
      return fetchExercise(supabase, exerciseId);
    },
    enabled: !!supabase,
  });

  const measurement = exerciseQuery.data?.measurement_type;

  const historyQuery = useQuery({
    queryKey: ["pb-history", exerciseId, tokenTag],
    queryFn: () => {
      if (!supabase) throw new Error("Not signed in");
      return fetchExerciseHistory(supabase, exerciseId, measurement);
    },
    enabled: !!supabase && !!exerciseQuery.data,
  });

  if (exerciseQuery.isLoading || historyQuery.isLoading) {
    return <SkeletonProgression />;
  }
  if (exerciseQuery.isError || historyQuery.isError) {
    const err = (exerciseQuery.error ?? historyQuery.error) as Error;
    return (
      <div className="rounded-[16px] bg-card p-4">
        <div className="text-sm font-semibold text-foreground">
          Couldn't load progression
        </div>
        <p className="mt-1 text-xs text-muted-foreground">{err?.message}</p>
      </div>
    );
  }

  const exercise = exerciseQuery.data;
  if (!exercise) {
    return (
      <div className="rounded-[16px] bg-card p-4 text-sm text-muted-foreground">
        Exercise not found.
      </div>
    );
  }

  const history = historyQuery.data ?? [];
  const current = history.find((h) => h.is_current) ?? null;

  return (
    <div className="space-y-8">
      <CurrentPBHero exercise={exercise} pb={current} />
      <ProgressionChart exercise={exercise} history={history} />
      <HistoryList exercise={exercise} history={history} />
    </div>
  );
}

function CurrentPBHero({
  exercise,
  pb,
}: {
  exercise: ExerciseRow;
  pb: PersonalBestHistoryRow | null;
}) {
  const measurement = exercise.measurement_type ?? "";
  return (
    <div>
      <div className="text-xs font-semibold uppercase tracking-[0.08em] text-muted-foreground">
        {exercise.name}
      </div>
      {pb ? (
        <>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="font-numeric text-6xl font-semibold leading-none tabular-nums text-primary">
              {formatPBValue(pb.value, measurement).primary}
            </span>
            {formatPBValue(pb.value, measurement).unit && (
              <span className="text-2xl font-semibold text-primary/80">
                {formatPBValue(pb.value, measurement).unit}
              </span>
            )}
          </div>
          {pb.achieved_at && (
            <div className="mt-2 text-xs text-muted-foreground">
              Set on{" "}
              {new Date(pb.achieved_at).toLocaleDateString(undefined, {
                day: "numeric",
                month: "short",
                year: "numeric",
              })}
            </div>
          )}
        </>
      ) : (
        <div className="mt-3 rounded-[16px] bg-card p-4">
          <div className="text-sm font-semibold text-foreground">
            No current PB
          </div>
          <p className="mt-1 text-xs text-muted-foreground">
            Log a set for this exercise to establish your first PB.
          </p>
        </div>
      )}
    </div>
  );
}

function ProgressionChart({
  exercise,
  history,
}: {
  exercise: ExerciseRow;
  history: PersonalBestHistoryRow[];
}) {
  const measurement = exercise.measurement_type ?? "";
  const points = history
    .filter((h) => h.achieved_at && Number.isFinite(h.value))
    .map((h) => ({
      t: new Date(h.achieved_at as string).getTime(),
      value: h.value,
      label: new Date(h.achieved_at as string).toLocaleDateString(undefined, {
        day: "numeric",
        month: "short",
        year: "2-digit",
      }),
    }));

  return (
    <div>
      <SectionHeader title="Progression" caption={`${points.length} record${points.length === 1 ? "" : "s"}`} />
      <div className="rounded-[16px] bg-card p-4">
        {points.length === 0 ? (
          <p className="py-8 text-center text-xs text-muted-foreground">
            No history to chart yet.
          </p>
        ) : (
          <div className="h-64 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={points} margin={{ top: 8, right: 12, bottom: 8, left: 0 }}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                <XAxis
                  dataKey="label"
                  tick={{ fontSize: 11, fill: "var(--muted-foreground)" }}
                  axisLine={{ stroke: "var(--border)" }}
                  tickLine={{ stroke: "var(--border)" }}
                />
                <YAxis
                  tick={{ fontSize: 11, fill: "var(--muted-foreground)" }}
                  axisLine={{ stroke: "var(--border)" }}
                  tickLine={{ stroke: "var(--border)" }}
                  tickFormatter={(v: number) => formatPBValue(v, measurement).primary}
                  width={44}
                />
                <Tooltip
                  contentStyle={{
                    background: "var(--card)",
                    border: "1px solid var(--border)",
                    borderRadius: 12,
                    fontSize: 12,
                  }}
                  labelStyle={{ color: "var(--muted-foreground)" }}
                  formatter={(v: number) => {
                    const f = formatPBValue(v, measurement);
                    return [`${f.primary}${f.unit ? " " + f.unit : ""}`, "PB"];
                  }}
                />
                <Line
                  type="monotone"
                  dataKey="value"
                  stroke="var(--primary)"
                  strokeWidth={2}
                  dot={{ r: 4, fill: "var(--primary)", stroke: "var(--primary)" }}
                  activeDot={{ r: 6, fill: "var(--primary)" }}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        )}
      </div>
    </div>
  );
}

function HistoryList({
  exercise,
  history,
}: {
  exercise: ExerciseRow;
  history: PersonalBestHistoryRow[];
}) {
  const measurement = exercise.measurement_type ?? "";
  const rows = [...history].sort((a, b) => {
    const ta = a.achieved_at ? new Date(a.achieved_at).getTime() : 0;
    const tb = b.achieved_at ? new Date(b.achieved_at).getTime() : 0;
    return tb - ta;
  });

  return (
    <div>
      <SectionHeader title="History" caption={`${rows.length} record${rows.length === 1 ? "" : "s"}`} />
      {rows.length === 0 ? (
        <div className="rounded-[16px] bg-card p-4 text-sm text-muted-foreground">
          No history yet.
        </div>
      ) : (
        <ul className="overflow-hidden rounded-[16px] bg-card">
          {rows.map((row) => {
            const f = formatPBValue(row.value, measurement);
            return (
              <li
                key={row.id}
                className={
                  "flex items-center justify-between gap-3 border-b border-border/50 px-4 py-3 last:border-0 " +
                  (row.was_reset ? "bg-muted/40" : "")
                }
              >
                <div className="min-w-0">
                  <div className="font-numeric text-base font-semibold tabular-nums text-foreground">
                    {f.primary}
                    {f.unit && (
                      <span className="ml-1 text-sm font-medium text-muted-foreground">
                        {f.unit}
                      </span>
                    )}
                  </div>
                  <div className="mt-0.5 text-xs text-muted-foreground">
                    {row.achieved_at
                      ? new Date(row.achieved_at).toLocaleDateString(undefined, {
                          day: "numeric",
                          month: "short",
                          year: "numeric",
                        })
                      : "—"}
                  </div>
                </div>
                <div className="flex shrink-0 items-center gap-2">
                  {row.is_current && (
                    <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-primary">
                      Current
                    </span>
                  )}
                  {row.was_reset && (
                    <span className="rounded-full bg-muted px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
                      Reset
                    </span>
                  )}
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

function SkeletonProgression() {
  return (
    <div className="space-y-8">
      <div className="h-20 animate-pulse rounded-[16px] bg-card" aria-hidden />
      <div className="h-64 animate-pulse rounded-[16px] bg-card" aria-hidden />
      <div className="h-48 animate-pulse rounded-[16px] bg-card" aria-hidden />
    </div>
  );
}