# Owner API — bot/tool backend

Dedicated Cloudflare Worker. Steve never logs in. Incoming calls use a bot
API key. The Worker holds Lee's owner Supabase session (sealed in KV) and
proxies to the owner Edge Functions.

This is not the member web surface and does not use `ownerWeb` / TeamUp.

## Routes

All `POST`. Header: `Authorization: Bearer <OWNER_BOT_KEY>`.

| Path | Upstream |
|---|---|
| `/api/owner/current-pbs` | `owner-current-pbs` |
| `/api/owner/pb-frequency` | `owner-pb-frequency` (JSON body passed through) |
| `/api/owner/members` | `owner-member-names` (`{"refresh":true}` or `?refresh=1` to sync names) |

Missing key → 401. Wrong key → 403. Unprovisioned session → 503.

## One-time setup

1. Create KV: `npx wrangler kv namespace create OWNER_SESSION` and paste the
   id into `wrangler.jsonc`.
2. Secrets: `npx wrangler secret put OWNER_BOT_KEY`, `OWNER_SESSION_SECRET`
   (≥ 32 chars each), `SUPABASE_PUBLISHABLE_KEY`.
3. Provision Auth users (real emails, no TeamUp):

```bash
OWNER_LEE_EMAIL=... OWNER_STEVE_EMAIL=... node scripts/provision-owner-auth.mjs
```

That writes `scripts/.owner-auth.json` (gitignored). Confirm the JWT has
top-level `app_role=owner` (Custom Access Token Hook must be on) and that
`owner_surface_grants` returns a row.

4. Seal Lee's session into KV (Worker always uses Lee's session as the
   service identity):

```bash
cd src/client/web/owner-api
# OWNER_SESSION_SECRET in .dev.vars must match the Worker secret
bun run seal-session
npx wrangler kv key put lee --binding OWNER_SESSION --path .sealed-lee.txt
```

5. Deploy Edge Functions (`owner-current-pbs`, `owner-pb-frequency`,
   `owner-member-names`) and this Worker (`npm run deploy`).
6. TeamUp names: Steve generates an M2M token (see
   `docs/teamup-m2m-token-checklist.md`). Probe first:

```bash
TEAMUP_M2M_TOKEN=... node scripts/probe-teamup-customers.mjs
```

Then `npx supabase secrets set TEAMUP_M2M_TOKEN=...` (plus existing
`TEAMUP_OAUTH_PROVIDER_ID`). Daily cron on this Worker refreshes names at
05:00 UTC.

## Live refresh proof

```bash
node scripts/prove-owner-session-refresh.mjs
```

Same GoTrue `refresh_token` grant as iOS. Does not print tokens. Re-seal
KV afterwards because the proof rotates the stored refresh token.

## Tests

```bash
bun test src
```
