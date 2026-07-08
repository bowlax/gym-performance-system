import { cn } from "@/lib/utils";

export interface PBCardProps {
  lift: string;
  value: number;
  unit?: string;
  achievedAt?: string;
  isPB?: boolean;
  className?: string;
}

/**
 * PBCard — the core Board card. When `isPB` is true, the card gets the
 * electric-yellow celebration ring and PB badge. Weight is rendered in the
 * tabular numeric treatment shared with iOS.
 */
export function PBCard({
  lift,
  value,
  unit = "kg",
  achievedAt,
  isPB: _isPB = false,
  className,
}: PBCardProps) {
  return (
    <div
      className={cn(
        "relative overflow-hidden rounded-[16px] bg-card p-4 pl-5 text-card-foreground",
        "before:absolute before:inset-y-0 before:left-0 before:w-1 before:bg-primary",
        className,
      )}
    >
      <div className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">{lift}</div>
      <div className="mt-3 flex items-baseline gap-1.5">
        <span className="font-numeric text-5xl font-semibold leading-none text-primary">
          {value}
        </span>
        <span className="text-lg font-medium text-muted-foreground">{unit}</span>
      </div>
      {achievedAt && (
        <div className="mt-3 text-xs text-muted-foreground">{achievedAt}</div>
      )}
    </div>
  );
}