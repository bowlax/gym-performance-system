import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Plus, ChevronLeft, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { FormField } from "@/components/gp/form-field";
import { MmSsFields } from "@/components/gp/mm-ss-fields";
import {
  AppShell,
  AuthGate,
  SectionHeader,
} from "@/components/gp/app-shell";
import { useAuth } from "@/lib/gp/auth-provider";
import {
  fetchExercises,
  fetchSessionHistory,
  fetchSessionDetail,
  type ExerciseRow,
  type SessionListRow,
  type SessionEntryRow,
  type SessionSetRow,
} from "@/lib/gp/queries";
import {
  combineMmSs,
  fieldLabel,
  fieldUnit,
  fieldsForMeasurement,
  formatSetValues,
  isCableRow,
} from "@/lib/gp/format";
import { logSession, todayISO } from "@/lib/gp/log-set";
import {
  stashSessionSaveSummary,
  type SessionSaveSummary,
} from "@/lib/gp/session-save-summary";

export const Route = createFileRoute("/log")({
  head: () => ({
    meta: [
      { title: "Log a session — GymPerformance" },
      {
        name: "description",
        content: "Log a training session with date, notes, calories, and sets.",
      },
      { property: "og:title", content: "Log a session — GymPerformance" },
      {
        property: "og:description",
        content: "Log a training session with date, notes, calories, and sets.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: LogScreen,
});

function LogScreen() {
  const auth = useAuth();
  const navigate = useNavigate();
  const [view, setView] = useState<"form" | "history">("form");
  return (
    <AppShell>
      <div className="mb-4 flex items-center justify-between">
        {view === "form" ? (
          <>
            <button
              type="button"
              onClick={() => void navigate({ to: "/" })}
              className="text-sm font-medium text-primary"
            >
              Cancel
            </button>
            <h1 className="text-base font-semibold text-foreground">
              Log a session
            </h1>
            <button
              type="button"
              onClick={() => setView("history")}
              className="text-sm font-medium text-primary"
            >
              History
            </button>
          </>
        ) : (
          <>
            <button
              type="button"
              onClick={() => setView("form")}
              className="inline-flex items-center gap-1 text-sm font-medium text-primary"
            >
              <ChevronLeft className="size-4" />
              Back
            </button>
            <h1 className="text-base font-semibold text-foreground">
              Session history
            </h1>
            <span className="w-12" aria-hidden />
          </>
        )}
      </div>
      <AuthGate
        status={auth.status}
        error={auth.error}
        onRetry={() => void auth.refresh()}
      >
        {view === "form" ? <LogSessionForm /> : <SessionHistorySection />}
      </AuthGate>
    </AppShell>
  );
}

type PerExerciseValues = Record<string, Record<string, string>>;

function LogSessionForm() {
  const { supabase, session } = useAuth();
  const queryClient = useQueryClient();
  const navigate = useNavigate();

  const exercisesQuery = useQuery({
    queryKey: ["exercises", session?.token?.slice(-8) ?? "anon"],
    queryFn: () => {
      if (!supabase) throw new Error("Not signed in");
      return fetchExercises(supabase);
    },
    enabled: !!supabase,
  });

  const [sessionDate, setSessionDate] = useState<string>(todayISO());
  const [notes, setNotes] = useState<string>("");
  const [calories, setCalories] = useState<string>("");
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [values, setValues] = useState<PerExerciseValues>({});
  const [pickerOpen, setPickerOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const exercises = exercisesQuery.data ?? [];
  const selectedExercises = useMemo(
    () =>
      selectedIds
        .map((id) => exercises.find((e) => e.id === id))
        .filter((x): x is ExerciseRow => Boolean(x)),
    [selectedIds, exercises],
  );

  function removeExercise(id: string) {
    setSelectedIds((prev) => prev.filter((x) => x !== id));
    setValues((prev) => {
      const next = { ...prev };
      delete next[id];
      return next;
    });
  }

  function onPickerDone(ids: string[]) {
    setSelectedIds((prev) => {
      const merged = [...prev];
      for (const id of ids) if (!merged.includes(id)) merged.push(id);
      return merged;
    });
    setPickerOpen(false);
  }

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!session) return;
    setError(null);
    setSubmitting(true);
    try {
      const caloriesTrimmed = calories.trim();
      let caloriesBurned: number | null = null;
      if (caloriesTrimmed !== "") {
        const n = Number(caloriesTrimmed);
        if (!Number.isFinite(n)) {
          throw new Error("Please enter a valid calories value.");
        }
        caloriesBurned = n;
      }

      const exercisesToLog: {
        exerciseId: string;
        weight?: number;
        reps?: number;
        time?: number;
        distance?: number;
      }[] = [];

      for (const ex of selectedExercises) {
        const fields = fieldsForMeasurement(ex.measurement_type);
        const entry: (typeof exercisesToLog)[number] = { exerciseId: ex.id };
        for (const f of fields) {
          if (f === "time" && ex.measurement_type === "timeOnly") {
            const total = combineMmSs(
              values[ex.id]?.mm,
              values[ex.id]?.ss,
            );
            if (total == null) {
              throw new Error(
                `Please enter a valid time (mm:ss) for ${ex.name}.`,
              );
            }
            entry.time = total;
            continue;
          }
          const raw = values[ex.id]?.[f];
          const n = raw == null || raw === "" ? NaN : Number(raw);
          if (!Number.isFinite(n)) {
            throw new Error(
              `Please enter a valid ${fieldLabel(f, ex.measurement_type, ex.name).toLowerCase()} for ${ex.name}.`,
            );
          }
          entry[f as keyof typeof entry] = n;
        }
        exercisesToLog.push(entry);
      }

      if (exercisesToLog.length === 0) {
        throw new Error("Add at least one exercise before saving.");
      }

      const sessionResult = await logSession(session.token, {
        sessionDate,
        notes: notes.trim() === "" ? null : notes.trim(),
        calories_burned: caloriesBurned,
        exercises: exercisesToLog,
      });

      const saveSummary: SessionSaveSummary = {
        items: sessionResult.results.map(({ exerciseId, result }) => {
          const exercise = selectedExercises.find((e) => e.id === exerciseId);
          return {
            exerciseId,
            exerciseName: exercise?.name ?? "Exercise",
            isPersonalBest: result.isPersonalBest,
          };
        }),
      };

      stashSessionSaveSummary(saveSummary);

      await queryClient.invalidateQueries({ queryKey: ["board"] });
      await queryClient.invalidateQueries({ queryKey: ["personal-bests"] });
      await queryClient.invalidateQueries({ queryKey: ["session-history"] });
      await queryClient.invalidateQueries({ queryKey: ["sessions"] });

      void navigate({
        to: "/",
        state: { sessionSaveSummary: saveSummary },
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setSubmitting(false);
    }
  }

  if (pickerOpen) {
    return (
      <ExercisePicker
        exercises={exercises}
        loading={exercisesQuery.isLoading}
        error={
          exercisesQuery.isError
            ? (exercisesQuery.error as Error).message
            : null
        }
        alreadySelected={selectedIds}
        onCancel={() => setPickerOpen(false)}
        onDone={onPickerDone}
      />
    );
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <div className="rounded-[16px] bg-card p-4 space-y-3">
        <FormField
          label="Date"
          type="date"
          value={sessionDate}
          onChange={(e) => setSessionDate(e.target.value)}
        />
        <div className="flex flex-col gap-1.5">
          <label
            htmlFor="notes"
            className="text-sm font-medium text-foreground"
          >
            Notes <span className="text-muted-foreground">(optional)</span>
          </label>
          <textarea
            id="notes"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="How did the session feel?"
            rows={3}
            className="rounded-[10px] border border-input bg-surface px-3.5 py-3 text-base text-foreground outline-none placeholder:text-muted-foreground focus:border-primary focus:ring-4 focus:ring-primary/15 transition-shadow resize-none"
          />
        </div>
        <FormField
          label="Calories"
          numeric
          inputMode="numeric"
          value={calories}
          onChange={(e) => setCalories(e.target.value)}
          placeholder="0"
          trailing="kcal"
        />
      </div>

      <div className="rounded-[16px] bg-card p-4">
        <SectionHeader title="Exercises" />
        {selectedExercises.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No exercise is added. To add exercise, log your sets for the board
            or save this session as an attendance record.
          </p>
        ) : (
          <div className="space-y-4">
            {selectedExercises.map((ex) => (
              <ExerciseEntry
                key={ex.id}
                exercise={ex}
                values={values[ex.id] ?? {}}
                onChange={(field, v) =>
                  setValues((prev) => ({
                    ...prev,
                    [ex.id]: { ...(prev[ex.id] ?? {}), [field]: v },
                  }))
                }
                onRemove={() => removeExercise(ex.id)}
              />
            ))}
          </div>
        )}
        <button
          type="button"
          onClick={() => setPickerOpen(true)}
          className="mt-4 flex items-center gap-3 text-sm font-medium text-foreground"
        >
          <span className="inline-flex size-7 items-center justify-center rounded-full bg-primary text-primary-foreground">
            <Plus className="size-4" strokeWidth={2.5} />
          </span>
          Add exercise
        </button>
      </div>

      {error && (
        <div className="rounded-[16px] bg-card p-4">
          <div className="text-sm font-semibold text-destructive">
            Couldn't save the session
          </div>
          <p className="mt-1 text-xs text-muted-foreground">{error}</p>
        </div>
      )}

      <Button type="submit" disabled={submitting}>
        {submitting ? "Saving…" : "Save session"}
      </Button>
    </form>
  );
}

function ExerciseEntry({
  exercise,
  values,
  onChange,
  onRemove,
}: {
  exercise: ExerciseRow;
  values: Record<string, string>;
  onChange: (field: string, value: string) => void;
  onRemove: () => void;
}) {
  const fields = fieldsForMeasurement(exercise.measurement_type);
  const useMmSs = exercise.measurement_type === "timeOnly";

  return (
    <div className="rounded-[12px] border border-border/60 p-3">
      <div className="mb-3 flex items-center justify-between">
        <div className="text-sm font-semibold text-foreground">
          {exercise.name}
        </div>
        <button
          type="button"
          onClick={onRemove}
          aria-label={`Remove ${exercise.name}`}
          className="inline-flex size-7 items-center justify-center rounded-full text-muted-foreground hover:bg-muted"
        >
          <X className="size-4" />
        </button>
      </div>
      {useMmSs ? (
        <MmSsFields
          idPrefix={`ex-${exercise.id}`}
          mm={values.mm ?? ""}
          ss={values.ss ?? ""}
          onChange={(part, v) => onChange(part, v)}
        />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {fields.map((f) => (
            <FormField
              key={f}
              label={fieldLabel(f, exercise.measurement_type, exercise.name)}
              numeric
              inputMode={
                f === "reps" || isCableRow(exercise.name)
                  ? "numeric"
                  : "decimal"
              }
              value={values[f] ?? ""}
              onChange={(e) => onChange(f, e.target.value)}
              trailing={
                fieldUnit(f, exercise.measurement_type, exercise.name) ||
                undefined
              }
            />
          ))}
        </div>
      )}
    </div>
  );
}

function ExercisePicker({
  exercises,
  loading,
  error,
  alreadySelected,
  onCancel,
  onDone,
}: {
  exercises: ExerciseRow[];
  loading: boolean;
  error: string | null;
  alreadySelected: string[];
  onCancel: () => void;
  onDone: (ids: string[]) => void;
}) {
  const [picked, setPicked] = useState<Set<string>>(new Set());
  function toggle(id: string) {
    setPicked((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }
  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <button
          type="button"
          onClick={onCancel}
          className="inline-flex items-center gap-1 text-sm font-medium text-primary"
        >
          <ChevronLeft className="size-4" />
          Back
        </button>
        <button
          type="button"
          onClick={() => onDone(Array.from(picked))}
          disabled={picked.size === 0}
          className="text-sm font-semibold text-primary disabled:text-muted-foreground"
        >
          Add ({picked.size})
        </button>
      </div>
      <div className="rounded-[16px] bg-card p-2">
        {loading && (
          <div className="h-40 animate-pulse rounded-[12px] bg-muted" />
        )}
        {error && (
          <p className="p-3 text-sm text-destructive">{error}</p>
        )}
        {!loading && !error && exercises.length === 0 && (
          <p className="p-3 text-sm text-muted-foreground">
            No exercises available.
          </p>
        )}
        {!loading && !error &&
          exercises.map((ex) => {
            const already = alreadySelected.includes(ex.id);
            const checked = picked.has(ex.id);
            return (
              <button
                key={ex.id}
                type="button"
                onClick={() => !already && toggle(ex.id)}
                disabled={already}
                className="flex w-full items-center justify-between rounded-[10px] px-3 py-3 text-left hover:bg-muted disabled:opacity-50"
              >
                <div>
                  <div className="text-sm font-medium text-foreground">
                    {ex.name}
                  </div>
                  <div className="text-xs text-muted-foreground">
                    {ex.measurement_type}
                  </div>
                </div>
                {already ? (
                  <span className="text-xs text-muted-foreground">Added</span>
                ) : (
                  <span
                    className={
                      "inline-flex size-5 items-center justify-center rounded-full border " +
                      (checked
                        ? "border-primary bg-primary text-primary-foreground"
                        : "border-border")
                    }
                  >
                    {checked && "✓"}
                  </span>
                )}
              </button>
            );
          })}
      </div>
    </div>
  );
}

function SessionHistorySection() {
  const { supabase, session } = useAuth();
  const [openId, setOpenId] = useState<string | null>(null);
  const tokenTag = session?.token?.slice(-8) ?? "anon";

  const listQuery = useQuery({
    queryKey: ["session-history", tokenTag],
    queryFn: () => {
      if (!supabase) throw new Error("Not signed in");
      return fetchSessionHistory(supabase);
    },
    enabled: !!supabase,
  });

  if (openId) {
    return (
      <SessionDetailView
        sessionId={openId}
        onBack={() => setOpenId(null)}
      />
    );
  }

  if (listQuery.isLoading) {
    return (
      <div className="rounded-[16px] bg-card p-4 text-sm text-muted-foreground">
        Loading sessions…
      </div>
    );
  }
  if (listQuery.isError) {
    return (
      <div className="rounded-[16px] bg-card p-4 text-sm text-destructive">
        Couldn’t load sessions: {(listQuery.error as Error).message}
      </div>
    );
  }

  const sessions = listQuery.data ?? [];
  if (sessions.length === 0) {
    return (
      <div className="rounded-[16px] bg-card p-6 text-center">
        <div className="text-sm font-medium text-foreground">
          No sessions yet
        </div>
        <p className="mt-1 text-xs text-muted-foreground">
          Log your first session to see it here.
        </p>
      </div>
    );
  }

  return (
    <div>
      <SectionHeader
        title="Session history"
        caption={`${sessions.length} ${sessions.length === 1 ? "session" : "sessions"}`}
      />
      <ul className="rounded-[16px] bg-card">
        {sessions.map((s, i) => (
          <li key={s.id}>
            <button
              type="button"
              onClick={() => setOpenId(s.id)}
              className={
                "flex w-full items-center justify-between px-4 py-3 text-left transition-colors hover:bg-muted/40 " +
                (i === 0 ? "rounded-t-[16px] " : "") +
                (i === sessions.length - 1
                  ? "rounded-b-[16px] "
                  : "border-b border-border/50 ")
              }
            >
              <SessionRowSummary s={s} />
              <ChevronLeft
                className="size-4 rotate-180 text-muted-foreground"
                aria-hidden
              />
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}

function SessionRowSummary({ s }: { s: SessionListRow }) {
  const detail: string[] = [];
  if (typeof s.calories_burned === "number") {
    detail.push(`${s.calories_burned} kcal`);
  }
  if (s.notes && s.notes.trim().length > 0) {
    detail.push(s.notes.trim());
  }
  return (
    <div className="min-w-0 flex-1 pr-3">
      <div className="text-sm font-medium text-foreground">
        {formatSessionDate(s.date)}
      </div>
      {detail.length > 0 && (
        <div className="mt-0.5 truncate text-xs text-muted-foreground">
          {detail.join(" · ")}
        </div>
      )}
    </div>
  );
}

function SessionDetailView({
  sessionId,
  onBack,
}: {
  sessionId: string;
  onBack: () => void;
}) {
  const { supabase, session } = useAuth();
  const tokenTag = session?.token?.slice(-8) ?? "anon";

  const detailQuery = useQuery({
    queryKey: ["session-detail", sessionId, tokenTag],
    queryFn: () => {
      if (!supabase) throw new Error("Not signed in");
      return fetchSessionDetail(supabase, sessionId);
    },
    enabled: !!supabase,
  });

  return (
    <div>
      <button
        type="button"
        onClick={onBack}
        className="mb-3 inline-flex items-center gap-1 text-sm font-medium text-primary"
      >
        <ChevronLeft className="size-4" />
        All sessions
      </button>

      {detailQuery.isLoading && (
        <div className="rounded-[16px] bg-card p-4 text-sm text-muted-foreground">
          Loading session…
        </div>
      )}
      {detailQuery.isError && (
        <div className="rounded-[16px] bg-card p-4 text-sm text-destructive">
          Couldn’t load session:{" "}
          {(detailQuery.error as Error).message}
        </div>
      )}
      {detailQuery.data === null && (
        <div className="rounded-[16px] bg-card p-6 text-center text-sm text-muted-foreground">
          Session not found.
        </div>
      )}
      {detailQuery.data && (
        <SessionDetailBody detail={detailQuery.data} />
      )}
    </div>
  );
}

function SessionDetailBody({
  detail,
}: {
  detail: { session: SessionListRow; entries: SessionEntryRow[] };
}) {
  const { session, entries } = detail;
  return (
    <div className="space-y-6">
      <div className="rounded-[16px] bg-card p-4">
        <div className="text-xs uppercase tracking-wide text-muted-foreground">
          Session
        </div>
        <div className="mt-1 text-lg font-semibold text-foreground">
          {formatSessionDate(session.date)}
        </div>
        {typeof session.calories_burned === "number" && (
          <div className="mt-2 text-sm text-muted-foreground">
            {session.calories_burned} kcal
          </div>
        )}
        {session.notes && session.notes.trim().length > 0 && (
          <div className="mt-2 whitespace-pre-wrap text-sm text-foreground">
            {session.notes.trim()}
          </div>
        )}
      </div>

      {entries.length === 0 ? (
        <div className="rounded-[16px] bg-card p-6 text-center text-sm text-muted-foreground">
          No exercises logged in this session.
        </div>
      ) : (
        <div className="space-y-4">
          {entries.map((entry) => (
            <SessionEntryCard key={entry.id} entry={entry} />
          ))}
        </div>
      )}
    </div>
  );
}

function SessionEntryCard({ entry }: { entry: SessionEntryRow }) {
  const name = entry.exercise?.name ?? "Exercise";
  const measurement = entry.exercise?.measurement_type ?? "";
  return (
    <div className="rounded-[16px] bg-card p-4 border-l-4 border-primary">
      <div className="text-sm font-semibold text-foreground">{name}</div>
      {entry.sets.length === 0 ? (
        <div className="mt-2 text-xs text-muted-foreground">
          No sets recorded.
        </div>
      ) : (
        <ol className="mt-2 space-y-1.5">
          {entry.sets.map((set, i) => (
            <li
              key={set.id}
              className="flex items-center justify-between text-sm"
            >
              <span className="text-muted-foreground">Set {i + 1}</span>
              <span className="text-foreground">
                {describeSet(set, measurement, name)}
              </span>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}

function describeSet(set: SessionSetRow, measurement: string, exerciseName?: string | null): string {
  return formatSetValues({
    weight: set.weight,
    reps: set.reps,
    timeSeconds: set.time_seconds,
    distance: set.distance,
    measurementType: measurement,
    exerciseName,
  });
}

function formatSessionDate(iso: string): string {
  // `iso` is YYYY-MM-DD; render without timezone drift.
  const [y, m, d] = iso.split("-").map(Number);
  if (!y || !m || !d) return iso;
  const date = new Date(y, m - 1, d);
  return date.toLocaleDateString(undefined, {
    weekday: "short",
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}