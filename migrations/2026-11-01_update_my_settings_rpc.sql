-- Lets a signed-in user save only their own profiles.settings JSON (profiles has no self-UPDATE policy).
create or replace function public.update_my_settings(p_settings jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' or length(p_settings::text) > 20000 then raise exception 'invalid settings'; end if;
  update public.profiles set settings = p_settings where id = auth.uid();
  return p_settings;
end $$;
revoke all on function public.update_my_settings(jsonb) from public, anon;
grant execute on function public.update_my_settings(jsonb) to authenticated;
