export interface SessionSaveSummaryItem {
  exerciseId: string;
  exerciseName: string;
  isPersonalBest: boolean;
}

export interface SessionSaveSummary {
  items: SessionSaveSummaryItem[];
}

const STORAGE_KEY = "gp.sessionSaveSummary";

export function stashSessionSaveSummary(summary: SessionSaveSummary): void {
  if (typeof sessionStorage === "undefined") return;
  sessionStorage.setItem(STORAGE_KEY, JSON.stringify(summary));
}

export function takeSessionSaveSummary(): SessionSaveSummary | null {
  if (typeof sessionStorage === "undefined") return null;
  const raw = sessionStorage.getItem(STORAGE_KEY);
  if (!raw) return null;
  sessionStorage.removeItem(STORAGE_KEY);
  try {
    const parsed = JSON.parse(raw) as SessionSaveSummary;
    if (!parsed || !Array.isArray(parsed.items)) return null;
    return parsed;
  } catch {
    return null;
  }
}
