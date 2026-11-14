BEGIN;

ALTER TABLE public.tenant_tax_profiles
 ADD COLUMN IF NOT EXISTS ispc_activity_areas text[] NOT NULL DEFAULT '{}',
 ADD COLUMN IF NOT EXISTS ispc_activity_categories text[] NOT NULL DEFAULT '{}';

ALTER TABLE public.tenant_tax_profiles
 DROP CONSTRAINT IF EXISTS tenant_tax_profiles_ispc_activity_areas_check,
 ADD CONSTRAINT tenant_tax_profiles_ispc_activity_areas_check CHECK (
   ispc_activity_areas <@ ARRAY['forestry','fishing','livestock','agriculture','poultry','apiculture']::text[]
 ),
 DROP CONSTRAINT IF EXISTS tenant_tax_profiles_ispc_activity_categories_check,
 ADD CONSTRAINT tenant_tax_profiles_ispc_activity_categories_check CHECK (
   ispc_activity_categories <@ ARRAY['trade_agriculture_industry','general_services','liberal_profession']::text[]
 );

UPDATE public.tenant_tax_profiles
 SET ispc_activity_categories = ARRAY[activity_category]
 WHERE cardinality(ispc_activity_categories)=0
   AND activity_category IN ('trade_agriculture_industry','general_services','liberal_profession');

