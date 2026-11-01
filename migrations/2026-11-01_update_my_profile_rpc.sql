-- Self-service profile save: only full_name, nmls_id, settings on the caller's own row. Never role/access/status/brokerage.
alter table public.profiles add column if not exists nmls_id text;
create or replace function public.update_my_profile(p_full_name text default null, p_nmls_id text default null, p_settings jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if p_full_name is not null and (length(trim(p_full_name)) = 0 or length(p_full_name) > 120) then raise exception 'Full name must be 1-120 characters'; end if;
  if p_nmls_id is not null and p_nmls_id <> '' and p_nmls_id !~ '^[0-9]{1,12}$' then raise exception 'NMLS # must be digits only'; end if;
  if p_settings is not null and (jsonb_typeof(p_settings) <> 'object' or length(p_settings::text) > 20000) then raise exception 'Invalid settings'; end if;
  update public.profiles set
    full_name = coalesce(nullif(trim(p_full_name),''), full_name),
    nmls_id = case when p_nmls_id is null then nmls_id else nullif(p_nmls_id,'') end,
    settings = coalesce(p_settings, settings)
  where id = auth.uid();
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Profile not found'; end if;
end $$;
revoke all on function public.update_my_profile(text,text,jsonb) from public, anon;
grant execute on function public.update_my_profile(text,text,jsonb) to authenticated;
