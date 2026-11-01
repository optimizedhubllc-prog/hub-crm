-- Hub Outreach Tracker (tools.optimizedhub.com/outreach). Applied 2026-11-01.
-- Each row belongs to the signed-in owner/admin who created it. Nobody else can read or write it.
create table if not exists public.outreach_contacts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  company text default '',
  nmls text default '',
  channel text not null default 'text' check (channel in ('text','email','linkedin','call','in-person')),
  lang text not null default 'en' check (lang in ('en','es')),
  status text not null default 'queued' check (status in ('queued','messaged','followed','replied','demo','pilot','dead')),
  note text default '',
  first_sent date,
  follow_sent date,
  replied_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists outreach_contacts_owner_idx on public.outreach_contacts(owner_id);

create or replace function public.am_i_owner_or_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select p.role in ('owner','admin') from public.profiles p where p.id = auth.uid()), false)
$$;
revoke all on function public.am_i_owner_or_admin() from public;
grant execute on function public.am_i_owner_or_admin() to authenticated;

create or replace function public.outreach_touch() returns trigger language plpgsql as $$
begin new.updated_at = now(); new.owner_id = old.owner_id; return new; end $$;
drop trigger if exists trg_outreach_touch on public.outreach_contacts;
create trigger trg_outreach_touch before update on public.outreach_contacts
  for each row execute function public.outreach_touch();

alter table public.outreach_contacts enable row level security;
revoke all on public.outreach_contacts from anon;
grant select, insert, update, delete on public.outreach_contacts to authenticated;

drop policy if exists "outreach own rows" on public.outreach_contacts;
create policy "outreach own rows" on public.outreach_contacts for all to authenticated
  using (owner_id = auth.uid() and public.am_i_owner_or_admin())
  with check (owner_id = auth.uid() and public.am_i_owner_or_admin());
