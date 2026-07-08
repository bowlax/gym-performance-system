/**
 * Minutes + seconds inputs for timeOnly exercises (iOS mmssTimeField parity).
 * Values are stored as string fragments; combine with `combineMmSs` on submit.
 */
export function MmSsFields({
  mm,
  ss,
  onChange,
  idPrefix = "time",
}: {
  mm: string;
  ss: string;
  onChange: (part: "mm" | "ss", value: string) => void;
  idPrefix?: string;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-sm font-medium text-foreground">Time</span>
      <div className="flex items-end gap-2">
        <div className="flex flex-col gap-1.5">
          <label
            htmlFor={`${idPrefix}-mm`}
            className="text-xs text-muted-foreground"
          >
            mm
          </label>
          <div className="flex items-center rounded-[10px] border border-input bg-surface px-3.5 h-12 transition-shadow focus-within:border-primary focus-within:ring-4 focus-within:ring-primary/15">
            <input
              id={`${idPrefix}-mm`}
              inputMode="numeric"
              placeholder="0"
              value={mm}
              onChange={(e) => onChange("mm", e.target.value)}
              className="h-full w-14 bg-transparent font-numeric text-lg text-foreground outline-none placeholder:text-muted-foreground"
            />
          </div>
        </div>
        <span className="mb-3 text-lg font-medium text-muted-foreground">:</span>
        <div className="flex flex-col gap-1.5">
          <label
            htmlFor={`${idPrefix}-ss`}
            className="text-xs text-muted-foreground"
          >
            ss
          </label>
          <div className="flex items-center rounded-[10px] border border-input bg-surface px-3.5 h-12 transition-shadow focus-within:border-primary focus-within:ring-4 focus-within:ring-primary/15">
            <input
              id={`${idPrefix}-ss`}
              inputMode="numeric"
              placeholder="00"
              value={ss}
              onChange={(e) => onChange("ss", e.target.value)}
              className="h-full w-14 bg-transparent font-numeric text-lg text-foreground outline-none placeholder:text-muted-foreground"
            />
          </div>
        </div>
      </div>
    </div>
  );
}
