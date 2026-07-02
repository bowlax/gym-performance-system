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

The hosted Supabase project was initially set up by running SQL directly in the
dashboard SQL editor (schema, RLS policies, Wolf gym row, and exercise seed).
The files in `supabase/migrations/` capture that state so new environments are
reproducible from source:

1. `20260702170000_initial_schema.sql` — tables and indexes
2. `20260702170001_row_level_security.sql` — RLS enablement and policies
3. `20260702170002_wolf_gym_seed.sql` — Wolf gym and 19 exercises (idempotent)

**Do not re-apply these to the existing cloud project** — it already has this
state. Use `npx supabase db reset` locally, or apply to a fresh project / new
environment:

```bash
npx supabase start          # local: runs all migrations on first start
npx supabase db push        # remote: only on a new or empty database
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

## Token broker — deploy

Set secrets on the remote project, then deploy:

```bash
npx supabase secrets set \
  SERVICE_ROLE_KEY=<service-role-key> \
  JWT_SIGNING_SECRET=<jwt-secret>

npx supabase functions deploy token-broker --no-verify-jwt
```

`SUPABASE_URL` is injected automatically in the hosted Edge Functions runtime.

## Type-check the function

Requires [Deno](https://deno.land/):

```bash
npm run functions:check
```
