-- Issue #28: undated manual PBs — achieved_at is optional.
-- Undated entries count toward lifetime only (never current, never history).

alter table personal_bests
    alter column achieved_at drop not null;
