import { useEffect, useState } from "react";
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { Ellipsis, Trash2, Trophy } from "lucide-react";
import { AppShell, AuthGate, SectionHeader } from "@/components/gp/app-shell";
import { FormField } from "@/components/gp/form-field";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { useAuth } from "@/lib/gp/auth-provider";
import {
  currentPBEmptyReason,
  progressionEmptyDetail,
  progressionEmptyTitle,
} from "@/lib/gp/current-pb-empty-copy";
import { shouldShowLifetimePB } from "@gp-shared/pb-derivation.ts";
import type { PBRule, SetState } from "@gp-shared/pb-evaluation.ts";
import {
  fetchExercise,
  fetchMergedProgression,
  deleteHistoryEntry,
  type DerivedPBDisplay,
  type ProgressionEntryRow,
  type ExerciseRow,
  type MergedProgressionData,
} from "@/lib/gp/queries";
import { fieldsForMeasurement, formatPBValue, combineMmSs, fieldLabel, fieldUnit, isCableRow } from "@/lib/gp/format";
import {
  addManualPB,
  resetCurrentPB,
  type AddManualPBResult,
} from "@/lib/gp/pb-actions";
import { todayISO } from "@/lib/gp/log-set";
import { cn } from "@/lib/utils";
import { MmSsFields } from "@/components/gp/mm-ss-fields";

const progressionSearchSchema = z.object({
  manual: z.boolean().optional(),
});

