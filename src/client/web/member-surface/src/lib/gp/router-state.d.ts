import type { SessionSaveSummaryLocationState } from "./session-save-summary";

declare module "@tanstack/react-router" {
  interface HistoryState extends SessionSaveSummaryLocationState {}
}
