-- Members identity columns are broker-owned. Table-level UPDATE let any
-- authenticated session rewrite them on the caller's own row. Devices and the
-- member site only patch settings and sync bookkeeping.

revoke update on table public.members from authenticated;

grant update (
    staleness_enabled,
    staleness_periods,
    staleness_unit,
    log_reminder_email_opted_out_at,
    updated_at,
    synced_at,
    source_device_id
) on table public.members to authenticated;
