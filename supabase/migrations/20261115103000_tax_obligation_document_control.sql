alter table public.tax_obligations
  add column if not exists prepared_at timestamptz,
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid,
  add column if not exists submitted_at timestamptz,
  add column if not exists submission_reference text,
  add column if not exists payment_reference text,
  add column if not exists payment_proof_path text,
  add column if not exists payment_recorded_at timestamptz,
  add column if not exists payment_amount numeric(14,2),
  add column if not exists payment_date date;

create table if not exists public.tax_obligation_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  obligation_id uuid not null references public.tax_obligations(id) on delete cascade,
  event_type text not null check (event_type in ('prepared','reviewed','submission_recorded','payment_recorded','note','evidence_uploaded')),
  event_date timestamptz not null default now(),
  actor_user_id uuid,
  reference text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists tax_obligation_events_tenant_obligation_idx
  on public.tax_obligation_events(tenant_id, obligation_id, event_date desc);
alter table public.tax_obligation_events enable row level security;
drop policy if exists tax_obligation_events_select_tenant on public.tax_obligation_events;
create policy tax_obligation_events_select_tenant on public.tax_obligation_events
 for select to authenticated using (
   exists (select 1 from public.tenant_users tu where tu.tenant_id=tax_obligation_events.tenant_id and tu.user_id=(select auth.uid()))
 );
drop policy if exists tax_obligation_events_insert_tenant on public.tax_obligation_events;
grant select, insert, update on public.tax_obligation_events to authenticated;
create policy tax_obligation_events_insert_tenant on public.tax_obligation_events
 for insert to authenticated with check (
   exists (select 1 from public.tenant_users tu where tu.tenant_id=tax_obligation_events.tenant_id and tu.user_id=(select auth.uid()) and tu.role in ('owner','admin','accountant'))
 );
drop policy if exists tax_obligation_events_update_tenant on public.tax_obligation_events;
create policy tax_obligation_events_update_tenant on public.tax_obligation_events
 for update to authenticated using (
   exists (select 1 from public.tenant_users tu where tu.tenant_id=tax_obligation_events.tenant_id and tu.user_id=(select auth.uid()) and tu.role in ('owner','admin','accountant'))
 ) with check (
   exists (select 1 from public.tenant_users tu where tu.tenant_id=tax_obligation_events.tenant_id and tu.user_id=(select auth.uid()) and tu.role in ('owner','admin','accountant'))
 );

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('tax-obligation-evidence','tax-obligation-evidence',false,10485760,
 array['application/pdf','image/jpeg','image/png'])
on conflict (id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists tax_evidence_read_tenant on storage.objects;
create policy tax_evidence_read_tenant on storage.objects for select to authenticated
 using (bucket_id='tax-obligation-evidence' and exists (
   select 1 from public.tenant_users tu
   where tu.tenant_id::text=(storage.foldername(name))[1] and tu.user_id=(select auth.uid()) and tu.role in ('owner','admin','accountant')
 ));
drop policy if exists tax_evidence_insert_tenant on storage.objects;
create policy tax_evidence_insert_tenant on storage.objects for insert to authenticated
 with check (bucket_id='tax-obligation-evidence' and exists (
   select 1 from public.tenant_users tu
   where tu.tenant_id::text=(storage.foldername(name))[1] and tu.user_id=(select auth.uid())
 ));
