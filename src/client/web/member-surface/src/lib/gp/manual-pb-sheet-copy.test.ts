import { describe, expect, test } from "bun:test";
import {
  manualSheetIntentAfterParentClearsEditing,
  manualSheetSaveLabel,
  manualSheetSuccessMessage,
  manualSheetTitle,
  snapshotManualSheetIntent,
} from "./manual-pb-sheet-copy";

describe("manual sheet copy", () => {
  test("edit open snapshots as edit, not add", () => {
    expect(snapshotManualSheetIntent({ id: "pb-1" })).toBe("edit");
    expect(snapshotManualSheetIntent(null)).toBe("add");
  });

  test("edit success copy stays on PB updated, not New PB saved", () => {
    expect(manualSheetTitle("edit")).toBe("Edit manual PB");
    expect(manualSheetSuccessMessage("edit")).toBe("PB updated");
    expect(manualSheetSaveLabel("edit", false)).toBe("Save Changes");
    expect(manualSheetTitle("add")).toBe("Add PB manually");
    expect(manualSheetSuccessMessage("add")).toBe("New PB saved");
  });

  test("parent clearing editing while sheet is still open does not flip to add", () => {
    expect(
      manualSheetIntentAfterParentClearsEditing({
        open: true,
        captured: "edit",
        editing: null,
      }),
    ).toBe("edit");
    expect(
      manualSheetIntentAfterParentClearsEditing({
        open: false,
        captured: "edit",
        editing: null,
      }),
    ).toBe("edit");
  });
});
