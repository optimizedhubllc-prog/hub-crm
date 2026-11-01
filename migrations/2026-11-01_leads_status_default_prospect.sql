-- leads.status defaulted to 'New Lead', which leads_status_check does not allow
-- (allowed: Prospect, Application, Processing, Closing, Dead), so any insert without
-- an explicit status failed. In the CRM, 'New Lead' is a sub-status of 'Prospect'.
-- Default status to 'Prospect' and sub_status to 'New Lead'. Existing rows untouched.
-- Rollback: alter table public.leads alter column status set default 'New Lead';
--           alter table public.leads alter column sub_status drop default;
alter table public.leads alter column status set default 'Prospect';
alter table public.leads alter column sub_status set default 'New Lead';
