-- Semi-automatic outreach: lead pool, AI drafts, auto-email tracking, reply/opt-out.
alter table public.outreach_contacts
  add column if not exists email text, add column if not exists phone text, add column if not exists source text,
  add column if not exists draft_subject text, add column if not exists draft_message text, add column if not exists draft_followup text,
  add column if not exists draft_generated_at timestamptz, add column if not exists auto_email boolean not null default false,
  add column if not exists email_opener_sent_at timestamptz, add column if not exists email_followup_sent_at timestamptz,
  add column if not exists email_message_id text, add column if not exists email_thread_id text, add column if not exists email_last_error text,
  add column if not exists replied_ts timestamptz, add column if not exists reply_snippet text,
  add column if not exists do_not_email boolean not null default false;
alter table public.outreach_contacts drop constraint if exists outreach_contacts_status_check;
alter table public.outreach_contacts add constraint outreach_contacts_status_check
  check (status = any (array['pool','queued','messaged','followed','replied','demo','pilot','dead']));
create index if not exists outreach_contacts_pool_idx on public.outreach_contacts (status, created_at);
create index if not exists outreach_contacts_email_idx on public.outreach_contacts (lower(email));
