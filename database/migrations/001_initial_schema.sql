-- FacturaExpress initial schema (PostgreSQL)
create extension if not exists pgcrypto;

create table tenants (
 id uuid primary key default gen_random_uuid(),
 legal_name text not null,
 trade_name text,
 nuit varchar(20),
 address text,
 email text,
 phone text,
 currency char(3) not null default 'MZN',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table tenant_users (
 tenant_id uuid not null references tenants(id),
 user_id uuid not null,
 role text not null check (role in ('owner','admin','issuer','viewer','accountant')),
 created_at timestamptz not null default now(),
 primary key (tenant_id,user_id)
);

create table customers (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references tenants(id),
 name text not null,
 nuit varchar(20),
 address text,
 email text,
 phone text,
 tax_status text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (tenant_id,id)
);

create table items (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references tenants(id),
 code text,
 description text not null,
 unit text not null default 'UN',
 unit_price numeric(18,2) not null default 0 check (unit_price >= 0),
 tax_code text,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (tenant_id,id)
);

create table tax_rules (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid references tenants(id),
 code text not null,
 label text not null,
 tax_type text not null,
 rate numeric(9,4),
 legal_reference text,
 valid_from date not null,
 valid_to date,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 check (valid_to is null or valid_to >= valid_from)
);

create table document_series (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references tenants(id),
 document_type text not null,
 series_code text not null,
 fiscal_year integer not null,
 next_number bigint not null default 1 check (next_number > 0),
 status text not null default 'draft' check (status in ('draft','active','suspended','closed')),
 created_at timestamptz not null default now(),
 unique (tenant_id,document_type,series_code,fiscal_year)
);

create table fiscal_documents (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references tenants(id),
 customer_id uuid,
 series_id uuid references document_series(id),
 document_type text not null,
 document_number text,
 status text not null default 'draft' check (status in ('draft','pending_sync','issued','paid','partially_paid','voided')),
 issue_date timestamptz,
 due_date date,
 currency char(3) not null default 'MZN',
 exchange_rate numeric(18,6) not null default 1,
 subtotal numeric(18,2) not null default 0,
 discount_total numeric(18,2) not null default 0,
 tax_total numeric(18,2) not null default 0,
 withholding_total numeric(18,2) not null default 0,
 grand_total numeric(18,2) not null default 0,
 notes text,
 correction_reason text,
 corrects_document_id uuid references fiscal_documents(id),
 local_operation_id uuid unique,
 issued_snapshot jsonb,
 created_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 foreign key (tenant_id,customer_id) references customers(tenant_id,id),
 unique (tenant_id,series_id,document_number)
);

create table fiscal_document_lines (
 id uuid primary key default gen_random_uuid(),
 document_id uuid not null references fiscal_documents(id),
 item_id uuid references items(id),
 description text not null,
 quantity numeric(18,4) not null check (quantity > 0),
 unit text not null,
 unit_price numeric(18,4) not null check (unit_price >= 0),
 discount_amount numeric(18,2) not null default 0,
 tax_code text,
 tax_rate numeric(9,4),
 taxable_amount numeric(18,2) not null,
 tax_amount numeric(18,2) not null,
 line_total numeric(18,2) not null
);

create table document_events (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references tenants(id),
 document_id uuid not null references fiscal_documents(id),
 event_type text not null,
 actor_id uuid,
 payload jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);

create table sync_operations (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references tenants(id),
 device_id uuid not null,
 operation_id uuid not null,
 entity_type text not null,
 entity_id uuid not null,
 operation text not null,
 payload jsonb not null,
 base_version bigint,
 status text not null default 'pending' check (status in ('pending','processing','synced','conflict','failed')),
 attempts integer not null default 0,
 created_at timestamptz not null default now(),
 synced_at timestamptz,
 unique (tenant_id,device_id,operation_id)
);

create index idx_documents_tenant_date on fiscal_documents(tenant_id,issue_date desc);
create index idx_documents_tenant_status on fiscal_documents(tenant_id,status);
create index idx_customers_tenant_name on customers(tenant_id,name);
create index idx_sync_pending on sync_operations(tenant_id,status,created_at) where status <> 'synced';
create index idx_document_events_document on document_events(document_id,created_at);

-- Production hardening still required: enable RLS/policies or enforce tenant scope
-- through a trusted server-side data access layer before exposing any database access.
