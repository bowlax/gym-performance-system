# Member Surface — Web

**Layer:** Client  
**Platform:** Web (React / TanStack Start)  
**Phase:** 2 — Active  
**Status:** Pre-release member surface for Android and other web users

## Purpose

The web experience for gym members. Covers session logging, PB tracking, progression viewing, and board display. Connects to the same Supabase central store and Edge Functions as the iOS app.

## Backend integration

- **Reads and simple writes** — direct Supabase client calls under RLS (broker-minted JWT)
- **PB logging** — `log-set` Edge Function (`/functions/v1/log-set`)
- **Authentication** — `token-broker` Edge Function (`/functions/v1/token-broker`); currently uses a stub TeamUp broker for pre-release testing

## Environment variables

Set these for local development (see `.env.example`). Do not commit files containing real values.

| Variable | Purpose |
|----------|---------|
| `GYMPERF_SUPABASE_URL` | Supabase project API URL |
| `GYMPERF_SUPABASE_PUBLISHABLE_KEY` | Supabase publishable (anon) key — client-safe; never use the secret/service role key here |
| `TEST_DEVICE_MEMBER_ID` | Device member UUID for the stub token broker (pre-release only) |

Edge function URLs are derived from `GYMPERF_SUPABASE_URL`:

- `{SUPABASE_URL}/functions/v1/token-broker`
- `{SUPABASE_URL}/functions/v1/log-set`

## Local development

```bash
cd src/client/web/member-surface
cp .env.example .env.local   # fill in values
bun install                  # or npm install
bun run dev
```

## Design system

Visual tokens are defined in `docs/design-system.md` at the repo root. The web implementation values section pins fixed hex colours and spacing for cross-platform parity with iOS.

Refer to `docs/gym-performance-system-design.md` for full architectural context.
