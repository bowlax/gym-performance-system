-- members.teamup_email — JWT `email` captured at TeamUp connect/reconnect.
-- Join key for M2M GET /customers?query=<email> → display_name. Broker-owned.
-- Null means the member has never connected under this capture, TeamUp omitted
-- email on the token, or the account has no email (family dependants). Those
-- rows keep display_name default 'Member'.

alter table members
    add column teamup_email text;

comment on column members.teamup_email is
    'TeamUp customer email from the OAuth JWT at connect. Broker-owned; devices must not PATCH. Null members stay unnamed.';

create unique index members_gym_teamup_email_uidx
    on members (gym_id, teamup_email)
    where teamup_email is not null and deleted_at is null;
