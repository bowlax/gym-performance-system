/**
 * Who appears on the kiosk name picker.
 *
 * A resolved name is the email-based roster match (teamup_email captured and
 * teamup_roster_id written by that lookup), plus a display_name that is not
 * the unresolved sentinel. No Deno or Supabase imports — the member web
 * server uses the same predicate.
 */

export const UNRESOLVED_DISPLAY_NAME = "Member";

export interface KioskNameRow {
  display_name: string | null;
  teamup_email: string | null;
  teamup_roster_id: string | null;
  deleted_at?: string | null;
}

export function hasResolvedKioskName(member: KioskNameRow): boolean {
  if (member.deleted_at) return false;
  const name = member.display_name?.trim() ?? "";
  if (name.length === 0 || name === UNRESOLVED_DISPLAY_NAME) return false;
  const email = member.teamup_email?.trim() ?? "";
  if (email.length === 0) return false;
  const rosterId = member.teamup_roster_id?.trim() ?? "";
  return rosterId.length > 0;
}

export interface KioskMemberOption {
  member_id: string;
  display_name: string;
}

export function kioskMemberOptions(
  rows: Array<KioskNameRow & { id?: string; member_id?: string }>,
): KioskMemberOption[] {
  const options: KioskMemberOption[] = [];
  for (const row of rows) {
    const memberId = row.member_id ?? row.id ?? "";
    if (!memberId || !hasResolvedKioskName(row)) continue;
    options.push({
      member_id: memberId,
      display_name: row.display_name!.trim(),
    });
  }
  options.sort((left, right) => left.display_name.localeCompare(right.display_name));
  return options;
}
