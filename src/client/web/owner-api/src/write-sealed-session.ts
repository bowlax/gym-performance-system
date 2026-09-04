/**
 * Seal Lee's provisioned owner session for KV.
 * Reads scripts/.owner-auth.json (gitignored) and OWNER_SESSION_SECRET.
 * Refreshes once locally so KV holds a live access token — the Worker
 * must not refresh on first request (GoTrue already_used if it races).
 * Writes .sealed-lee.txt (gitignored) — ciphertext only.
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { refreshGoTrueSession } from "./gotrue-refresh";
import { sealOwnerSession, type OwnerSessionData } from "./session-store";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "../../../../../");
const statePath = join(root, "scripts/.owner-auth.json");
const outPath = join(here, "../.sealed-lee.txt");

function loadEnvFile(path: string): Record<string, string> {
  if (!existsSync(path)) return {};
  const out: Record<string, string> = {};
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) continue;
    const i = trimmed.indexOf("=");
    out[trimmed.slice(0, i)] = trimmed.slice(i + 1).trim().replace(/^['"]|['"]$/g, "");
  }
  return out;
}

const secret =
  process.env.OWNER_SESSION_SECRET ?? loadEnvFile(join(here, "../.dev.vars")).OWNER_SESSION_SECRET;
if (!secret) {
  throw new Error("Set OWNER_SESSION_SECRET (env or .dev.vars)");
}
if (!existsSync(statePath)) {
  throw new Error("Run scripts/provision-owner-auth.mjs first");
}

const web = loadEnvFile(join(root, "src/client/web/member-surface/.env.local"));
const supabaseUrl = web.GYMPERF_SUPABASE_URL;
const publishableKey = web.GYMPERF_SUPABASE_PUBLISHABLE_KEY;
if (!supabaseUrl || !publishableKey) {
  throw new Error("Missing GYMPERF_SUPABASE_URL / GYMPERF_SUPABASE_PUBLISHABLE_KEY");
}

const state = JSON.parse(readFileSync(statePath, "utf8")) as {
  users?: { lee?: { refreshToken?: string; expiresAt?: number } };
};
const lee = state.users?.lee;
if (!lee?.refreshToken) {
  throw new Error("Lee session missing from .owner-auth.json");
}

const now = Math.floor(Date.now() / 1000);
const refreshed = await refreshGoTrueSession({
  refreshToken: lee.refreshToken,
  supabaseUrl,
  publishableKey,
  nowSeconds: now,
});
lee.refreshToken = refreshed.refreshToken;
lee.expiresAt = refreshed.expiresAt;
writeFileSync(statePath, `${JSON.stringify(state, null, 2)}\n`);

const data: OwnerSessionData = {
  accessToken: refreshed.accessToken,
  refreshToken: refreshed.refreshToken,
  expiresAt: refreshed.expiresAt,
  issuedAt: now,
};
const sealed = await sealOwnerSession(secret, data);
writeFileSync(outPath, sealed);
console.log(`Wrote sealed Lee session to ${outPath} (live access token, ciphertext only).`);
console.log(
  "Put it: npx wrangler kv key put lee --binding OWNER_SESSION --remote --path .sealed-lee.txt",
);
