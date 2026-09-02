/**
 * Seal Lee's provisioned owner session for KV.
 * Reads scripts/.owner-auth.json (gitignored) and OWNER_SESSION_SECRET.
 * Writes .sealed-lee.txt (gitignored) — ciphertext only.
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { sealOwnerSession, type OwnerSessionData } from "./session-store";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "../../../../../");
const statePath = join(root, "scripts/.owner-auth.json");
const outPath = join(here, "../.sealed-lee.txt");

function loadDevVars(): Record<string, string> {
  const path = join(here, "../.dev.vars");
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

const secret = process.env.OWNER_SESSION_SECRET ?? loadDevVars().OWNER_SESSION_SECRET;
if (!secret) {
  throw new Error("Set OWNER_SESSION_SECRET (env or .dev.vars)");
}
if (!existsSync(statePath)) {
  throw new Error("Run scripts/provision-owner-auth.mjs first");
}

const state = JSON.parse(readFileSync(statePath, "utf8")) as {
  users?: { lee?: { refreshToken?: string; expiresAt?: number } };
};
const lee = state.users?.lee;
if (!lee?.refreshToken || !lee.expiresAt) {
  throw new Error("Lee session missing from .owner-auth.json");
}

const now = Math.floor(Date.now() / 1000);
const data: OwnerSessionData = {
  accessToken: "pending-refresh",
  refreshToken: lee.refreshToken,
  expiresAt: 0,
  issuedAt: now,
};
const sealed = await sealOwnerSession(secret, data);
writeFileSync(outPath, sealed);
console.log(`Wrote sealed Lee session to ${outPath} (ciphertext only).`);
console.log(
  "Put it: npx wrangler kv key put lee --binding OWNER_SESSION --path .sealed-lee.txt",
);
