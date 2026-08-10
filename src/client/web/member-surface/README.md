# Member Surface — Web

**Layer:** Client  
**Platform:** Web (React / TanStack Start on Cloudflare Workers SSR)  
**Phase:** 2 — Active  
**Status:** Deployed member surface (`gymperf-member-web`) for Android and other web users

## Purpose

The web experience for gym members. Covers session logging, PB tracking, progression viewing, and board display. Connects to the same Supabase central store and Edge Functions as the iOS app.

## Backend integration

- **Reads and simple writes** — direct Supabase client calls under RLS (Auth-session JWT from the broker)
- **PB logging** — `log-set` Edge Function (`/functions/v1/log-set`)
- **Progression actions** — `add-manual-pb`, `reset-current-pb`, `delete-personal-best`
- **Authentication** — real TeamUp OAuth via `token-broker` (`/functions/v1/token-broker?oauth=authorize` …). Callback returns Auth session tokens; the Worker seals them into an **httpOnly** cookie (`gp_auth`, sealed with `SESSION_SECRET`). The browser does **not** hold the JWT in the clear. The client obtains a short-lived access token via `GET /api/auth/session`; `POST /api/auth/signout` clears the cookie

## Environment variables

### Local development

Copy `.env.example` → `.env.local` and `.dev.vars.example` → `.dev.vars`. Do not commit real values.

| Variable | Where | Purpose |
|----------|--------|---------|
| `GYMPERF_SUPABASE_URL` | `.env.local` | Supabase project API URL (injected into the client bundle at build/dev time) |
| `GYMPERF_SUPABASE_PUBLISHABLE_KEY` | `.env.local` | Supabase publishable (anon) key — client-safe; never use the secret/service role key here |
| `SESSION_SECRET` | `.dev.vars` (local) / Worker secret (prod) | Seals the `gp_auth` httpOnly cookie (≥ 32 chars). **Never** bake into the client bundle or put in plaintext `[vars]` |
| `GYMPERF_USE_STUB_BROKER` / `TEST_DEVICE_MEMBER_ID` | `.env.local` (optional) | **Local/dev only** — mint without TeamUp OAuth. Forbidden in production builds |

Edge function URLs are derived from `GYMPERF_SUPABASE_URL`:

- `{SUPABASE_URL}/functions/v1/token-broker`
- `{SUPABASE_URL}/functions/v1/log-set`
- `{SUPABASE_URL}/functions/v1/add-manual-pb`
- `{SUPABASE_URL}/functions/v1/reset-current-pb`
- `{SUPABASE_URL}/functions/v1/delete-personal-best`

## Local development

```bash
cd src/client/web/member-surface
cp .env.example .env.local       # GYMPERF_SUPABASE_*
cp .dev.vars.example .dev.vars   # SESSION_SECRET
bun install                      # or npm install
bun run dev
```

## Deploy (Cloudflare Workers)

Worker name: `gymperf-member-web` (`wrangler.jsonc`). Nitro preset `cloudflare-module`.

```bash
cd src/client/web/member-surface
npm run deploy   # build && wrangler deploy
```

**Build-time env (GYMPERF_SUPABASE_*):** Vite/`gymPerfEnvDefinePlugin` injects these into the client bundle at build time. For Cloudflare Workers Builds (or any CI that runs `npm run build` then deploy), set `GYMPERF_SUPABASE_URL` and `GYMPERF_SUPABASE_PUBLISHABLE_KEY` as **build environment variables / secrets** in the Workers Builds project settings (or the CI env) so the production bundle is not empty.

**Runtime secret (SESSION_SECRET):**

```bash
npx wrangler secret put SESSION_SECRET
```

Must be ≥ 32 characters. Used only on the Worker to seal/unseal `gp_auth` — not available to the browser.

Live workers.dev URL pattern: `https://gymperf-member-web.<account>.workers.dev` (also linked from `docs/landing/`).

## Design system

Visual tokens are defined in `docs/design-system.md` at the repo root. The web implementation values section pins fixed hex colours and spacing for cross-platform parity with iOS.

Refer to `docs/gym-performance-system-design.md` for full architectural context.
