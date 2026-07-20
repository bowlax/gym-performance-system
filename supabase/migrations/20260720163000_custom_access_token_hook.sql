-- Custom Access Token Hook (Phase A / #17)
--
-- Postgres function only. NOT registered here.
-- Enable later via Dashboard → Authentication → Hooks → Custom Access Token
-- (URI: pg-functions://postgres/public/custom_access_token_hook).
-- That registration is also the kill switch: disable there if the hook
-- misbehaves.
--
-- Behaviour notes:
-- - Fires on EVERY Supabase Auth-issued access token, including token_refresh.
-- - Fails CLOSED: any error/timeout from the hook aborts token minting
--   project-wide for Auth-issued JWTs. Keep this function pure and fast
--   (~2s Postgres hook budget).
-- - Does NOT affect the interim HS256 stub path (token-broker hand-mints
--   with JWT_SIGNING_SECRET and never goes through GoTrue issuance).
-- - Reads member_id / gym_id / app_role from draft claims.app_metadata and
--   promotes them to TOP-LEVEL claims so existing RLS
--   (auth.jwt() ->> 'member_id' | 'gym_id' | 'app_role') stays unchanged.
-- - Missing metadata fields are omitted (not errored). Incomplete metadata
--   yields a valid Auth session whose RLS simply denies data until claims
--   are set — never lock out token issuance.

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
as $$
declare
  claims jsonb;
  meta jsonb;
  claim_value text;
begin
  claims := coalesce(event->'claims', '{}'::jsonb);
  meta := coalesce(claims->'app_metadata', '{}'::jsonb);

  -- Promote only when present and non-empty. Omit otherwise (no raise).
  -- Do not touch claims.role — PostgREST session role stays "authenticated".
  claim_value := meta->>'member_id';
  if claim_value is not null and claim_value <> '' then
    claims := jsonb_set(claims, '{member_id}', to_jsonb(claim_value), true);
  end if;

  claim_value := meta->>'gym_id';
  if claim_value is not null and claim_value <> '' then
    claims := jsonb_set(claims, '{gym_id}', to_jsonb(claim_value), true);
  end if;

  claim_value := meta->>'app_role';
  if claim_value is not null and claim_value <> '' then
    claims := jsonb_set(claims, '{app_role}', to_jsonb(claim_value), true);
  end if;

  -- Return { claims: ... } so GoTrue finds the required top-level key.
  -- Base claims (iss, aud, exp, iat, sub, role, aal, session_id, email,
  -- phone, is_anonymous, …) remain intact on the claims object.
  return jsonb_build_object('claims', claims);
end;
$$;

grant usage on schema public to supabase_auth_admin;

grant execute
  on function public.custom_access_token_hook(jsonb)
  to supabase_auth_admin;

revoke execute
  on function public.custom_access_token_hook(jsonb)
  from authenticated, anon, public;
