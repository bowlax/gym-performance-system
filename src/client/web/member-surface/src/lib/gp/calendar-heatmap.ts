import { addMonths, format, startOfMonth } from "date-fns";

export interface HeatmapDay {
  date: string;
  count: number;
  /** Between first session and today (inclusive). */
  inRange: boolean;
}

export interface HeatmapWeek {
  weekStart: string;
  days: HeatmapDay[];
}

export interface MonthLabelPlacement {
  label: string;
  weekStartIndex: number;
  weekEndIndex: number;
  row: number;
}

export interface CalendarHeatmapData {
  weeks: HeatmapWeek[];
  monthLabels: MonthLabelPlacement[];
  firstSessionDate: string;
  todayDate: string;
}

const CELL_SIZE_PX = 9;
const CELL_GAP_PX = 2;

/** Parse `YYYY-MM-DD` in local time (no timezone drift). */
export function parseISODate(iso: string): Date {
  const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
  return new Date(y, m - 1, d);
}

export function toISODate(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function startOfWeekSunday(date: Date): Date {
  const copy = new Date(date);
  copy.setHours(0, 0, 0, 0);
  copy.setDate(copy.getDate() - copy.getDay());
  return copy;
}

function endOfWeekSaturday(date: Date): Date {
  const start = startOfWeekSunday(date);
  const end = new Date(start);
  end.setDate(end.getDate() + 6);
  return end;
}

function weekHasInRangeDayInMonth(
  week: HeatmapWeek,
  year: number,
  month: number,
): boolean {
  return week.days.some((day) => {
    if (!day.inRange) return false;
    const parsed = parseISODate(day.date);
    return parsed.getFullYear() === year && parsed.getMonth() === month;
  });
}

export function placementCenterX(
  placement: MonthLabelPlacement,
  cellSize = CELL_SIZE_PX,
  cellGap = CELL_GAP_PX,
): number {
  const stride = cellSize + cellGap;
  const start = placement.weekStartIndex * stride + cellSize / 2;
  const end = placement.weekEndIndex * stride + cellSize / 2;
  return (start + end) / 2;
}

interface LabelCandidate {
  label: string;
  weekStartIndex: number;
  weekEndIndex: number;
  sortOrder: number;
}

function buildMonthLabelPlacements(
  weeks: HeatmapWeek[],
  rangeEnd: Date,
  firstSessionDate: string,
): MonthLabelPlacement[] {
  if (weeks.length === 0) return [];

  const candidates: LabelCandidate[] = [];
  const labeledMonths = new Set<string>();
  let monthCursor = startOfMonth(parseISODate(firstSessionDate));
  let sortOrder = 0;

  while (monthCursor.getTime() <= rangeEnd.getTime()) {
    const year = monthCursor.getFullYear();
    const month = monthCursor.getMonth();
    const monthKey = `${year}-${month}`;

    if (!labeledMonths.has(monthKey)) {
      const weekIndices = weeks
        .map((week, index) =>
          weekHasInRangeDayInMonth(week, year, month) ? index : -1,
        )
        .filter((index) => index >= 0);

      if (weekIndices.length > 0) {
        candidates.push({
          label: format(new Date(year, month, 1), "MMM"),
          weekStartIndex: weekIndices[0] ?? 0,
          weekEndIndex: weekIndices[weekIndices.length - 1] ?? 0,
          sortOrder,
        });
        sortOrder += 1;
        labeledMonths.add(monthKey);
      }
    }

    monthCursor = addMonths(monthCursor, 1);
  }

  if (candidates.length === 0) {
    const anchorDate =
      weeks.flatMap((week) => week.days).find((day) => day.inRange)?.date ??
      firstSessionDate;
    const targetIndex = Math.floor((weeks.length - 1) / 2);
    candidates.push({
      label: format(parseISODate(anchorDate), "MMM"),
      weekStartIndex: targetIndex,
      weekEndIndex: targetIndex,
      sortOrder: 0,
    });
  }

  return candidates.map((candidate) => ({
    label: candidate.label,
    weekStartIndex: candidate.weekStartIndex,
    weekEndIndex: candidate.weekEndIndex,
    row: 0,
  }));
}

/**
 * Build a Sunday-start week grid from the member's first session through today.
 */
export function buildCalendarHeatmap(
  sessionDates: string[],
  today: Date = new Date(),
): CalendarHeatmapData | null {
  const counts = new Map<string, number>();
  for (const raw of sessionDates) {
    const key = raw.slice(0, 10);
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }

  if (counts.size === 0) return null;

  const sortedKeys = [...counts.keys()].sort();
  const firstSessionDate = sortedKeys[0];

  const todayNorm = new Date(today);
  todayNorm.setHours(0, 0, 0, 0);
  const todayDate = toISODate(todayNorm);

  const gridStart = startOfWeekSunday(parseISODate(firstSessionDate));
  const gridEnd = endOfWeekSaturday(todayNorm);

  const weeks: HeatmapWeek[] = [];
  const cursor = new Date(gridStart);

  while (cursor.getTime() <= gridEnd.getTime()) {
    const days: HeatmapDay[] = [];
    for (let offset = 0; offset < 7; offset += 1) {
      const day = new Date(cursor);
      day.setDate(cursor.getDate() + offset);
      const key = toISODate(day);
      const isFuture = key > todayDate;
      const beforeFirst = key < firstSessionDate;

      days.push({
        date: key,
        count: isFuture || beforeFirst ? 0 : (counts.get(key) ?? 0),
        inRange: !isFuture && !beforeFirst,
      });
    }

    weeks.push({ weekStart: toISODate(cursor), days });
    cursor.setDate(cursor.getDate() + 7);
  }

  const monthLabels = buildMonthLabelPlacements(weeks, gridEnd, firstSessionDate);

  return { weeks, monthLabels, firstSessionDate, todayDate };
}

export function heatmapCellLevel(count: number): 0 | 1 | 2 | 3 | 4 {
  if (count <= 0) return 0;
  if (count === 1) return 1;
  if (count === 2) return 2;
  if (count === 3) return 3;
  return 4;
}
