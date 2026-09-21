import { SignJWT, jwtVerify } from "jsr:@panva/jose@6";

export const LOG_REMINDER_OPT_OUT_PURPOSE = "log_reminder_opt_out";
const TOKEN_TTL_SECONDS = 90 * 24 * 60 * 60;

export async function signLogReminderOptOutToken(
  memberId: string,
  secret: string,
  nowSeconds: number = Math.floor(Date.now() / 1000),
): Promise<string> {
  return await new SignJWT({
    member_id: memberId,
    purpose: LOG_REMINDER_OPT_OUT_PURPOSE,
  })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setAudience(LOG_REMINDER_OPT_OUT_PURPOSE)
    .setIssuedAt(nowSeconds)
    .setExpirationTime(nowSeconds + TOKEN_TTL_SECONDS)
    .sign(new TextEncoder().encode(secret));
}

export async function verifyLogReminderOptOutToken(
  token: string,
  secret: string,
): Promise<{ memberId: string }> {
  const { payload } = await jwtVerify(
    token,
    new TextEncoder().encode(secret),
    { audience: LOG_REMINDER_OPT_OUT_PURPOSE },
  );
  const memberId = payload.member_id;
  const purpose = payload.purpose;
  if (typeof memberId !== "string" || memberId.length === 0) {
    throw new Error("opt-out token is missing member_id");
  }
  if (purpose !== LOG_REMINDER_OPT_OUT_PURPOSE) {
    throw new Error("opt-out token has the wrong purpose");
  }
  return { memberId };
}
