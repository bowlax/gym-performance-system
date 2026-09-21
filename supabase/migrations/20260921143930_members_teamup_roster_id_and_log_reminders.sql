-- TeamUp roster id on members (ProviderCustomerProfile id, not OAuth sub)
-- plus log-reminder opt-out and send ledger.

alter table members
    add column teamup_roster_id text;

alter table members
    add column log_reminder_email_opted_out_at timestamptz;

comment on column members.teamup_roster_id is
    'TeamUp GET /customers id (roster). Broker/name-sync owned via email match. Distinct from teamup_customer_id (OAuth sub). Devices must not PATCH.';

comment on column members.log_reminder_email_opted_out_at is
    'Set when the member unsubscribes from log-reminder emails. Null means subscribed. Members may clear this from Settings. Do not mix into staleness PATCHes.';

create unique index members_gym_teamup_roster_id_uidx
    on members (gym_id, teamup_roster_id)
    where teamup_roster_id is not null and deleted_at is null;

create table log_reminder_sends (
    id          uuid primary key default gen_random_uuid(),
    gym_id      uuid not null references gyms(id),
    member_id   uuid not null references members(id),
    for_date    date not null,
    kind        text not null default 'booked_unlogged',
    slot        text not null,
    sent_at     timestamptz not null default now(),
    unique (member_id, for_date, kind)
);

comment on table log_reminder_sends is
    'One row per member per London date a log-reminder email was sent. Unique on (member_id, for_date, kind) so later runs the same day cannot send again. Backoff counts distinct for_date values, not runs.';

create index log_reminder_sends_member_sent
    on log_reminder_sends (member_id, sent_at desc);

alter table log_reminder_sends enable row level security;

-- No authenticated policies: members do not read or write this table.
-- service_role bypasses RLS for the reminder job.

grant select, insert, update on public.log_reminder_sends to service_role;