CREATE OR REPLACE FUNCTION public.preview_ispc_quarter(
 p_tax_year integer,
 p_quarter integer,
 p_turnover_before numeric,
 p_quarter_turnover numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path=public,private,pg_temp
AS $$
DECLARE
 v_tenant uuid;
 v_profile public.tenant_tax_profiles%ROWTYPE;
 v_ref numeric;
 v_rate numeric;
 v_rate_code text;
 v_within numeric;
 v_excess numeric;
 v_tax numeric;
 v_pay numeric;
 v_excess_rate numeric;
 v_category text;
 v_categories text[];
 v_rule public.ispc_rate_schedule%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão inválida.'; END IF;
 SELECT tenant_id INTO v_tenant FROM public.tenant_users
  WHERE user_id=auth.uid() ORDER BY created_at LIMIT 1;
 IF v_tenant IS NULL OR NOT private.is_tenant_member(v_tenant) THEN
  RAISE EXCEPTION 'Utilizador sem empresa activa.';
 END IF;
 IF p_tax_year<2026 OR p_quarter NOT BETWEEN 1 AND 4
    OR p_turnover_before<0 OR p_quarter_turnover<0 THEN
  RAISE EXCEPTION 'Parâmetros do período ou volume de negócios inválidos.';
 END IF;

 SELECT * INTO v_profile FROM public.tenant_tax_profiles WHERE tenant_id=v_tenant;
 IF NOT FOUND OR v_profile.regime_code<>'ISPC'
    OR v_profile.confirmation_status<>'confirmed' OR NOT v_profile.ispc_opt_in THEN
  RAISE EXCEPTION 'Perfil ISPC não confirmado.';
 END IF;
 IF v_profile.has_ispc_shareholding_exclusion OR v_profile.has_unidentified_shareholders
    OR v_profile.has_multiple_establishments OR v_profile.liberal_service_over_183_days_same_client
    OR v_profile.requires_organized_accounting OR v_profile.has_other_noneligible_activities THEN
  RAISE EXCEPTION 'Foram assinalados factores de exclusão do ISPC. Solicite revisão fiscal.';
 END IF;
 IF v_profile.ispc_annual_reference_turnover IS NULL OR NOT v_profile.ispc_reference_confirmed
    OR nullif(trim(v_profile.at_activity_confirmation_reference),'') IS NULL THEN
  RAISE EXCEPTION 'O volume de negócios de referência deve ser confirmado pela AT e documentado.';
 END IF;
 v_ref:=v_profile.ispc_annual_reference_turnover;
 IF v_ref>4000000 THEN
  RAISE EXCEPTION 'O volume anual de referência ultrapassa o limite de enquadramento ISPC.';
 END IF;
 IF v_profile.ispc_reference_year IS DISTINCT FROM (p_tax_year-1)
    AND NOT (v_profile.at_startup_turnover_confirmation
      AND v_profile.ispc_start_date>=make_date(p_tax_year,1,1)) THEN
  RAISE EXCEPTION 'O ano de referência deve ser o exercício anterior, ou deve existir confirmação da AT para início de actividade.';
 END IF;

 v_categories:=COALESCE(NULLIF(v_profile.ispc_activity_categories,'{}'::text[]),
   CASE WHEN v_profile.activity_category IN ('trade_agriculture_industry','general_services','liberal_profession')
     THEN ARRAY[v_profile.activity_category] ELSE ARRAY[]::text[] END);
 IF cardinality(v_categories)=0 THEN
  RAISE EXCEPTION 'Configure pelo menos uma categoria de actividade ISPC.';
 END IF;
 IF 'trade_agriculture_industry'=ANY(v_categories)
    AND cardinality(v_profile.ispc_activity_areas)=0 THEN
  RAISE EXCEPTION 'Seleccione as áreas de actividade primária, comercial ou industrial exercidas.';
 END IF;

 -- Artigo 8, n.º 2: em caso de cumulação, aplica-se a categoria com a taxa mais elevada.
 IF 'liberal_profession'=ANY(v_categories) THEN
  v_category:='liberal_profession';
 ELSIF 'general_services'=ANY(v_categories) THEN
  v_category:='general_services';
 ELSIF 'trade_agriculture_industry'=ANY(v_categories) THEN
  v_category:='trade_agriculture_industry';
 ELSE
  RAISE EXCEPTION 'As categorias seleccionadas não permitem determinar uma taxa ISPC.';
 END IF;

 SELECT * INTO v_rule FROM public.ispc_rate_schedule
  WHERE activity_category=v_category AND min_annual_turnover<=v_ref
    AND (max_annual_turnover IS NULL OR max_annual_turnover>=v_ref)
    AND active AND valid_from<=current_date
    AND (valid_to IS NULL OR valid_to>=current_date)
  ORDER BY min_annual_turnover DESC LIMIT 1;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'Não existe escalão ISPC vigente para a actividade e volume de negócios indicados.';
 END IF;
 v_rate:=v_rule.rate;
 v_rate_code:=v_rule.code;

 v_within:=least(p_quarter_turnover,greatest(0,4000000-p_turnover_before));
 v_excess:=greatest(0,p_quarter_turnover-v_within);
 SELECT rate INTO v_excess_rate FROM public.ispc_rate_schedule
  WHERE code='ISPC_EXCESS_20' AND active AND valid_from<=current_date
    AND (valid_to IS NULL OR valid_to>=current_date);
 IF v_excess_rate IS NULL THEN RAISE EXCEPTION 'Regra de taxa sobre excesso não configurada.'; END IF;
 v_tax:=round(v_within*v_rate/100,2)+round(v_excess*v_excess_rate/100,2);
 v_pay:=CASE WHEN v_tax<500 THEN 0 ELSE v_tax END;

 RETURN jsonb_build_object(
  'tax_year',p_tax_year,'quarter',p_quarter,
  'activity_category',v_category,'activity_categories',v_categories,
  'activity_areas',v_profile.ispc_activity_areas,
  'annual_reference_turnover',v_ref,
  'turnover_before_quarter',p_turnover_before,'quarter_turnover',p_quarter_turnover,
  'applicable_rate',v_rate,'rate_code',v_rate_code,'excess_rate',v_excess_rate,
  'taxable_within_limit',v_within,'taxable_over_limit',v_excess,
  'calculated_tax',v_tax,'payment_due',v_pay,
  'payment_threshold_exemption',v_tax<500,'declaration_still_required',true,
  'legal_reference','Lei n.º 9/2025, artigo 8, n.ºs 1 e 2, artigos 9 e 10-A'
 );
END;
$$;

REVOKE ALL ON FUNCTION public.preview_ispc_quarter(integer,integer,numeric,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.preview_ispc_quarter(integer,integer,numeric,numeric) TO authenticated;

COMMIT;
