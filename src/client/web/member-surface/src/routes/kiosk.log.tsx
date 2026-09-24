import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { ChevronLeft, Plus, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { FormField } from "@/components/gp/form-field";
import { KioskShell } from "@/components/gp/kiosk-shell";
import { MmSsFields } from "@/components/gp/mm-ss-fields";
import { SectionHeader } from "@/components/gp/app-shell";
import {
  combineMmSs,
  fieldLabel,
  fieldUnit,
  fieldsForMeasurement,
  isCableRow,
  type MeasurementType,
} from "@/lib/gp/format";
import { todayISO, type LogSessionExerciseInput } from "@/lib/gp/log-set";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export const Route = createFileRoute("/kiosk/log")({
  validateSearch: (search: Record<string, unknown>) => ({
    member: typeof search.member === "string" ? search.member : "",
    name: typeof search.name === "string" ? search.name : "",
  }),
  head: () => ({
    meta: [
      { title: "Log a session — Gym kiosk" },
      { name: "robots", content: "noindex" },
    ],
  }),
  component: KioskLogScreen,
});

interface ExerciseRow {
  id: string;
  name: string;
  measurement_type: MeasurementType;
  display_order: number;
}

type PerExerciseValues = Record<string, Record<string, string>>;

function KioskLogScreen() {
  const { member, name } = Route.useSearch();
  const navigate = useNavigate();
  if (!UUID.test(member)) {
    return (
      <KioskShell>
        <p className="text-sm text-muted-foreground">Pick a name first.</p>
        <button
          type="button"
          className="mt-4 text-sm font-medium text-primary"
          onClick={() => void navigate({ to: "/kiosk" })}
        >
          Back to names
        </button>
      </KioskShell>
    );
  }
  return <KioskLogForm memberId={member} memberName={name || "Member"} />;
}

function KioskLogForm({
  memberId,
  memberName,
}: {
  memberId: string;
  memberName: string;
}) {
  const navigate = useNavigate();
  const exercisesQuery = useQuery({
    queryKey: ["kiosk-exercises"],
    queryFn: async () => {
      const res = await fetch("/api/kiosk/exercises");
      const body = await res.json().catch(() => ({})) as {
        error?: string;
      } | ExerciseRow[];
      if (!res.ok) {
        const message = !Array.isArray(body) && body.error
          ? body.error
          : "Could not load exercises.";
        throw new Error(message);
      }
      return body as ExerciseRow[];
    },
  });

  const [sessionDate, setSessionDate] = useState(todayISO());
  const [notes, setNotes] = useState("");
  const [calories, setCalories] = useState("");
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [values, setValues] = useState<PerExerciseValues>({});
  const [pickerOpen, setPickerOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const exercises = exercisesQuery.data ?? [];
  const selectedExercises = useMemo(
    () =>
      selectedIds
        .map((id) => exercises.find((exercise) => exercise.id === id))
        .filter((exercise): exercise is ExerciseRow => Boolean(exercise)),
    [selectedIds, exercises],
  );

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      const caloriesTrimmed = calories.trim();
      let caloriesBurned: number | null = null;
      if (caloriesTrimmed !== "") {
        const parsed = Number(caloriesTrimmed);
        if (!Number.isFinite(parsed)) {
          throw new Error("Please enter a valid calories value.");
        }
        caloriesBurned = parsed;
      }
      const exercisesToLog = buildExercisesToLog(selectedExercises, values);
      const res = await fetch("/api/kiosk/submit", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          memberId,
          session: {
            date: sessionDate,
            notes: notes.trim() === "" ? null : notes.trim(),
            calories_burned: caloriesBurned,
          },
          exercises: exercisesToLog.map((exercise) => ({
            exerciseId: exercise.exerciseId,
            sets: [
              {
                ...(exercise.weight != null ? { weight: exercise.weight } : {}),
                ...(exercise.reps != null ? { reps: exercise.reps } : {}),
                ...(exercise.time != null ? { time_seconds: exercise.time } : {}),
                ...(exercise.distance != null ? { distance: exercise.distance } : {}),
              },
            ],
          })),
        }),
      });
      const body = await res.json().catch(() => ({})) as { error?: string };
      if (!res.ok) throw new Error(body.error ?? "Could not send the confirmation.");
      void navigate({ to: "/kiosk" });
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setSubmitting(false);
    }
  }

  if (pickerOpen) {
    return (
      <KioskShell>
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
          onDone={(ids) => {
            setSelectedIds((prev) => {
              const merged = [...prev];
              for (const id of ids) if (!merged.includes(id)) merged.push(id);
              return merged;
            });
            setPickerOpen(false);
          }}
        />
      </KioskShell>
    );
  }

  return (
    <KioskShell>
      <div className="mb-4 flex items-center justify-between">
        <button
          type="button"
          onClick={() => void navigate({ to: "/kiosk" })}
          className="text-sm font-medium text-primary"
        >
          Cancel
        </button>
        <h1 className="text-base font-semibold text-foreground">
          Log for {memberName}
        </h1>
        <span className="w-12" aria-hidden />
      </div>
      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="rounded-[16px] bg-card p-4 space-y-3">
          <FormField
            label="Date"
            type="date"
            value={sessionDate}
            onChange={(event) => setSessionDate(event.target.value)}
          />
          <div className="flex flex-col gap-1.5">
            <label htmlFor="notes" className="text-sm font-medium text-foreground">
              Notes <span className="text-muted-foreground">(optional)</span>
            </label>
            <textarea
              id="notes"
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
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
            onChange={(event) => setCalories(event.target.value)}
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
              {selectedExercises.map((exercise) => (
                <ExerciseEntry
                  key={exercise.id}
                  exercise={exercise}
                  values={values[exercise.id] ?? {}}
                  onChange={(field, value) =>
                    setValues((prev) => ({
                      ...prev,
                      [exercise.id]: { ...(prev[exercise.id] ?? {}), [field]: value },
                    }))
                  }
                  onRemove={() => {
                    setSelectedIds((prev) => prev.filter((id) => id !== exercise.id));
                    setValues((prev) => {
                      const next = { ...prev };
                      delete next[exercise.id];
                      return next;
                    });
                  }}
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
    </KioskShell>
  );
}

function buildExercisesToLog(
  selectedExercises: ExerciseRow[],
  values: PerExerciseValues,
): LogSessionExerciseInput[] {
  const exercisesToLog: LogSessionExerciseInput[] = [];
  for (const exercise of selectedExercises) {
    const fields = fieldsForMeasurement(exercise.measurement_type);
    const entry: LogSessionExerciseInput = { exerciseId: exercise.id };
    for (const field of fields) {
      if (field === "time" && exercise.measurement_type === "timeOnly") {
        const total = combineMmSs(values[exercise.id]?.mm, values[exercise.id]?.ss);
        if (total == null) {
          throw new Error(`Please enter a valid time (mm:ss) for ${exercise.name}.`);
        }
        entry.time = total;
        continue;
      }
      const raw = values[exercise.id]?.[field];
      const parsed = raw == null || raw === "" ? NaN : Number(raw);
      if (!Number.isFinite(parsed)) {
        throw new Error(
          `Please enter a valid ${fieldLabel(field, exercise.measurement_type, exercise.name).toLowerCase()} for ${exercise.name}.`,
        );
      }
      if (field === "weight") entry.weight = parsed;
      else if (field === "reps") entry.reps = parsed;
      else if (field === "time") entry.time = parsed;
      else if (field === "distance") entry.distance = parsed;
    }
    exercisesToLog.push(entry);
  }
  if (exercisesToLog.length === 0) {
    throw new Error("Add at least one exercise before saving.");
  }
  return exercisesToLog;
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
        <div className="text-sm font-semibold text-foreground">{exercise.name}</div>
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
          onChange={(part, value) => onChange(part, value)}
        />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {fields.map((field) => (
            <FormField
              key={field}
              label={fieldLabel(field, exercise.measurement_type, exercise.name)}
              numeric
              inputMode={
                field === "reps" || isCableRow(exercise.name) ? "numeric" : "decimal"
              }
              value={values[field] ?? ""}
              onChange={(event) => onChange(field, event.target.value)}
              trailing={
                fieldUnit(field, exercise.measurement_type, exercise.name) || undefined
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
      <div className="flex items-center">
        <button
          type="button"
          onClick={onCancel}
          className="inline-flex items-center gap-1 text-sm font-medium text-primary"
        >
          <ChevronLeft className="size-4" />
          Back
        </button>
      </div>
      <div className="rounded-[16px] bg-card p-2">
        {loading && <div className="h-40 animate-pulse rounded-[12px] bg-muted" />}
        {error && <p className="p-3 text-sm text-destructive">{error}</p>}
        {!loading && !error && exercises.length === 0 && (
          <p className="p-3 text-sm text-muted-foreground">No exercises available.</p>
        )}
        {!loading && !error &&
          exercises.map((exercise) => {
            const already = alreadySelected.includes(exercise.id);
            const checked = picked.has(exercise.id);
            return (
              <button
                key={exercise.id}
                type="button"
                onClick={() => !already && toggle(exercise.id)}
                disabled={already}
                className="flex w-full items-center justify-between rounded-[10px] px-3 py-3 text-left hover:bg-muted disabled:opacity-50"
              >
                <div className="text-sm font-medium text-foreground">{exercise.name}</div>
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
      <Button
        type="button"
        onClick={() => onDone(Array.from(picked))}
        disabled={picked.size === 0}
      >
        {picked.size === 0
          ? "Select exercises"
          : `Add ${picked.size} exercise${picked.size === 1 ? "" : "s"}`}
      </Button>
    </div>
  );
}
