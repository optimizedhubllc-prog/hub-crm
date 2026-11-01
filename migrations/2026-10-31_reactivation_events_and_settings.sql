-- DRAFT for Pedro's review. NOT applied. Run in Supabase SQL editor only after review.
-- Purpose: power the Today results strip + Campaigns activity feed, and sync Settings across devices.

-- 1) Event log written by n8n (service role) for every reactivation touch/outcome.
create table if not exists public.reactivation_events (
  id            uuid primary key default gen_random_uuid(),
  campaign_id   uuid references public.reactivation_campaigns(id) on delete cascade,
  lead_id       uuid references public.leads(id) on delete set null,
  owner_lo      uuid not null references auth.users(id) on delete cascade,
  brokerage_id  uuid,
  event_type    text not null check (event_type in
                  ('message_sent','reply_received','call_booked','opted_out','converted','funded')),
  channel       text check (channel in ('sms','email','call','calendar')),
  meta          jsonb not null default '{}'::jsonb,   -- no message bodies / PII beyond what's needed
  occurred_at   timestamptz not null default now()
);
create index if not exists reactivation_events_owner_time_idx on public.reactivation_events (owner_lo, occurred_at desc);
create index if not exists reactivation_events_campaign_idx  on public.reactivation_events (campaign_id);

alter table public.reactivation_events enable row level security;

-- LOs read their own events. Writes come only from n8n using the service role (bypasses RLS),
-- so no insert/update/delete policies for authenticated users.
create policy "reactivation_events_select_own"
  on public.reactivation_events for select to authenticated
  using (owner_lo = auth.uid());

-- Optional: brokers read their brokerage's events (mirror whatever rule reactivation_campaigns uses).
-- create policy "reactivation_events_select_brokerage" on public.reactivation_events for select to authenticated
--   using (brokerage_id = (select brokerage_id from public.profiles where id = auth.uid())
--          and (select role from public.profiles where id = auth.uid()) = 'broker');

-- 2) Per-user settings + NMLS on profiles (UI falls back to localStorage until these exist).
alter table public.profiles add column if not exists settings jsonb not null default '{}'::jsonb;
alter table public.profiles add column if not exists nmls_id text;
-- Confirm the existing profiles UPDATE policy lets a user update their own row (id = auth.uid()),
-- and that it does NOT let users change role / product_tier / brokerage_id (column privileges or a trigger).

-- n8n insert example (service role):
-- insert into reactivation_events (campaign_id, lead_id, owner_lo, brokerage_id, event_type, channel)
-- values (:campaign_id, :lead_id, :owner_lo, :brokerage_id, 'call_booked', 'calendar');

-- 3) Lead status at campaign start, so the Conversion Tracker only counts leads that were Dead
--    when the campaign began. Whatever creates reactivation_campaigns rows should set this
--    (e.g. start_status = leads.status at insert time).
alter table public.reactivation_campaigns add column if not exists start_status text;
