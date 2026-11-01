-- Allow 'transient' in qa_alert_log.action (Systems QA Agent logs brief blips as transient).
-- Rollback: restore the original two-value check.
alter table public.qa_alert_log drop constraint if exists qa_alert_log_action_check;
alter table public.qa_alert_log add constraint qa_alert_log_action_check
  check (action = any (array['sent'::text, 'suppressed'::text, 'transient'::text]));
