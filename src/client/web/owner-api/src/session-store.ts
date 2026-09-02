/** Refresh when access token expires within this window (matches iOS skew). */
export const REFRESH_SKEW_SECONDS = 60;

export interface OwnerSessionData {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  issuedAt: number;
}

export function sessionNeedsRefresh(
  expiresAt: number | undefined,
  nowSeconds: number = Math.floor(Date.now() / 1000),
): boolean {
  if (expiresAt == null || !Number.isFinite(expiresAt)) return true;
  return expiresAt - REFRESH_SKEW_SECONDS <= nowSeconds;
}

export function isValidOwnerSessionData(
  data: Partial<OwnerSessionData> | null | undefined,
): data is OwnerSessionData {
  if (!data) return false;
  return (
    typeof data.accessToken === "string" &&
    data.accessToken.length > 0 &&
    typeof data.refreshToken === "string" &&
    data.refreshToken.length > 0 &&
    typeof data.expiresAt === "number" &&
    Number.isFinite(data.expiresAt) &&
    typeof data.issuedAt === "number" &&
    Number.isFinite(data.issuedAt)
  );
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function importSealKey(secret: string): Promise<CryptoKey> {
  const material = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(secret),
  );
  return crypto.subtle.importKey("raw", material, { name: "AES-GCM" }, false, [
    "encrypt",
    "decrypt",
  ]);
}

export async function sealOwnerSession(
  secret: string,
  data: OwnerSessionData,
): Promise<string> {
  if (secret.length < 32) {
    throw new Error("OWNER_SESSION_SECRET must be at least 32 characters");
  }
  const key = await importSealKey(secret);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plaintext = new TextEncoder().encode(JSON.stringify(data));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, plaintext),
  );
  const packed = new Uint8Array(iv.length + ciphertext.length);
  packed.set(iv, 0);
  packed.set(ciphertext, iv.length);
  return bytesToBase64(packed);
}

export async function unsealOwnerSession(
  secret: string,
  sealed: string,
): Promise<OwnerSessionData | null> {
  try {
    const key = await importSealKey(secret);
    const packed = base64ToBytes(sealed);
    if (packed.length < 13) return null;
    const iv = packed.subarray(0, 12);
    const ciphertext = packed.subarray(12);
    const plaintext = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv },
      key,
      ciphertext,
    );
    const parsed = JSON.parse(new TextDecoder().decode(plaintext)) as unknown;
    if (typeof parsed !== "object" || parsed === null) return null;
    const record = parsed as Partial<OwnerSessionData>;
    if (!isValidOwnerSessionData(record)) return null;
    return record;
  } catch {
    return null;
  }
}

export const OWNER_SESSION_KV_KEY = "lee";

export interface OwnerSessionKv {
  get(key: string): Promise<string | null>;
  put(key: string, value: string): Promise<void>;
}

export async function readSealedOwnerSession(
  kv: OwnerSessionKv,
  secret: string,
): Promise<OwnerSessionData | null> {
  const sealed = await kv.get(OWNER_SESSION_KV_KEY);
  if (!sealed) return null;
  return unsealOwnerSession(secret, sealed);
}

export async function writeSealedOwnerSession(
  kv: OwnerSessionKv,
  secret: string,
  data: OwnerSessionData,
): Promise<void> {
  const sealed = await sealOwnerSession(secret, data);
  await kv.put(OWNER_SESSION_KV_KEY, sealed);
}
