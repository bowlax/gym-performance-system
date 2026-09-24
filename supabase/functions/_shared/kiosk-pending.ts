/**
 * Kiosk pending logs.
 *
 * Shared parsing, the resolved-name predicate, and the confirm email live in
 * kiosk-names.ts so the member web server can use them without Deno. This
 * module re-exports them for the edge function.
 */

export {
  UNRESOLVED_DISPLAY_NAME,
  buildKioskConfirmEmail,
  hashKioskToken,
  hasResolvedKioskName,
  kioskMemberOptions,
  newKioskToken,
  parseKioskSubmitBody,
  type KioskEmailCopy,
  type KioskEmailExercise,
  type KioskExerciseInput,
  type KioskMemberOption,
  type KioskNameRow,
  type KioskPendingPayload,
  type KioskSetInput,
  type KioskSubmitRequest,
} from "./kiosk-names.ts";
