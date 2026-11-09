BEGIN;
-- Correctly anchor the normal VAT rate to Article 17, and register the restricted 5% category.
UPDATE public.tax_rules SET legal_reference='Lei n.º 10/2025, de 29 de Dezembro, que mantém a taxa geral de 16% no artigo 17 do CIVA',source_article='Artigo 17 do Código do IVA',applicability='{"regime":"IVA_REGULAR","currency":"MZN"}'::jsonb
WHERE tenant_id IS NULL AND code='IVA_STD_16';
INSERT INTO public.tax_rules(tenant_id,code,label,tax_type,rate,legal_reference,valid_from,active,validation_status,calculation_method,source_document,source_article,applicability)
SELECT NULL,'IVA_RED_5','IVA — taxa reduzida (5%), operações legalmente elegíveis','IVA',5,'Código do IVA, artigo 17-A, aditado pela Lei n.º 22/2022 e mantido após Lei n.º 10/2025',DATE '2023-01-01',true,'approved','percentage','Lei n.º 22/2022, de 28 de Dezembro','Artigo 17-A do Código do IVA','{"regime":"IVA_REGULAR","eligible_operations":["serviços médicos e sanitários prestados por estabelecimentos privados elegíveis","ensino privado reconhecido e operações conexas elegíveis","formação profissional privada e operações conexas elegíveis","lições ministradas a título pessoal sobre matérias de ensino escolar ou superior"],"deductible_input_vat":false,"manual_eligibility_check":true}'::jsonb
WHERE NOT EXISTS(SELECT 1 FROM public.tax_rules WHERE tenant_id IS NULL AND code='IVA_RED_5' AND valid_from=DATE '2023-01-01');

ALTER TABLE public.tenant_tax_profiles
 ADD COLUMN IF NOT EXISTS ispc_annual_reference_turnover numeric(18,2) CHECK(ispc_annual_reference_turnover IS NULL OR ispc_annual_reference_turnover>=0),
 ADD COLUMN IF NOT EXISTS ispc_reference_year integer,
 ADD COLUMN IF NOT EXISTS ispc_reference_confirmed boolean NOT NULL DEFAULT false,
 ADD COLUMN IF NOT EXISTS has_ispc_shareholding_exclusion boolean NOT NULL DEFAULT false,
 ADD COLUMN IF NOT EXISTS has_unidentified_shareholders boolean NOT NULL DEFAULT false,
 ADD COLUMN IF NOT EXISTS has_multiple_establishments boolean NOT NULL DEFAULT false,
 ADD COLUMN IF NOT EXISTS liberal_service_over_183_days_same_client boolean NOT NULL DEFAULT false,
 ADD COLUMN IF NOT EXISTS requires_organized_accounting boolean NOT NULL DEFAULT false,
 ADD COLUMN IF NOT EXISTS has_other_noneligible_activities boolean NOT NULL DEFAULT false,
 ADD COLUMN IF NOT EXISTS at_activity_confirmation_reference text,
 ADD COLUMN IF NOT EXISTS at_startup_turnover_confirmation boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS public.ispc_rate_schedule(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 code text NOT NULL UNIQUE,
 activity_category text NOT NULL CHECK(activity_category IN ('trade_agriculture_industry','general_services','liberal_profession','excess')),
 min_annual_turnover numeric(18,2) NOT NULL DEFAULT 0,
 max_annual_turnover numeric(18,2),
 rate numeric(9,4) NOT NULL CHECK(rate>=0 AND rate<=100),
 legal_reference text NOT NULL,
 valid_from date NOT NULL,
 valid_to date,
 active boolean NOT NULL DEFAULT true,
 CHECK(max_annual_turnover IS NULL OR max_annual_turnover>=min_annual_turnover),
 CHECK(valid_to IS NULL OR valid_to>=valid_from)
);
ALTER TABLE public.ispc_rate_schedule ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ispc_rate_schedule_read ON public.ispc_rate_schedule;
CREATE POLICY ispc_rate_schedule_read ON public.ispc_rate_schedule FOR SELECT TO authenticated USING(true);
REVOKE ALL ON public.ispc_rate_schedule FROM anon,authenticated;
GRANT SELECT ON public.ispc_rate_schedule TO authenticated;

