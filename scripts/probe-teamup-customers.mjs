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
 * Prints Object.keys of the first customer, pagination totals, and
 * name-related fields for two known ids only — not emails or the roster.
 */

const PROVIDER_ID = process.env.TEAMUP_PROVIDER_ID?.trim() || "5404319";
const TOKEN = process.env.TEAMUP_M2M_TOKEN?.trim();
const PREFIXES = ["Bearer", "Token", "JWT"];
const LOOKUP_IDS = ["2809647", "2293073"];
const PAGE_SIZE = 100;

if (!TOKEN) {
  console.error("Set TEAMUP_M2M_TOKEN");
  process.exit(1);
}

function nameFields(record) {
  if (!record || typeof record !== "object") return null;
  const out = { id: record.id ?? null };
  for (const key of Object.keys(record)) {
    if (/name/i.test(key)) out[key] = record[key];
  }
  return out;
}

async function teamUpGet(prefix, pathAndQuery) {
  const url = new URL(pathAndQuery, "https://goteamup.com/api/v2/");
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
    nextIsNull: record.next == null,
    hasPrevious: "previous" in record,
    previousIsNull: record.previous == null,
    resultsLength: results ? results.length : null,
    firstCustomerKeys:
      first && typeof first === "object" ? Object.keys(first) : null,
    firstCustomerNameKeys:
      first && typeof first === "object"
        ? Object.keys(first).filter((key) => /name/i.test(key))
        : null,
  };
}

async function paginateAll(prefix) {
  const pages = [];
  const lookups = {};
  let page = 1;
  let declaredCount = null;

  while (page <= 50) {
    const attempt = await teamUpGet(
      prefix,
      `customers?page=${page}&page_size=${PAGE_SIZE}`,
    );
    if (attempt.status < 200 || attempt.status >= 300 || !attempt.json) {
      pages.push({
        page,
        status: attempt.status,
        errorKeys:
          attempt.json && typeof attempt.json === "object"
            ? Object.keys(attempt.json)
            : null,
      });
      break;
    }

    const json = attempt.json;
    const results = Array.isArray(json.results) ? json.results : [];
    if (typeof json.count === "number") declaredCount = json.count;

    for (const row of results) {
      if (!row || typeof row !== "object") continue;
      const id = row.id == null ? null : String(row.id);
      if (id && LOOKUP_IDS.includes(id)) lookups[id] = nameFields(row);
    }

    pages.push({
      page,
      status: attempt.status,
      resultsLength: results.length,
      nextIsNull: json.next == null,
      previousIsNull: json.previous == null,
    });

    if (!json.next || results.length === 0) break;
    page += 1;
  }

  return {
    declaredCount,
    pagesFetched: pages.length,
    summedResults: pages.reduce(
      (sum, row) => sum + (typeof row.resultsLength === "number" ? row.resultsLength : 0),
      0,
    ),
    pages,
    lookups,
  };
}

async function retrieveById(prefix, id) {
  const attempt = await teamUpGet(prefix, `customers/${id}`);
  if (attempt.status < 200 || attempt.status >= 300) {
    return {
      id,
      status: attempt.status,
      errorKeys:
        attempt.json && typeof attempt.json === "object"
          ? Object.keys(attempt.json)
          : null,
    };
  }
  const json = attempt.json;
  const record = json && typeof json === "object" && json.id != null
    ? json
    : json && typeof json === "object" && json.results
    ? json
    : json;
  return {
    id,
    status: attempt.status,
    topLevelKeys: json && typeof json === "object" ? Object.keys(json) : null,
    nameFields: nameFields(record),
  };
}

const prefixResults = [];
for (const prefix of PREFIXES) {
  const attempt = await teamUpGet(prefix, "customers?page=1&page_size=1");
  prefixResults.push({
    prefix: attempt.prefix,
    status: attempt.status,
    summary: attempt.status >= 200 && attempt.status < 300
      ? summarize(attempt.json)
      : {
        errorKeys: attempt.json && typeof attempt.json === "object"
          ? Object.keys(attempt.json)
          : null,
      },
  });
}

const ok = prefixResults.filter((row) => row.status >= 200 && row.status < 300);
const report = {
  okPrefixes: ok.map((row) => row.prefix),
  prefixResults,
};

if (ok.length > 0) {
  const prefix = ok[0].prefix;
  report.workingPrefix = prefix;
  report.pagination = await paginateAll(prefix);
  report.retrieveById = [];
  for (const id of LOOKUP_IDS) {
    report.retrieveById.push(await retrieveById(prefix, id));
  }
}

console.log(JSON.stringify(report, null, 2));
if (ok.length === 0) process.exit(2);
