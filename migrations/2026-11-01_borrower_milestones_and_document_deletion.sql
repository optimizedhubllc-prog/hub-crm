-- Borrower milestone texts (EN/ES) + document deletion (manual + 30-day auto) + deletion log. Applied 2026-11-01.

-- A) Borrower milestone texts
alter table public.milestone_templates add column if not exists borrower_template_es text;
alter table public.leads add column if not exists milestone_texts_borrower boolean not null default true; -- per-file toggle
-- per-LO toggle: profiles.settings->>'borrower_milestone_texts' = 'false' turns borrower texts off for that LO
alter table public.milestone_events add column if not exists borrower_send_status text;
alter table public.milestone_events add column if not exists borrower_recipient_phone text;
alter table public.milestone_events add column if not exists borrower_message_sent text;
alter table public.milestone_events add column if not exists borrower_quo_activity_id text;
alter table public.milestone_events add column if not exists borrower_error_message text;

update public.milestone_templates t set notify_borrower = true, borrower_template = v.en, borrower_template_es = v.es
from (values
 ('Application',   'Hi {{first_name}}, this is {{lo_name}}. Your mortgage application is in and we''re reviewing it now. I''ll keep you posted at each step.',
                   'Hola {{first_name}}, le saluda {{lo_name}}. Recibimos su solicitud de hipoteca y la estamos revisando. Le mantendré informado en cada paso.'),
 ('Pre-Approved',  'Good news {{first_name}}! You''re pre-approved. {{lo_name}} will follow up with next steps.',
                   '¡Buenas noticias, {{first_name}}! Usted está preaprobado. {{lo_name}} le contactará con los próximos pasos.'),
 ('Under Contract','Congrats {{first_name}}, you''re under contract! {{lo_name}} is moving your loan forward and will reach out if anything is needed.',
                   '¡Felicidades, {{first_name}}, ya tiene contrato! {{lo_name}} está avanzando con su préstamo y le avisará si necesita algo.'),
 ('Processing',    'Hi {{first_name}}, your loan is now in processing. If we need any documents, {{lo_name}} will let you know.',
                   'Hola {{first_name}}, su préstamo está en procesamiento. Si necesitamos algún documento, {{lo_name}} le avisará.'),
 ('Underwriting',  'Hi {{first_name}}, your file is with underwriting now. {{lo_name}} will update you as soon as we hear back.',
                   'Hola {{first_name}}, su expediente está en suscripción (underwriting). {{lo_name}} le avisará en cuanto tengamos respuesta.'),
 ('Clear to Close','Great news {{first_name}}: you''re CLEAR TO CLOSE! {{lo_name}} will confirm your closing details.',
                   '¡Excelente noticia, {{first_name}}: su préstamo está aprobado para cierre! {{lo_name}} le confirmará los detalles del cierre.'),
 ('Funded',        'Congratulations {{first_name}}, your loan has funded! Thank you for working with {{lo_name}}.',
                   '¡Felicidades, {{first_name}}, su préstamo ha sido fondeado! Gracias por trabajar con {{lo_name}}.')
) as v(status, en, es)
where t.brokerage_id is null and t.status = v.status;

-- B) File closed/dead timestamp for retention
alter table public.leads add column if not exists file_closed_at timestamptz;
create or replace function public.set_file_closed_at() returns trigger language plpgsql as $$
declare closed boolean := (new.status = 'Dead' or new.sub_status in ('Funded','Post-Close','Dead'));
begin
  if closed and (tg_op = 'INSERT' or old.file_closed_at is null) then new.file_closed_at := coalesce(new.file_closed_at, now());
  elsif not closed then new.file_closed_at := null; end if;
  return new;
end $$;
drop trigger if exists trg_set_file_closed_at on public.leads;
create trigger trg_set_file_closed_at before insert or update of status, sub_status on public.leads
  for each row execute function public.set_file_closed_at();
update public.leads set file_closed_at = coalesce(updated_at, now())
  where file_closed_at is null and (status = 'Dead' or sub_status in ('Funded','Post-Close','Dead'));

-- Deletion log: metadata only, never document contents or names.
create table if not exists public.document_deletion_log (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null,
  brokerage_id uuid,
  owner_lo uuid,
  deleted_at timestamptz not null default now(),
  trigger_type text not null check (trigger_type in ('lo_manual','auto_closed_30d','auto_dead_30d')),
  triggered_by uuid,
  file_status text,
  file_count integer not null default 0
);
create index if not exists document_deletion_log_lead_idx on public.document_deletion_log(lead_id);
alter table public.document_deletion_log enable row level security;
revoke all on public.document_deletion_log from anon;
grant select on public.document_deletion_log to authenticated;
drop policy if exists "deletion_log_select" on public.document_deletion_log;
create policy "deletion_log_select" on public.document_deletion_log for select to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid()
    and (p.role in ('owner','admin') or p.brokerage_id = document_deletion_log.brokerage_id or document_deletion_log.owner_lo = p.id)));
drop policy if exists "require active access" on public.document_deletion_log;
create policy "require active access" on public.document_deletion_log as restrictive for all to authenticated
  using (public.am_i_active()) with check (public.am_i_active());
-- Inserts come only from the n8n deletion workflow (service role); no insert/update/delete policy for users.