INSERT INTO public.ispc_rate_schedule(code,activity_category,min_annual_turnover,max_annual_turnover,rate,legal_reference,valid_from)
VALUES
('ISPC_GOODS_3','trade_agriculture_industry',0,1000000,3,'Lei n.º 9/2025, artigo 8, n.º 1, alínea a), subalínea i)',DATE '2026-01-01'),
('ISPC_GOODS_4','trade_agriculture_industry',1000000.01,2500000,4,'Lei n.º 9/2025, artigo 8, n.º 1, alínea a), subalínea ii)',DATE '2026-01-01'),
('ISPC_GOODS_5','trade_agriculture_industry',2500000.01,4000000,5,'Lei n.º 9/2025, artigo 8, n.º 1, alínea a), subalínea iii)',DATE '2026-01-01'),
('ISPC_SERVICES_12','general_services',0,4000000,12,'Lei n.º 9/2025, artigo 8, n.º 1, alínea b)',DATE '2026-01-01'),
('ISPC_LIBERAL_15','liberal_profession',0,4000000,15,'Lei n.º 9/2025, artigo 8, n.º 1, alínea c)',DATE '2026-01-01'),
('ISPC_EXCESS_20','excess',4000000.01,NULL,20,'Lei n.º 9/2025, artigo 8, n.º 1, alínea d)',DATE '2026-01-01')
ON CONFLICT(code) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.ispc_quarterly_assessments(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
 tax_year integer NOT NULL,
 quarter integer NOT NULL CHECK(quarter BETWEEN 1 AND 4),
 activity_category text NOT NULL,
 annual_reference_turnover numeric(18,2) NOT NULL,
 turnover_before_quarter numeric(18,2) NOT NULL DEFAULT 0,
 quarter_turnover numeric(18,2) NOT NULL,
 applicable_rate numeric(9,4) NOT NULL,
 taxable_within_limit numeric(18,2) NOT NULL,
 taxable_over_limit numeric(18,2) NOT NULL,
 calculated_tax numeric(18,2) NOT NULL,
 payment_due numeric(18,2) NOT NULL,
 payment_threshold_exemption boolean NOT NULL DEFAULT false,
 status text NOT NULL DEFAULT 'preview' CHECK(status IN ('preview','confirmed','declared','paid','cancelled')),
 legal_reference text NOT NULL,
 created_by uuid,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(tenant_id,tax_year,quarter)
);
ALTER TABLE public.ispc_quarterly_assessments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ispc_assessment_member_read ON public.ispc_quarterly_assessments;
CREATE POLICY ispc_assessment_member_read ON public.ispc_quarterly_assessments FOR SELECT TO authenticated USING(private.is_tenant_member(tenant_id));
DROP POLICY IF EXISTS ispc_assessment_member_insert ON public.ispc_quarterly_assessments;
CREATE POLICY ispc_assessment_member_insert ON public.ispc_quarterly_assessments FOR INSERT TO authenticated WITH CHECK(private.is_tenant_member(tenant_id));
REVOKE ALL ON public.ispc_quarterly_assessments FROM anon,authenticated;
GRANT SELECT,INSERT ON public.ispc_quarterly_assessments TO authenticated;

