import { cn } from "@/lib/utils";

export interface PBCardProps {
  lift: string;
  /** Full PB display string (e.g. `80kg × 5`). Omit for exercises without a PB. */
  value?: string;
  /** Short date under the PB value (e.g. `8 Jul`). */
  achievedAt?: string;
  className?: string;
}

/**
 * Board exercise card — mirrors iOS `BoardView.row` layout.
 */
export function PBCard({ lift, value, achievedAt, className }: PBCardProps) {
  return (
    <div
      className={cn(
        "flex overflow-hidden rounded-[16px] bg-card text-card-foreground",
        className,
      )}
    >
      <div
        className="w-[3px] shrink-0 bg-primary"
        aria-hidden
      />
      <div className="flex min-w-0 flex-1 items-start justify-between gap-3 p-4">
        <h3 className="min-w-0 flex-1 text-[17px] font-semibold leading-snug text-foreground">
          {lift}
        </h3>
        {value ? (
          <div className="shrink-0 text-right">
            <div className="font-numeric text-[34px] font-semibold leading-none tracking-tight text-primary">
              {value}
            </div>
            {achievedAt ? (
              <div className="mt-1 text-xs text-muted-foreground">{achievedAt}</div>
            ) : null}
          </div>
        ) : (
          <span className="shrink-0 text-xs text-muted-foreground">No PB yet</span>
        )}
      </div>
    </div>
  );
}
