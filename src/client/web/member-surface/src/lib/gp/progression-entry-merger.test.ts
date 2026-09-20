import { describe, expect, test } from "bun:test";
import {
  sortProgressionHistoryForList,
  type ProgressionEntryRow,
} from "./progression-entry-merger";

function row(
  partial: Pick<ProgressionEntryRow, "id" | "date" | "isUndated">,
): ProgressionEntryRow {
  return {
    formattedValue: partial.id,
    chartValue: 1,
    isPB: false,
    isResetMarker: false,
    setId: null,
    personalBestId: partial.id,
    weight: null,
    reps: null,
    time_seconds: null,
    distance: null,
    ...partial,
  };
}

describe("sortProgressionHistoryForList", () => {
  test("puts undated rows before dated rows, then dated newest-first", () => {
    const undated = row({ id: "undated", date: "0001-01-01", isUndated: true });
    const may = row({ id: "may", date: "2026-05-29", isUndated: false });
    const june = row({ id: "june", date: "2026-06-10", isUndated: false });

    const list = sortProgressionHistoryForList([june, undated, may]);

    expect(list.map((entry) => entry.id)).toEqual(["undated", "june", "may"]);
  });
});
