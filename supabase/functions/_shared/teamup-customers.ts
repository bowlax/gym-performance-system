/**
 * TeamUp M2M customer roster helpers.
 *
 * Join is GET /customers?query=<email>. JWT `sub` and ProviderCustomerProfile
 * id are different namespaces — never look up by members.teamup_customer_id.
 */

import { optionalString } from "./member-edge.ts";

const TEAMUP_CUSTOMERS_URL = "https://goteamup.com/api/v2/customers";
const AUTH_PREFIXES = ["Bearer", "Token", "JWT"] as const;

interface TeamUpCustomerPage {
  count?: number;
  next?: string | null;
  results?: unknown[];
}

export function customerDisplayName(record: Record<string, unknown>): string | null {
  const first =
    optionalString(record.first_name) ?? optionalString(record.firstName);
  const last =
    optionalString(record.last_name) ?? optionalString(record.lastName);
  const joined = [first, last].filter((part) => part && part.trim().length > 0)
    .join(" ")
    .trim();
  if (joined.length > 0) return joined;

  const combined = optionalString(record.name);
  if (combined && combined.trim().length > 0) return combined.trim();
  return null;
}

export function customerEmail(record: Record<string, unknown>): string | null {
  const direct = optionalString(record.email) ??
    optionalString(record.email_address);
  if (direct) return direct.trim();
  const nested = record.user;
  if (typeof nested === "object" && nested !== null) {
    const nestedEmail = optionalString(
      (nested as Record<string, unknown>).email,
    );
    if (nestedEmail) return nestedEmail.trim();
  }
  return null;
}

export function emailsMatch(left: string, right: string): boolean {
  return left.trim().toLowerCase() === right.trim().toLowerCase();
}

export function pickCustomerByEmail(
  results: unknown[],
  email: string,
): Record<string, unknown> | null {
  const matches: Record<string, unknown>[] = [];
  for (const row of results) {
    if (typeof row !== "object" || row === null) continue;
    const record = row as Record<string, unknown>;
    const recordEmail = customerEmail(record);
    if (recordEmail && emailsMatch(recordEmail, email)) {
      matches.push(record);
    }
  }
  if (matches.length === 0) return null;
  const converted = matches.find((record) =>
    optionalString(record.status)?.toLowerCase() === "converted"
  );
  return converted ?? matches[0] ?? null;
}

async function teamUpGetCustomers(
  token: string,
  providerId: string,
  prefix: string,
  params: Record<string, string>,
): Promise<{ ok: true; json: TeamUpCustomerPage } | { ok: false; status: number }> {
  const url = new URL(TEAMUP_CUSTOMERS_URL);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }

  const response = await fetch(url, {
    headers: {
      Authorization: `${prefix} ${token}`,
      "TeamUp-Provider-ID": providerId,
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    return { ok: false, status: response.status };
  }

  const json = await response.json() as TeamUpCustomerPage;
  return { ok: true, json };
}

export async function detectTeamUpAuthPrefix(
  token: string,
  providerId: string,
): Promise<string> {
  for (const prefix of AUTH_PREFIXES) {
    const result = await teamUpGetCustomers(token, providerId, prefix, {
      page: "1",
      page_size: "1",
    });
    if (result.ok) return prefix;
  }
  throw new Error("TeamUp customers list rejected every auth prefix");
}

export async function lookupCustomerByEmail(
  token: string,
  providerId: string,
  prefix: string,
  email: string,
): Promise<Record<string, unknown> | null> {
  const result = await teamUpGetCustomers(token, providerId, prefix, {
    query: email,
    page: "1",
    page_size: "20",
  });
  if (!result.ok) {
    throw new Error(`TeamUp customer email query failed (${result.status})`);
  }
  const rows = Array.isArray(result.json.results) ? result.json.results : [];
  return pickCustomerByEmail(rows, email);
}

/**
 * Best-effort roster name for connect. Missing M2M config or TeamUp errors
 * return null so OAuth still succeeds; display_name stays as-is until refresh.
 */
export async function lookupDisplayNameByEmailBestEffort(
  email: string,
): Promise<string | null> {
  const token = Deno.env.get("TEAMUP_M2M_TOKEN")?.trim();
  const providerId = Deno.env.get("TEAMUP_OAUTH_PROVIDER_ID")?.trim();
  if (!token || !providerId || !email.trim()) return null;
  try {
    const prefix = await detectTeamUpAuthPrefix(token, providerId);
    const record = await lookupCustomerByEmail(
      token,
      providerId,
      prefix,
      email,
    );
    return record ? customerDisplayName(record) : null;
  } catch {
    return null;
  }
}
