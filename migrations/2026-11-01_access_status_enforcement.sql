-- DRAFT — NOT APPLIED. Access enforcement for Hub CRM.
-- Adds profiles.access_status and RESTRICTIVE RLS policies so suspended users
-- cannot read/write lead or campaign data. Owners/admins are always exempt.
-- Restrictive policies are AND-ed with existing permissive ones, so nothing
-- that works today changes for active users.

begin;

alter table public.profiles
  add column if not exists access_status text not null default 'active',
  add column if not exists access_status_reason text,
  add column if not exists access_status_changed_at timestamptz;

alter table public.profiles drop constraint if exists profiles_access_status_check;
alter table public.profiles
  add constraint profiles_access_status_check check (access_status in ('active','suspended'));

-- Owners/admins can never be suspended (protects Pedro's account).
create or replace function public.protect_admin_access_status()
returns trigger language plpgsql as $$
begin
  if new.role in ('owner','admin') then
    new.access_status := 'active';
  end if;
  if new.access_status is distinct from old.access_status then
    new.access_status_changed_at := now();
  end if;
  return new;
end $$;

drop trigger if exists trg_protect_admin_access_status on public.profiles;
create trigger trg_protect_admin_access_status
  before update on public.profiles
  for each row execute function public.protect_admin_access_status();

-- SECURITY DEFINER so it can read profiles without recursing through RLS.
create or replace function public.am_i_active()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select p.role in ('owner','admin') or p.access_status = 'active'
       from public.profiles p where p.id = auth.uid()),
    false)
$$;
revoke all on function public.am_i_active() from public;
grant execute on function public.am_i_active() to authenticated;

-- Restrictive policies on business data tables.
do $$
declare t text;
begin
  foreach t in array array[
    'leads','tasks','contacts','reactivation_campaigns','documents',
    'milestone_events','sent_letters','letter_templates','reactivation_events'
  ] loop
    if to_regclass('public.'||t) is not null then
      execute format('drop policy if exists "require active access" on public.%I', t);
      execute format(
        'create policy "require active access" on public.%I as restrictive for all to authenticated using (public.am_i_active()) with check (public.am_i_active())', t);
    end if;
  end loop;
end $$;

-- Audit log for the n8n access-sync job.
create table if not exists public.access_status_log (
  id bigserial primary key,
  profile_id uuid references public.profiles(id) on delete set null,
  email text,
  old_status text,
  new_status text,
  reason text,
  notion_status text,
  notion_tier text,
  created_at timestamptz not null default now()
);
alter table public.access_status_log enable row level security;
drop policy if exists "owners read access log" on public.access_status_log;
create policy "owners read access log" on public.access_status_log
  for select to authenticated using (public.am_i_owner() or public.am_i_admin());

commit;

-- Rollback:
-- do $$ declare t text; begin foreach t in array array['leads','tasks','contacts','reactivation_campaigns','documents','milestone_events','sent_letters','letter_templates','reactivation_events'] loop
--   if to_regclass('public.'||t) is not null then execute format('drop policy if exists "require active access" on public.%I', t); end if; end loop; end $$;
-- drop function if exists public.am_i_active(); drop trigger if exists trg_protect_admin_access_status on public.profiles;
-- drop function if exists public.protect_admin_access_status(); drop table if exists public.access_status_log;
-- alter table public.profiles drop column if exists access_status, drop column if exists access_status_reason, drop column if exists access_status_changed_at;
