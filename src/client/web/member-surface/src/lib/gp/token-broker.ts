import {
  SUPABASE_PUBLISHABLE_KEY,
  TEST_DEVICE_MEMBER_ID,
  TOKEN_BROKER_URL,
} from "./env";

/**
 * A TokenBroker exchanges an upstream identity (TeamUp today, real OAuth
 * tomorrow) for a Supabase-compatible JWT that RLS understands.
 *
 * The rest of the app depends on this interface, never on TeamUp specifics,
 * so real OAuth can be swapped in later by shipping a new broker
 * implementation.
 */
export interface BrokerSession {
  token: string;
  /** Unix seconds; may be undefined if the broker doesn't share it. */
  expiresAt?: number;
  /** Any extra fields the broker returned, for debug/inspection. */
  raw: Record<string, unknown>;
}

export interface TokenBroker {
  mint(): Promise<BrokerSession>;
}

/**
 * Stub broker: sends a hardcoded TeamUp token + a configured test member id.
 * When real OAuth lands, replace this with a broker that resolves the current
 * TeamUp session and passes the real values to the same edge function.
 */
export class StubTeamUpBroker implements TokenBroker {
  async mint(): Promise<BrokerSession> {
    if (!SUPABASE_PUBLISHABLE_KEY) {
      throw new Error(
        "Supabase publishable key is not configured. Add GYMPERF_SUPABASE_PUBLISHABLE_KEY in Project Settings → Secrets.",
      );
    }
    if (!TEST_DEVICE_MEMBER_ID) {
      throw new Error(
        "Test device member id is not configured. Add TEST_DEVICE_MEMBER_ID in Project Settings → Secrets.",
      );
    }

    const response = await fetch(TOKEN_BROKER_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${SUPABASE_PUBLISHABLE_KEY}`,
        apikey: SUPABASE_PUBLISHABLE_KEY,
      },
      body: JSON.stringify({
        teamupToken: "stub-token",
        deviceMemberId: TEST_DEVICE_MEMBER_ID,
        surface: "memberWeb",
      }),
    });

    if (!response.ok) {
      const detail = await response.text().catch(() => "");
      throw new Error(
        `Token broker rejected the request (${response.status}). ${detail}`,
      );
    }

    const raw = (await response.json()) as Record<string, unknown>;
    const token =
      pickString(raw, ["token", "access_token", "accessToken", "jwt"]) ?? "";
    if (!token) {
      throw new Error(
        "Token broker response did not contain a token field.",
      );
    }
    const expiresAt = pickNumber(raw, [
      "expires_at",
      "expiresAt",
      "exp",
    ]);
    return { token, expiresAt, raw };
  }
}

function pickString(o: Record<string, unknown>, keys: string[]) {
  for (const k of keys) {
    const v = o[k];
    if (typeof v === "string" && v.length > 0) return v;
  }
  return undefined;
}

function pickNumber(o: Record<string, unknown>, keys: string[]) {
  for (const k of keys) {
    const v = o[k];
    if (typeof v === "number" && Number.isFinite(v)) return v;
  }
  return undefined;
}

export const defaultBroker: TokenBroker = new StubTeamUpBroker();