-- members.auth_user_id — broker-owned link to auth.users (#17 Phase C)
--
-- Populated only by the token-broker (service role) when establishing a
-- Supabase Auth user for a TeamUp customer. Devices never write this column:
-- SyncPayloadMapper.memberSettingsPatch emits only staleness_* (+ sync
-- bookkeeping) and the Swift test memberSettingsPatchMapsStalenessOnly
-- asserts broker identity fields are absent from the PATCH body.

alter table members
    add column auth_user_id uuid unique;

comment on column members.auth_user_id is
    'Supabase auth.users.id for this member. Broker-owned; devices must not PATCH.';
