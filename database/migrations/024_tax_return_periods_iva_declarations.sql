BEGIN;
CREATE TABLE IF NOT EXISTS public.tax_return_periods (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenants(id),
 tax_type text NOT NULL CHECK (tax_type IN ('IVA','ISPC')),
 tax_year integer NOT NULL,
 tax_period integer NOT NULL CHECK (tax_period BETWEEN 1 AND 12),
 status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','reviewed','submitted','paid','cancelled')),
 period_start date NOT NULL,
 period_end date NOT NULL,
 sales_taxable_base numeric(18,2) NOT NULL DEFAULT 0,
 output_tax numeric(18,2) NOT NULL DEFAULT 0,
 input_tax_credit numeric(18,2) NOT NULL DEFAULT 0,
 prior_period_credit numeric(18,2) NOT NULL DEFAULT 0,
 tax_due numeric(18,2) NOT NULL DEFAULT 0,
 zero_rated_base numeric(18,2) NOT NULL DEFAULT 0,
 exempt_base numeric(18,2) NOT NULL DEFAULT 0,
 non_taxable_base numeric(18,2) NOT NULL DEFAULT 0,
 source_document_count integer NOT NULL DEFAULT 0,
 source_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
 notes text,
 created_by uuid,
 reviewed_by uuid,
 reviewed_at timestamptz,
 submitted_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(tenant_id,tax_type,tax_year,tax_period),
 CHECK(period_end>=period_start),
 CHECK(input_tax_credit>=0 AND prior_period_credit>=0)
);
CREATE INDEX IF NOT EXISTS idx_tax_return_tenant_period ON public.tax_return_periods(tenant_id,tax_type,tax_year DESC,tax_period DESC);
ALTER TABLE public.tax_return_periods ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tax_return_member_read ON public.tax_return_periods;
CREATE POLICY tax_return_member_read ON public.tax_return_periods FOR SELECT TO authenticated USING(private.is_tenant_member(tenant_id));
DROP POLICY IF EXISTS tax_return_admin_insert ON public.tax_return_periods;
CREATE POLICY tax_return_admin_insert ON public.tax_return_periods FOR INSERT TO authenticated WITH CHECK(private.is_tenant_admin(tenant_id));
DROP POLICY IF EXISTS tax_return_admin_update ON public.tax_return_periods;
CREATE POLICY tax_return_admin_update ON public.tax_return_periods FOR UPDATE TO authenticated USING(private.is_tenant_admin(tenant_id)) WITH CHECK(private.is_tenant_admin(tenant_id));
GRANT SELECT,INSERT,UPDATE ON public.tax_return_periods TO authenticated;
COMMIT;