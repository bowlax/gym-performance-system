export type ManualSheetIntent = "add" | "edit";

export function snapshotManualSheetIntent(
  editing: { id: string } | null,
): ManualSheetIntent {
  return editing == null ? "add" : "edit";
}

export function manualSheetTitle(intent: ManualSheetIntent): string {
  return intent === "edit" ? "Edit manual PB" : "Add PB manually";
}

export function manualSheetSuccessMessage(intent: ManualSheetIntent): string {
  return intent === "edit" ? "PB updated" : "New PB saved";
}

export function manualSheetSaveLabel(
  intent: ManualSheetIntent,
  saving: boolean,
): string {
  if (saving) return "Saving…";
  return intent === "edit" ? "Save Changes" : "Save PB";
}

/**
 * Closing the sheet clears `editing` in the same render as `open=false`.
 * Success copy must keep using the intent captured at open, not the live
 * `editing` prop — otherwise the sheet flashes Add-PB / "New PB saved".
 */
export function manualSheetIntentAfterParentClearsEditing(args: {
  open: boolean;
  captured: ManualSheetIntent;
  editing: { id: string } | null;
}): ManualSheetIntent {
  if (!args.open) return args.captured;
  if (args.editing) return "edit";
  return args.captured;
}
