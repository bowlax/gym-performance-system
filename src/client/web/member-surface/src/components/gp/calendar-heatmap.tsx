import { useEffect, useMemo, useRef, type CSSProperties } from "react";
import { format } from "date-fns";
import {
  buildCalendarHeatmap,
  heatmapCellLevel,
  parseISODate,
  placementCenterX,
  type HeatmapDay,
  type MonthLabelPlacement,
} from "@/lib/gp/calendar-heatmap";
import { cn } from "@/lib/utils";

const DAY_LABELS = ["S", "M", "T", "W", "T", "F", "S"] as const;
const CELL_SIZE_PX = 9;
const CELL_GAP_PX = 2;
const LABEL_COL_PX = 14;
const WEEK_COL_PX = CELL_SIZE_PX;
const WEEK_GRID_OFFSET_PX = LABEL_COL_PX + CELL_GAP_PX;

function weeksGridWidth(weekCount: number): number {
  return weekCount * WEEK_COL_PX + Math.max(0, weekCount - 1) * CELL_GAP_PX;
}

const SESSION_LEVEL_CLASS: Record<1 | 2 | 3 | 4, string> = {
  1: "bg-primary/35",
  2: "bg-primary/55",
  3: "bg-primary/75",
  4: "bg-primary",
};

export interface CalendarHeatmapProps {
  sessionDates: string[];
}

export function CalendarHeatmap({ sessionDates }: CalendarHeatmapProps) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const data = useMemo(
    () => buildCalendarHeatmap(sessionDates),
    [sessionDates],
  );

  useEffect(() => {
    const el = scrollRef.current;
    if (!el || !data) return;
    el.scrollLeft = el.scrollWidth - el.clientWidth;
  }, [data]);

  if (!data || data.weeks.length === 0) return null;

  const weekCount = data.weeks.length;
  const weekGridColumns = `repeat(${weekCount}, ${WEEK_COL_PX}px)`;

  return (
    <div
      ref={scrollRef}
      className="overflow-x-auto overscroll-x-contain [scrollbar-width:thin]"
      aria-label="Training consistency calendar"
    >
      <div className="inline-block min-w-max">
        <div
          className="grid"
          style={{
            gridTemplateColumns: `${LABEL_COL_PX}px ${weekGridColumns}`,
            gridTemplateRows: `repeat(7, ${CELL_SIZE_PX}px)`,
            columnGap: `${CELL_GAP_PX}px`,
            rowGap: `${CELL_GAP_PX}px`,
          }}
        >
          {DAY_LABELS.map((label, rowIndex) => (
            <span
              key={`label-${rowIndex}`}
              className="sticky left-0 z-10 flex items-center justify-end bg-card text-[11px] font-medium leading-none text-muted-foreground"
              style={{ gridColumn: 1, gridRow: rowIndex + 1 }}
              aria-hidden
            >
              {label}
            </span>
          ))}

          {data.weeks.map((week, weekIndex) =>
            week.days.map((day, dayIndex) => (
              <HeatmapCell
                key={day.date}
                day={day}
                style={{
                  gridColumn: weekIndex + 2,
                  gridRow: dayIndex + 1,
                }}
              />
            )),
          )}
        </div>

        <div
          className="relative mt-1.5 h-4"
          style={{ width: WEEK_GRID_OFFSET_PX + weeksGridWidth(weekCount) }}
        >
          {data.monthLabels.map((placement) => (
            <MonthLabel
              key={`${placement.label}-${placement.weekStartIndex}-${placement.weekEndIndex}`}
              placement={placement}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

function MonthLabel({ placement }: { placement: MonthLabelPlacement }) {
  return (
    <span
      className="absolute top-0 -translate-x-1/2 whitespace-nowrap text-[11px] leading-none text-muted-foreground"
      style={{ left: WEEK_GRID_OFFSET_PX + placementCenterX(placement) }}
    >
      {placement.label}
    </span>
  );
}

function HeatmapCell({
  day,
  style,
}: {
  day: HeatmapDay;
  style: CSSProperties;
}) {
  const title = day.inRange
    ? `${format(parseISODate(day.date), "EEE d MMM yyyy")}${
        day.count > 0
          ? ` — ${day.count} session${day.count === 1 ? "" : "s"}`
          : " — no session"
      }`
    : undefined;

  return (
    <div
      title={title}
      className={cn("size-[9px] rounded-[2px]", cellClass(day))}
      style={style}
    />
  );
}

function cellClass(day: HeatmapDay): string {
  if (!day.inRange) return "bg-transparent";
  if (day.count === 0) return "bg-border";
  return SESSION_LEVEL_CLASS[heatmapCellLevel(day.count)];
}
