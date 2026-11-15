alter table public.tax_obligations
  alter column due_date drop not null;

alter table public.tax_obligations
  add column if not exists due_month integer,
  add column if not exists deadline_precision text not null default 'date',
  add column if not exists official_source_url text,
  add column if not exists source_published_at date;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'tax_obligations_due_month_check') then
    alter table public.tax_obligations add constraint tax_obligations_due_month_check
      check (due_month is null or due_month between 1 and 12);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'tax_obligations_deadline_precision_check') then
    alter table public.tax_obligations add constraint tax_obligations_deadline_precision_check
      check (deadline_precision in ('date','month','unconfirmed'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'tax_obligations_deadline_shape_check') then
    alter table public.tax_obligations add constraint tax_obligations_deadline_shape_check
      check (
        (deadline_precision = 'date' and due_date is not null)
        or (deadline_precision = 'month' and due_month is not null)
        or deadline_precision = 'unconfirmed'
      );
  end if;
end $$;

comment on column public.tax_obligations.deadline_precision is
  'date = dia exacto validado; month = apenas mês validado; unconfirmed = prazo pendente de confirmação oficial';
comment on column public.tax_obligations.official_source_url is
  'URL HTTPS da fonte oficial que fundamenta o prazo fiscal';
