export interface SessionSaveSummaryItem {
  exerciseId: string;
  exerciseName: string;
  isPersonalBest: boolean;
}

export interface SessionSaveSummary {
  items: SessionSaveSummaryItem[];
}

export interface SessionSaveSummaryLocationState {
  sessionSaveSummary?: SessionSaveSummary;
}

const STORAGE_KEY = "gp.sessionSaveSummary";

function isSessionSaveSummary(value: unknown): value is SessionSaveSummary {
  if (!value || typeof value !== "object") return false;
  const items = (value as SessionSaveSummary).items;
  return Array.isArray(items);
}

export function stashSessionSaveSummary(summary: SessionSaveSummary): void {
  if (typeof sessionStorage === "undefined") return;
  sessionStorage.setItem(STORAGE_KEY, JSON.stringify(summary));
}

/** Read without removing — safe for effects that may run more than once. */
export function readSessionSaveSummary(): SessionSaveSummary | null {
  if (typeof sessionStorage === "undefined") return null;
  const raw = sessionStorage.getItem(STORAGE_KEY);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!isSessionSaveSummary(parsed)) return null;
    return parsed;
  } catch {
    return null;
  }
}

export function clearSessionSaveSummary(): void {
  if (typeof sessionStorage === "undefined") return;
  sessionStorage.removeItem(STORAGE_KEY);
}

/** @deprecated Prefer router state + readSessionSaveSummary */
export function takeSessionSaveSummary(): SessionSaveSummary | null {
  const summary = readSessionSaveSummary();
  if (summary) clearSessionSaveSummary();
  return summary;
}

export function sessionSaveSummaryFromLocationState(
  state: unknown,
): SessionSaveSummary | null {
  if (!state || typeof state !== "object") return null;
  const summary = (state as SessionSaveSummaryLocationState)
    .sessionSaveSummary;
  return isSessionSaveSummary(summary) ? summary : null;
}
