# Supabase — Gym Performance System

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (for `supabase start`)
- Node.js 18+ (for the Supabase CLI via npm)

## Install the Supabase CLI

From the repo root:

```bash
npm install
```

This installs the Supabase CLI as a dev dependency. Run it with `npx supabase` or `npm run supabase`.

Alternatively, install globally:

```bash
npm install -g supabase
```

## Initialise / link a project

If you have not linked this repo to a remote Supabase project:

```bash
npx supabase login
npx supabase link --project-ref <PROJECT_REF>
```

Local config lives in `supabase/config.toml`. Edge Functions live in `supabase/functions/`.

## Database migrations

**As of 2026-07-16**, `supabase/migrations/` is the applied source of truth on
the linked live project. New schema changes go through `npx supabase db push`.

### Provenance (why history looked empty)

The hosted project was initially set up by running SQL in the dashboard SQL
editor. Repo migration files were a parallel record, not what had been applied
via the CLI — so `schema_migrations` on live was empty even though tables
existed. On 2026-07-16 (issue #28 step 4), history was repaired (early versions
marked applied) and the pending migrations were pushed. Step 2’s
`exercise_resets` table and member staleness columns were found missing on live
at that point (never dashboard-applied) and were created by the push. Detail:
`docs/supabase-schema.md` § Migration history provenance.

```bash
npx supabase start          # local: runs all migrations on first start
npx supabase db push        # remote: apply pending migrations
```

## Token broker — local development

1. Create `supabase/.env.local` (do not commit) with:

   ```
   SUPABASE_URL=http://127.0.0.1:54321
   SERVICE_ROLE_KEY=<from supabase status>
   JWT_SIGNING_SECRET=<from supabase status>
   ```

   `SUPABASE_URL` is injected automatically on the hosted runtime; include it
   locally when using `supabase functions serve`. Custom secrets must not use
   the `SUPABASE_` prefix (reserved by the hosted runtime).

2. Start the local stack and serve the function:

   ```bash
   npx supabase start
   npx supabase functions serve token-broker --no-verify-jwt --env-file supabase/.env.local
   ```

3. Test with curl:

   ```bash
   curl -s -X POST 'http://127.0.0.1:54321/functions/v1/token-broker' \
     -H 'Content-Type: application/json' \
     -d '{
       "teamupToken": "stub-token",
       "deviceMemberId": "aaaaaaaa-0000-0000-0000-000000000001",
       "surface": "ios"
     }'
   ```

   `--no-verify-jwt` is required because callers authenticate with a TeamUp token, not a Supabase JWT.

### Path selection (stub vs real OAuth)

| Configuration | POST `teamupToken: "stub-token"` | GET `?oauth=authorize` |
|---------------|----------------------------------|-------------------------|
| No TeamUp OAuth env vars (local/dev) | **Stub path**: HS256 session mint | `404` — OAuth not configured |
| All four required OAuth vars set (prod) | **Rejected (403)** — no HS256 mint | Real TeamUp authorize redirect (PKCE) |
| OAuth vars set + POST with real TeamUp JWT | Auth-session ES256 path | N/A |

**Boundary:** HS256 session mint exists only when OAuth is **unconfigured**. Deployed prod (OAuth configured) refuses `stub-token`.

Required OAuth secrets (set together via `supabase secrets set`):

- `TEAMUP_OAUTH_CLIENT_ID`
- `TEAMUP_OAUTH_CLIENT_SECRET`
- `TEAMUP_OAUTH_REDIRECT_URI` — must include `?oauth=callback` (TeamUp redirects here with `code` and `state`)
- `TEAMUP_OAUTH_PROVIDER_ID` — Wolf gym provider id once registered
- `OAUTH_STATE_SECRET` — dedicated HMAC for OAuth `state` (not the project JWT secret)

Optional: `TEAMUP_OAUTH_SUCCESS_REDIRECT_URI`, `TEAMUP_OAUTH_SCOPE`, `TEAMUP_OAUTH_AUTHORIZE_URL`, `TEAMUP_OAUTH_TOKEN_URL`.

**Authorize (browser redirect):**

```bash
open 'http://127.0.0.1:54321/functions/v1/token-broker?oauth=authorize&deviceMemberId=aaaaaaaa-0000-0000-0000-000000000001&surface=memberWeb&returnUrl=http://localhost:5173/auth/callback'
```

After TeamUp login, the broker exchanges the code, establishes an Auth session (ES256), and redirects to `returnUrl` with `access_token` / `refresh_token` (or returns JSON if no redirect URI is configured).

## Token broker — deploy

Set secrets on the remote project, then deploy:

```bash
npx supabase secrets set \
  SERVICE_ROLE_KEY=<service-role-key> \
  OAUTH_STATE_SECRET=<random-dedicated-secret>

# JWT_SIGNING_SECRET is only needed for local/dev stub (OAuth unconfigured).
# On prod with OAuth configured it is unused for the real path; omit once stub is gone.

npx supabase functions deploy token-broker --no-verify-jwt
```

`SUPABASE_URL` is injected automatically in the hosted Edge Functions runtime.

## Type-check the function

Requires [Deno](https://deno.land/):

```bash
npm run functions:check
```
