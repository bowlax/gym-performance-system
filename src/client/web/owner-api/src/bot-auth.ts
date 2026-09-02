/**
 * Incoming /api/owner/* auth is the bot key, not a Supabase session.
 */

export function extractBearer(header: string | null): string | null {
  if (!header?.startsWith("Bearer ")) return null;
  const token = header.slice("Bearer ".length).trim();
  return token.length > 0 ? token : null;
}

export function timingSafeEqual(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  const len = Math.max(a.length, b.length);
  let diff = a.length === b.length ? 0 : 1;
  for (let i = 0; i < len; i += 1) {
    const av = i < a.length ? a[i]! : 0;
    const bv = i < b.length ? b[i]! : 0;
    diff |= av ^ bv;
  }
  return diff === 0;
}

export function authorizeBotKey(
  request: Request,
  expectedKey: string,
): "ok" | "missing" | "wrong" {
  if (!expectedKey || expectedKey.length < 32) {
    return "wrong";
  }
  const presented = extractBearer(request.headers.get("Authorization"));
  if (!presented) return "missing";
  return timingSafeEqual(presented, expectedKey) ? "ok" : "wrong";
}
