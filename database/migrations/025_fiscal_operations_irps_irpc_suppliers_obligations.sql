begin;
create table if not exists public.suppliers (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 name text not null,
 nuit varchar(20),
 address text,
 email text,
 phone text,
 tax_status text,
 active boolean not null default true,
 created_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists suppliers_tenant_name_idx on public.suppliers(tenant_id,name);
create table if not exists public.purchase_invoices (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 supplier_id uuid not null references public.suppliers(id) on delete restrict,
 supplier_invoice_number text not null,
 document_type text not null default 'FT' check(document_type in ('FT','FR','VD','NC','ND','OTHER')),
 issue_date date not null,
 received_date date not null default current_date,
 due_date date,
 currency char(3) not null default 'MZN',
 exchange_rate numeric(18,6) not null default 1 check(exchange_rate>0),
 description text,
 taxable_base numeric(18,2) not null default 0 check(taxable_base>=0),
 vat_rate numeric(6,3) not null default 0 check(vat_rate>=0 and vat_rate<=100),
 vat_amount numeric(18,2) not null default 0 check(vat_amount>=0),
 exempt_amount numeric(18,2) not null default 0 check(exempt_amount>=0),
 non_deductible_vat numeric(18,2) not null default 0 check(non_deductible_vat>=0),
 deductible_vat numeric(18,2) not null default 0 check(deductible_vat>=0),
 total_amount numeric(18,2) not null default 0 check(total_amount>=0),
 deduction_status text not null default 'pending' check(deduction_status in ('pending','eligible','partially_eligible','ineligible','reviewed')),
 document_reference text,
 storage_path text,
 notes text,
 status text not null default 'recorded' check(status in ('recorded','paid','cancelled')),
 created_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,supplier_id,supplier_invoice_number,issue_date),
 check(deductible_vat+non_deductible_vat<=vat_amount+0.01)
);
create index if not exists purchase_invoices_tenant_date_idx on public.purchase_invoices(tenant_id,issue_date desc);
create index if not exists purchase_invoices_supplier_id_idx on public.purchase_invoices(supplier_id);
create table if not exists public.tax_withholdings (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 tax_type text not null check(tax_type in ('IRPS','IRPC')),
 direction text not null default 'withheld' check(direction in ('withheld','suffered')),
 beneficiary_name text not null,
 beneficiary_nuit varchar(20),
 income_category text not null,
 payment_reference text,
 competence_date date not null,
 payment_date date,
 gross_amount numeric(18,2) not null check(gross_amount>=0),
 withholding_rate numeric(7,4) not null check(withholding_rate>=0 and withholding_rate<=100),
 withholding_amount numeric(18,2) not null check(withholding_amount>=0),
 net_amount numeric(18,2) not null check(net_amount>=0),
 due_date date,
 declaration_model text,
 status text not null default 'pending' check(status in ('pending','declared','paid','cancelled')),
 legal_basis text,
 evidence_reference text,
 notes text,
 created_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists tax_withholdings_tenant_due_idx on public.tax_withholdings(tenant_id,tax_type,due_date,status);
create table if not exists public.tax_obligations (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 tax_type text not null check(tax_type in ('IVA','IRPS','IRPC','ISPC','IS','OTHER')),
 obligation_code text not null,
 title text not null,
 description text,
 reference_period text not null,
 due_date date not null,
 status text not null default 'pending' check(status in ('pending','in_progress','filed','paid','not_applicable','overdue')),
 estimated_amount numeric(18,2),
 filed_at timestamptz,
 paid_at timestamptz,
 source text not null default 'manual' check(source in ('manual','calendar_rule','generated_from_records')),
 notes text,
 created_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,obligation_code,reference_period)
);
create index if not exists tax_obligations_tenant_due_idx on public.tax_obligations(tenant_id,due_date,status);
create table if not exists public.ispc_model_b_drafts (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 tax_year integer not null,
 status text not null default 'draft' check(status in ('draft','reviewed','filed')),
 annual_turnover numeric(18,2) not null default 0,
 q1_turnover numeric(18,2) not null default 0,
 q2_turnover numeric(18,2) not null default 0,
 q3_turnover numeric(18,2) not null default 0,
 q4_turnover numeric(18,2) not null default 0,
 total_tax_calculated numeric(18,2) not null default 0,
 source_snapshot jsonb not null default '{}'::jsonb,
 notes text,
 created_by uuid,
 reviewed_by uuid,
 reviewed_at timestamptz,
 filed_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,tax_year)
);
do $$
declare t text;
begin
 foreach t in array array['suppliers','purchase_invoices','tax_withholdings','tax_obligations','ispc_model_b_drafts'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists %I on public.%I',t||'_member_select',t);
  execute format('create policy %I on public.%I for select to authenticated using (private.is_tenant_member(tenant_id))',t||'_member_select',t);
  execute format('drop policy if exists %I on public.%I',t||'_member_insert',t);
  execute format('create policy %I on public.%I for insert to authenticated with check (private.is_tenant_member(tenant_id))',t||'_member_insert',t);
  execute format('drop policy if exists %I on public.%I',t||'_member_update',t);
  execute format('create policy %I on public.%I for update to authenticated using (private.is_tenant_admin(tenant_id)) with check (private.is_tenant_admin(tenant_id))',t||'_member_update',t);
 end loop;
end $$;
grant select,insert,update on public.suppliers,public.purchase_invoices,public.tax_withholdings,public.tax_obligations,public.ispc_model_b_drafts to authenticated;
commit;