CREATE OR REPLACE FUNCTION public.preview_ispc_quarter(p_tax_year integer,p_quarter integer,p_turnover_before numeric,p_quarter_turnover numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,private,pg_temp AS $$
DECLARE v_tenant uuid; v_profile public.tenant_tax_profiles%ROWTYPE; v_category text; v_ref numeric; v_rate numeric; v_rate_code text;
 v_within numeric; v_excess numeric; v_tax numeric; v_pay numeric; v_cutoff date; v_eligible boolean;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão inválida.'; END IF;
 SELECT tenant_id INTO v_tenant FROM public.tenant_users WHERE user_id=auth.uid() ORDER BY created_at LIMIT 1;
 IF v_tenant IS NULL OR NOT private.is_tenant_member(v_tenant) THEN RAISE EXCEPTION 'Utilizador sem empresa activa.'; END IF;
 IF p_tax_year<2026 OR p_quarter NOT BETWEEN 1 AND 4 OR p_turnover_before<0 OR p_quarter_turnover<0 THEN RAISE EXCEPTION 'Parâmetros do período ou volume de negócios inválidos.'; END IF;
 SELECT * INTO v_profile FROM public.tenant_tax_profiles WHERE tenant_id=v_tenant;
 IF NOT FOUND OR v_profile.regime_code<>'ISPC' OR v_profile.confirmation_status<>'confirmed' OR NOT v_profile.ispc_opt_in THEN RAISE EXCEPTION 'Perfil ISPC não confirmado.'; END IF;
 IF v_profile.has_ispc_shareholding_exclusion OR v_profile.has_unidentified_shareholders OR v_profile.has_multiple_establishments OR v_profile.liberal_service_over_183_days_same_client OR v_profile.requires_organized_accounting OR v_profile.has_other_noneligible_activities THEN RAISE EXCEPTION 'Foram assinalados factores de exclusão do ISPC. Solicite revisão fiscal.'; END IF;
 IF v_profile.ispc_annual_reference_turnover IS NULL OR NOT v_profile.ispc_reference_confirmed THEN RAISE EXCEPTION 'O volume de negócios de referência deve ser confirmado com a AT.'; END IF;
 v_ref:=v_profile.ispc_annual_reference_turnover;
 IF v_profile.activity_category IS NULL THEN RAISE EXCEPTION 'Classifique a actividade ISPC.'; END IF;
 IF v_profile.activity_category='trade_agriculture_industry' THEN
   IF v_ref<=1000000 THEN v_rate:=3;v_rate_code:='ISPC_GOODS_3';
   ELSIF v_ref<=2500000 THEN v_rate:=4;v_rate_code:='ISPC_GOODS_4';
   ELSIF v_ref<=4000000 THEN v_rate:=5;v_rate_code:='ISPC_GOODS_5';
   ELSE v_rate:=20;v_rate_code:='ISPC_EXCESS_20'; END IF;
 ELSIF v_profile.activity_category='general_services' THEN v_rate:=12;v_rate_code:='ISPC_SERVICES_12';
 ELSIF v_profile.activity_category='liberal_profession' THEN v_rate:=15;v_rate_code:='ISPC_LIBERAL_15';
 ELSE RAISE EXCEPTION 'Categoria não habilitada para cálculo ISPC.'; END IF;
 IF v_ref>4000000 THEN RAISE EXCEPTION 'O volume anual de referência ultrapassa o limite de enquadramento ISPC.'; END IF;
 v_within:=least(p_quarter_turnover,greatest(0,4000000-p_turnover_before));
 v_excess:=greatest(0,p_quarter_turnover-v_within);
 v_tax:=round(v_within*v_rate/100,2)+round(v_excess*20/100,2);
 v_pay:=CASE WHEN v_tax<500 THEN 0 ELSE v_tax END;
 RETURN jsonb_build_object('tax_year',p_tax_year,'quarter',p_quarter,'activity_category',v_profile.activity_category,'annual_reference_turnover',v_ref,'turnover_before_quarter',p_turnover_before,'quarter_turnover',p_quarter_turnover,'applicable_rate',v_rate,'rate_code',v_rate_code,'taxable_within_limit',v_within,'taxable_over_limit',v_excess,'calculated_tax',v_tax,'payment_due',v_pay,'payment_threshold_exemption',v_tax<500,'declaration_still_required',true,'legal_reference','Lei n.º 9/2025, artigos 8, 9 e 10-A');
END;$$;
REVOKE ALL ON FUNCTION public.preview_ispc_quarter(integer,integer,numeric,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.preview_ispc_quarter(integer,integer,numeric,numeric) TO authenticated;
COMMIT;