export const Route = createFileRoute("/progression/$exerciseId")({
  validateSearch: progressionSearchSchema,
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
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const { exerciseId } = Route.useParams();
  const { manual } = Route.useSearch();
  const tokenTag = session?.token?.slice(-8) ?? "anon";

  const [manualOpen, setManualOpen] = useState(!!manual);
  const [resetOpen, setResetOpen] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [pendingDelete, setPendingDelete] = useState<ProgressionEntryRow | null>(null);
  const [deleteMessage, setDeleteMessage] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);
  const [acting, setActing] = useState(false);
  const [celebrate, setCelebrate] = useState(false);

  const exerciseQuery = useQuery({
    queryKey: ["exercise", exerciseId],
    queryFn: () => {
      if (!supabase) throw new Error("Not signed in");
      return fetchExercise(supabase, exerciseId);
    },
    enabled: !!supabase,
  });

  const historyQuery = useQuery({
    queryKey: ["pb-history", exerciseId, tokenTag],
    queryFn: () => {
      if (!supabase || !exerciseQuery.data) throw new Error("Not signed in");
      return fetchMergedProgression(supabase, exerciseId, exerciseQuery.data);
    },
    enabled: !!supabase && !!exerciseQuery.data && !manual,
  });

  const handleManualOpenChange = (open: boolean) => {
    setManualOpen(open);
    if (!open && manual) {
      void navigate({ to: "/" });
    }
  };

  const refreshProgression = async () => {
    await queryClient.invalidateQueries({ queryKey: ["pb-history", exerciseId] });
    await queryClient.invalidateQueries({ queryKey: ["board"] });
  };

  useEffect(() => {
    if (!celebrate) return;
    const timer = window.setTimeout(() => setCelebrate(false), 4000);
    return () => window.clearTimeout(timer);
  }, [celebrate]);

  if (exerciseQuery.isLoading || (!manual && historyQuery.isLoading)) {
    return <SkeletonProgression />;
  }
  if (exerciseQuery.isError || (!manual && historyQuery.isError)) {
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

  const history = historyQuery.data?.entries ?? [];
  const current = historyQuery.data?.currentPB ?? null;
  const lifetimePB = historyQuery.data?.lifetimePB ?? null;
  const staleness = historyQuery.data?.staleness ?? { enabled: false, periods: 2, unit: "quarters" as const };
  const resetAt = historyQuery.data?.resetAt ?? null;
  const hasHistory =
    history.some((entry) => !entry.isResetMarker) ||
    lifetimePB != null ||
    current != null;
  const emptyReason = currentPBEmptyReason({
    hasHistory,
    hasActiveReset: resetAt != null,
    stalenessEnabled: staleness.enabled,
  });

  if (manual) {
    return (
      <div className="space-y-4">
        <h2 className="text-xl font-semibold tracking-tight text-foreground">
          {exercise.name}
        </h2>
        <ManualPBSheet
          open={manualOpen}
          onOpenChange={handleManualOpenChange}
          exercise={exercise}
          current={current}
          token={session?.token ?? null}
          onSaved={async (result) => {
            await refreshProgression();
            const data = queryClient.getQueryData<MergedProgressionData>([
              "pb-history",
              exerciseId,
              tokenTag,
            ]);
            if (
              result.isNewPB &&
              result.personalBest &&
              data?.currentPB?.id === result.personalBest.id
            ) {
              setCelebrate(true);
            }
          }}
        />
      </div>
    );
  }

  const openDeleteDialog = (row: ProgressionEntryRow) => {
    setPendingDelete(row);
    setDeleteMessage(
      deleteConfirmationMessage(row, history, current),
    );
    setDeleteOpen(true);
  };

  const handleReset = async () => {
    if (!session?.token) return;
    setActing(true);
    setActionError(null);
    try {
      await resetCurrentPB(session.token, exerciseId);
      setResetOpen(false);
      await refreshProgression();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : String(e));
    } finally {
      setActing(false);
    }
  };

  const handleDelete = async () => {
    if (!session?.token || !pendingDelete || !supabase) return;
    setActing(true);
    setActionError(null);
    try {
      await deleteHistoryEntry(supabase, {
        exerciseId,
        personalBestId: pendingDelete.personalBestId ?? undefined,
        setId: pendingDelete.setId ?? undefined,
        token: session.token,
      });
      setDeleteOpen(false);
      setPendingDelete(null);
      await refreshProgression();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : String(e));
    } finally {
      setActing(false);
    }
  };

  return (
    <div className="space-y-8">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <CurrentPBHero
            exercise={exercise}
            currentPB={current}
            lifetimePB={lifetimePB}
            showLifetime={shouldShowLifetimeForExercise(
              exercise.pb_rule,
              current,
              lifetimePB,
            )}
            emptyReason={emptyReason}
            celebrate={celebrate}
          />
        </div>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              type="button"
              aria-label="Progression actions"
              className="inline-flex size-9 shrink-0 items-center justify-center rounded-full text-primary hover:bg-primary/10"
            >
              <Ellipsis className="size-5" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-52">
            <DropdownMenuItem onSelect={() => setManualOpen(true)}>
              Add PB manually
            </DropdownMenuItem>
            {current && (
              <DropdownMenuItem
                className="text-destructive focus:text-destructive"
                onSelect={() => setResetOpen(true)}
              >
                Reset current PB
              </DropdownMenuItem>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      {actionError && (
        <div className="rounded-[16px] bg-card p-4">
          <div className="text-sm font-semibold text-destructive">Action failed</div>
          <p className="mt-1 text-xs text-muted-foreground">{actionError}</p>
        </div>
      )}

      <ProgressionChart exercise={exercise} history={history} />
      <HistoryList
        exercise={exercise}
        history={history}
        onDelete={openDeleteDialog}
      />

      <ManualPBSheet
        open={manualOpen}
        onOpenChange={setManualOpen}
        exercise={exercise}
        current={current}
        token={session?.token ?? null}
        onSaved={async (result) => {
          await refreshProgression();
          const data = queryClient.getQueryData<MergedProgressionData>([
            "pb-history",
            exerciseId,
            tokenTag,
          ]);
          if (
            result.isNewPB &&
            result.personalBest &&
            data?.currentPB?.id === result.personalBest.id
          ) {
            setCelebrate(true);
          }
        }}
      />

      <AlertDialog open={resetOpen} onOpenChange={setResetOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Reset personal best?</AlertDialogTitle>
            <AlertDialogDescription>
              This will clear your current {exercise.name} PB. Your board will
              show no current PB until you log a new one. Your history will be
              preserved.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={acting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              disabled={acting}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
              onClick={(e) => {
                e.preventDefault();
                void handleReset();
              }}
            >
              {acting ? "Resetting…" : "Reset"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog
        open={deleteOpen}
        onOpenChange={(open) => {
          setDeleteOpen(open);
          if (!open) setPendingDelete(null);
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete this entry?</AlertDialogTitle>
            <AlertDialogDescription>{deleteMessage}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={acting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              disabled={acting}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
              onClick={(e) => {
                e.preventDefault();
                void handleDelete();
              }}
            >
              {acting ? "Deleting…" : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

function displayToSetState(pb: DerivedPBDisplay): SetState {
  const raw = pb.raw;
  const num = (key: string): number | null =>
    typeof raw[key] === "number" && Number.isFinite(raw[key] as number)
      ? (raw[key] as number)
      : null;
  return {
    weight: num("weight"),
    reps: pb.reps,
    time: num("time") ?? num("time_seconds"),
    distance: num("distance"),
  };
}

function shouldShowLifetimeForExercise(
  pbRule: string | null | undefined,
  current: DerivedPBDisplay | null,
  lifetime: DerivedPBDisplay | null,
): boolean {
  if (!pbRule) return false;
  return shouldShowLifetimePB(
    lifetime ? displayToSetState(lifetime) : null,
    current ? displayToSetState(current) : null,
    pbRule as PBRule,
  );
}

function formatExercisePB(
  value: number,
  measurement: string,
  exercise: { name: string },
  reps?: number | null,
): { primary: string; unit: string } {
  return formatPBValue(value, measurement, {
    exerciseName: exercise.name,
    reps,
  });
}

function CurrentPBHero({
  exercise,
  currentPB,
  lifetimePB,
  showLifetime,
  emptyReason,
  celebrate,
}: {
  exercise: ExerciseRow;
  currentPB: DerivedPBDisplay | null;
  lifetimePB: DerivedPBDisplay | null;
  showLifetime: boolean;
  emptyReason: ReturnType<typeof currentPBEmptyReason>;
  celebrate: boolean;
}) {
  const measurement = exercise.measurement_type ?? "";
  const currentFormatted = currentPB
    ? formatExercisePB(currentPB.value, measurement, exercise, currentPB.reps)
    : null;
  const lifetimeFormatted =
    showLifetime && lifetimePB
      ? formatExercisePB(lifetimePB.value, measurement, exercise, lifetimePB.reps)
      : null;

  return (
    <div
      className={cn(
        celebrate && currentPB && "rounded-[16px] p-4 pb-ring transition-shadow",
      )}
    >
      <div className="flex items-center gap-2">
        <div className="text-xs font-semibold uppercase tracking-[0.08em] text-muted-foreground">
          {exercise.name}
        </div>
        {celebrate && currentPB && (
          <span className="inline-flex items-center gap-1 rounded-full bg-pb-badge px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-pb-foreground">
            <Trophy className="size-3" strokeWidth={2.5} />
            New PB
          </span>
        )}
      </div>
      {currentPB && currentFormatted ? (
        <>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="font-numeric text-6xl font-semibold leading-none tabular-nums text-primary">
              {currentFormatted.primary}
            </span>
            {currentFormatted.unit && (
              <span className="text-2xl font-semibold text-primary/80">
                {currentFormatted.unit}
              </span>
            )}
          </div>
          {currentPB.achieved_at && (
            <div className="mt-2 text-xs text-muted-foreground">
              Set on{" "}
              {new Date(currentPB.achieved_at).toLocaleDateString(undefined, {
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
            {progressionEmptyTitle(emptyReason)}
          </div>
          {progressionEmptyDetail(emptyReason) && (
            <p className="mt-1 text-xs text-muted-foreground">
              {progressionEmptyDetail(emptyReason)}
            </p>
          )}
        </div>
      )}
      {showLifetime && (
        <div className="mt-4 rounded-[16px] bg-card p-4">
          <div className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            Lifetime PB
          </div>
          {lifetimePB && lifetimeFormatted ? (
            <>
              <div className="mt-1 flex items-baseline gap-2">
                <span className="font-numeric text-2xl font-semibold tabular-nums text-foreground">
                  {lifetimeFormatted.primary}
                </span>
                {lifetimeFormatted.unit && (
                  <span className="text-sm font-semibold text-muted-foreground">
                    {lifetimeFormatted.unit}
                  </span>
                )}
              </div>
              {lifetimePB.achieved_at ? (
                <div className="mt-1 text-xs text-muted-foreground">
                  Set on{" "}
                  {new Date(lifetimePB.achieved_at).toLocaleDateString(undefined, {
                    day: "numeric",
                    month: "short",
                    year: "numeric",
                  })}
                </div>
              ) : (
                <div className="mt-1 text-xs text-muted-foreground">Undated</div>
              )}
            </>
          ) : (
            <div className="mt-1 font-numeric text-2xl font-semibold text-muted-foreground">
              No lifetime PB
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function ManualPBSheet({
  open,
  onOpenChange,
  exercise,
  current,
  token,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  exercise: ExerciseRow;
  current: DerivedPBDisplay | null;
  token: string | null;
  onSaved: (result: AddManualPBResult) => Promise<void>;
}) {
  const measurement = exercise.measurement_type ?? "";
  const fields = fieldsForMeasurement(measurement);
  const useMmSs = measurement === "timeOnly";
  const [includeDate, setIncludeDate] = useState(false);
  const [achievedAt, setAchievedAt] = useState(todayISO());
  const [values, setValues] = useState<Record<string, string>>({});
  const [feedback, setFeedback] = useState<
    { type: "success" } | { type: "notPB"; current: string } | { type: "error"; message: string } | null
  >(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    setIncludeDate(false);
    setAchievedAt(todayISO());
    setValues({});
    setFeedback(null);
  }, [open]);

  const canSave = useMmSs
    ? values.mm?.trim() !== "" || values.ss?.trim() !== ""
    : fields.every((f) => values[f]?.trim());

  const save = async () => {
    if (!token) return;
    const payload = parseMeasurementForm(measurement, values);
    if (!payload) {
      setFeedback({
        type: "error",
        message: "Enter all required values before saving.",
      });
      return;
    }
    if (includeDate && achievedAt > todayISO()) {
      setFeedback({ type: "error", message: "Date cannot be in the future." });
      return;
    }

    setSaving(true);
    setFeedback(null);
    try {
      const result = await addManualPB(token, {
        exerciseId: exercise.id,
        achievedAt: includeDate ? achievedAt : null,
        ...payload,
      });

      if (result.isNewPB) {
        setFeedback({ type: "success" });
        await onSaved(result);
        window.setTimeout(() => onOpenChange(false), 800);
      } else {
        const currentFormatted = current
          ? formatExercisePB(current.value, measurement, exercise, current.reps)
          : null;
        const currentLabel = currentFormatted
          ? currentFormatted.primary +
            (currentFormatted.unit ? ` ${currentFormatted.unit}` : "")
          : "none";
        setFeedback({ type: "notPB", current: currentLabel });
        await onSaved(result);
      }
    } catch (e) {
      setFeedback({
        type: "error",
        message: e instanceof Error ? e.message : String(e),
      });
    } finally {
      setSaving(false);
    }
  };

  const currentFormatted = current
    ? formatExercisePB(current.value, measurement, exercise, current.reps)
    : null;

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="max-h-[90vh] overflow-y-auto rounded-t-[20px]">
        <SheetHeader>
          <SheetTitle>Add PB manually</SheetTitle>
        </SheetHeader>
        <div className="mt-6 space-y-6">
          <div>
            <div className="text-sm font-semibold text-foreground">{exercise.name}</div>
            {current && currentFormatted ? (
              <div className="mt-2">
                <div className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  Current PB
                </div>
                <div className="mt-1 font-numeric text-2xl font-semibold text-primary">
                  {currentFormatted.primary}
                  {currentFormatted.unit && (
                    <span className="ml-1 text-base text-primary/80">
                      {currentFormatted.unit}
                    </span>
                  )}
                </div>
              </div>
            ) : (
              <p className="mt-2 text-xs text-muted-foreground">No current PB</p>
            )}
          </div>

          <div className="space-y-3">
            <label className="flex items-center justify-between gap-3 text-sm font-medium text-foreground">
              Include date
              <input
                type="checkbox"
                checked={includeDate}
                onChange={(e) => setIncludeDate(e.target.checked)}
                className="size-4 accent-primary"
              />
            </label>
            {includeDate ? (
              <FormField
                label="Date"
                type="date"
                max={todayISO()}
                value={achievedAt}
                onChange={(e) => setAchievedAt(e.target.value)}
              />
            ) : (
              <p className="text-xs text-muted-foreground">
                Leave the date off if you only remember the value. It counts
                toward your lifetime best, not your current PB.
              </p>
            )}
          </div>

          <div className="rounded-[16px] bg-card p-4 space-y-3">
            <div className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              New PB
            </div>
            {useMmSs ? (
              <MmSsFields
                idPrefix="manual-pb"
                mm={values.mm ?? ""}
                ss={values.ss ?? ""}
                onChange={(part, v) =>
                  setValues((prev) => ({ ...prev, [part]: v }))
                }
              />
            ) : (
              <div className="grid gap-3 sm:grid-cols-2">
                {fields.map((f) => (
                  <FormField
                    key={f}
                    label={fieldLabel(f, measurement, exercise.name)}
                    numeric
                    inputMode={
                      f === "reps" || isCableRow(exercise.name)
                        ? "numeric"
                        : "decimal"
                    }
                    value={values[f] ?? ""}
                    onChange={(e) =>
                      setValues((prev) => ({ ...prev, [f]: e.target.value }))
                    }
                    trailing={
                      fieldUnit(f, measurement, exercise.name) || undefined
                    }
                  />
                ))}
              </div>
            )}
          </div>

          {feedback?.type === "success" && (
            <div className="rounded-[16px] bg-card p-4 text-sm font-medium text-green-600">
              New PB saved
            </div>
          )}
          {feedback?.type === "notPB" && (
            <div className="rounded-[16px] bg-card p-4 text-sm text-muted-foreground">
              This doesn't beat your current PB of {feedback.current}. Not saved.
            </div>
          )}
          {feedback?.type === "error" && (
            <div className="rounded-[16px] bg-card p-4 text-sm text-destructive">
              {feedback.message}
            </div>
          )}

          <Button type="button" disabled={!canSave || saving} onClick={() => void save()}>
            {saving ? "Saving…" : "Save PB"}
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}

function ProgressionChart({
  exercise,
  history,
}: {
  exercise: ExerciseRow;
  history: ProgressionEntryRow[];
}) {
  const measurement = exercise.measurement_type ?? "";
  const points = history
    .filter((h) => h.date && Number.isFinite(h.chartValue))
    .map((h) => ({
      t: new Date(h.date).getTime(),
      value: h.chartValue,
      label: new Date(h.date).toLocaleDateString(undefined, {
        day: "numeric",
        month: "short",
        year: "2-digit",
      }),
      isPB: h.isPB,
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
                  tickFormatter={(v: number) =>
                    formatExercisePB(v, measurement, exercise).primary
                  }
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
                    const f = formatExercisePB(v, measurement, exercise);
                    return [`${f.primary}${f.unit ? " " + f.unit : ""}`, "PB"];
                  }}
                />
                <Line
                  type="monotone"
                  dataKey="value"
                  stroke="var(--primary)"
                  strokeWidth={2}
                  dot={(props) => {
                    const { cx, cy, payload } = props as {
                      cx?: number;
                      cy?: number;
                      payload?: { isPB?: boolean };
                    };
                    if (cx == null || cy == null) return <g />;
                    const isPb = payload?.isPB ?? false;
                    return (
                      <circle
                        cx={cx}
                        cy={cy}
                        r={isPb ? 5 : 3}
                        fill={isPb ? "var(--pb)" : "var(--primary)"}
                        stroke={isPb ? "var(--pb)" : "var(--primary)"}
                        opacity={isPb ? 1 : 0.55}
                      />
                    );
                  }}
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
  onDelete,
}: {
  exercise: ExerciseRow;
  history: ProgressionEntryRow[];
  onDelete: (row: ProgressionEntryRow) => void;
}) {
  const rows = [...history].sort((a, b) => {
    const ta = a.date ? new Date(a.date).getTime() : 0;
    const tb = b.date ? new Date(b.date).getTime() : 0;
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
          {rows.map((row) => (
              <li
                key={row.id}
                className={cn(
                  "flex items-stretch border-b border-border/50 last:border-0",
                  row.isResetMarker && "bg-muted/40",
                )}
              >
                {row.isPB && (
                  <div className="w-1 shrink-0 bg-pb" aria-hidden />
                )}
                <div className="flex min-w-0 flex-1 items-center justify-between gap-3 px-4 py-3">
                  <div className="min-w-0">
                    <div className="font-numeric text-base font-semibold tabular-nums text-foreground">
                      {row.isResetMarker ? "Current PB reset" : row.formattedValue}
                    </div>
                    <div className="mt-0.5 text-xs text-muted-foreground">
                      {row.date
                        ? new Date(row.date).toLocaleDateString(undefined, {
                            day: "numeric",
                            month: "short",
                            year: "numeric",
                          })
                        : "—"}
                    </div>
                  </div>
                  <div className="flex shrink-0 items-center gap-2">
                    {row.isPB && (
                      <span className="rounded-full bg-pb-badge px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-pb-foreground">
                        PB
                      </span>
                    )}
                    {row.isResetMarker && (
                      <span className="rounded-full bg-muted px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
                        Reset
                      </span>
                    )}
                    {!row.isResetMarker && (
                      <button
                        type="button"
                        aria-label="Delete history entry"
                        onClick={() => onDelete(row)}
                        className="inline-flex size-8 items-center justify-center rounded-full text-muted-foreground hover:bg-muted hover:text-destructive"
                      >
                        <Trash2 className="size-4" />
                      </button>
                    )}
                  </div>
                </div>
              </li>
            ))}
        </ul>
      )}
    </div>
  );
}

function deleteConfirmationMessage(
  row: ProgressionEntryRow,
  history: ProgressionEntryRow[],
  current: DerivedPBDisplay | null,
): string {
  const removesCurrent =
    current != null &&
    (row.personalBestId === current.id ||
      (row.setId != null && row.setId === current.set_id) ||
      (row.setId != null && row.setId === current.id));

  if (!removesCurrent) {
    return "This cannot be undone.";
  }

  const otherCandidates = history.filter((h) => h.id !== row.id && h.isPB);

  if (otherCandidates.length === 0) {
    return "Your board will show no current PB until you log a new one.";
  }

  return "Your current PB may revert to another record in your history, or your board may show no current PB.";
}

function parseMeasurementForm(
  measurementType: string,
  values: Record<string, string>,
): {
  weight?: number;
  reps?: number;
  time_seconds?: number;
  distance?: number;
} | null {
  if (measurementType === "timeOnly") {
    const total = combineMmSs(values.mm, values.ss);
    if (total == null) return null;
    return { time_seconds: total };
  }

  const fields = fieldsForMeasurement(measurementType);
  const payload: {
    weight?: number;
    reps?: number;
    time_seconds?: number;
    distance?: number;
  } = {};

  for (const field of fields) {
    const raw = values[field]?.trim();
    if (!raw) return null;
    const parsed = Number(raw);
    if (!Number.isFinite(parsed)) return null;
    if (field === "time") payload.time_seconds = parsed;
    else if (field === "weight") payload.weight = parsed;
    else if (field === "reps") payload.reps = parsed;
    else if (field === "distance") payload.distance = parsed;
  }

  return payload;
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
