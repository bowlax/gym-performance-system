import { cn } from "@/lib/utils";

export interface PBCardProps {
  lift: string;
  /** Full PB display string (e.g. `80kg × 5`). Omit for exercises without a PB. */
  value?: string;
  /** Short date under the PB value (e.g. `8 Jul`). */
  achievedAt?: string;
  /** Caption when there is no current PB. */
  emptyCaption?: string;
  className?: string;
}

/**
 * Board exercise card — mirrors iOS `BoardView.row`.
 *
 * Name and value share one row with a reserved trailing column so long
 * exercise names wrap in their own lane instead of colliding with the PB.
 */
export function PBCard({
  lift,
  value,
  achievedAt,
  emptyCaption = "No PB yet",
  className,
}: PBCardProps) {
  return (
    <div
      className={cn(
        "flex overflow-hidden rounded-[16px] bg-card text-card-foreground",
        className,
      )}
    >
      <div className="w-[3px] shrink-0 bg-primary" aria-hidden />
      <div className="grid min-w-0 flex-1 grid-cols-[minmax(0,1fr)_auto] items-start gap-x-4 gap-y-1 p-4">
        <h3 className="min-w-0 text-[17px] font-semibold leading-snug text-foreground [overflow-wrap:anywhere]">
          {lift}
        </h3>
        {value ? (
          <div className="max-w-[11rem] justify-self-end text-right sm:max-w-none">
            <div className="font-numeric text-[28px] font-semibold leading-none tracking-tight text-primary sm:text-[34px]">
              {value}
            </div>
            {achievedAt ? (
              <div className="mt-1 text-xs text-muted-foreground">{achievedAt}</div>
            ) : null}
          </div>
        ) : (
          <span className="max-w-[11rem] justify-self-end text-right text-xs leading-snug text-muted-foreground sm:max-w-[14rem]">
            {emptyCaption}
          </span>
        )}
      </div>
    </div>
  );
}
