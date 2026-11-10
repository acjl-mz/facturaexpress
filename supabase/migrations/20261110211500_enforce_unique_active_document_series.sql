create unique index if not exists document_series_one_active_per_type_year
  on public.document_series (tenant_id, document_type, fiscal_year)
  where status = 'active';

alter table public.document_series
  add constraint document_series_next_number_positive
  check (next_number > 0) not valid;

alter table public.document_series
  validate constraint document_series_next_number_positive;
