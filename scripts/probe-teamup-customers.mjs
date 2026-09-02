#!/usr/bin/env node
/**
 * Isolated LIVE probe of TeamUp GET /customers with the M2M token.
 * Confirms auth header prefix, pagination shape, and name field keys
 * before owner-member-names sync is trusted.
 *
 * Usage:
 *   TEAMUP_M2M_TOKEN=... node scripts/probe-teamup-customers.mjs
 *
 * Optional: TEAMUP_PROVIDER_ID (defaults to Wolf 5404319).
 * Prints Object.keys of the first customer only — not names or emails.
 */

const PROVIDER_ID = process.env.TEAMUP_PROVIDER_ID?.trim() || "5404319";
const TOKEN = process.env.TEAMUP_M2M_TOKEN?.trim();
const PREFIXES = ["Bearer", "Token", "JWT"];

if (!TOKEN) {
  console.error("Set TEAMUP_M2M_TOKEN");
  process.exit(1);
}

async function tryPrefix(prefix) {
  const url = new URL("https://goteamup.com/api/v2/customers");
  url.searchParams.set("page", "1");
  url.searchParams.set("page_size", "1");

  const res = await fetch(url, {
    headers: {
      Authorization: `${prefix} ${TOKEN}`,
      "TeamUp-Provider-ID": PROVIDER_ID,
      Accept: "application/json",
    },
  });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    json = null;
  }
  return { prefix, status: res.status, json, textLength: text.length };
}

function summarize(json) {
  if (!json || typeof json !== "object") return { shape: "non-object" };
  const record = json;
  const keys = Object.keys(record);
  const results = Array.isArray(record.results) ? record.results : null;
  const first = results?.[0];
  return {
    topLevelKeys: keys,
    count: typeof record.count === "number" ? record.count : null,
    hasNext: "next" in record,
    hasPrevious: "previous" in record,
    resultsLength: results ? results.length : null,
    firstCustomerKeys:
      first && typeof first === "object" ? Object.keys(first) : null,
  };
}

const results = [];
for (const prefix of PREFIXES) {
  const attempt = await tryPrefix(prefix);
  results.push({
    prefix: attempt.prefix,
    status: attempt.status,
    summary: attempt.status >= 200 && attempt.status < 300
      ? summarize(attempt.json)
      : { errorKeys: attempt.json && typeof attempt.json === "object"
        ? Object.keys(attempt.json)
        : null },
  });
}

const ok = results.filter((row) => row.status >= 200 && row.status < 300);
console.log(JSON.stringify({ okPrefixes: ok.map((row) => row.prefix), results }, null, 2));
if (ok.length === 0) process.exit(2);
