DO $$
DECLARE v_def text;
BEGIN
 v_def:=pg_get_functiondef('public.issue_fiscal_document(uuid,text)'::regprocedure);
 v_def:=replace(v_def,
 'v_company public.tenants%ROWTYPE; v_customer public.customers%ROWTYPE;',
 'v_company public.tenants%ROWTYPE; v_customer public.customers%ROWTYPE; v_profile public.tenant_tax_profiles%ROWTYPE;');
 v_def:=replace(v_def,
 'SELECT * INTO v_company FROM public.tenants WHERE id=v_tenant;',
 'SELECT * INTO v_company FROM public.tenants WHERE id=v_tenant; SELECT * INTO v_profile FROM public.tenant_tax_profiles WHERE tenant_id=v_tenant;');
 v_def:=replace(v_def,
 'OR nullif(trim(v_customer.address),'''') IS NULL',
 'OR (coalesce(v_profile.regime_code,''IVA_REGULAR'')<>''ISPC'' AND nullif(trim(v_customer.address),'''') IS NULL)');
 v_def:=replace(v_def,
 'AND (nullif(trim(l.tax_code),'''') IS NULL OR l.tax_rate IS NULL)',
 'AND ((v_profile.regime_code=''ISPC'' AND (l.tax_code IS NOT NULL OR coalesce(l.tax_rate,0)<>0)) OR (coalesce(v_profile.regime_code,''IVA_REGULAR'')<>''ISPC'' AND (nullif(trim(l.tax_code),'''') IS NULL OR l.tax_rate IS NULL)) OR (l.tax_code=''IVA_RED_5'' AND (l.tax_eligibility_category IS NULL OR nullif(trim(l.tax_eligibility_reference),'''') IS NULL)))');
 IF position('v_profile public.tenant_tax_profiles%ROWTYPE' in v_def)=0 OR position('l.tax_eligibility_category IS NULL' in v_def)=0 THEN RAISE EXCEPTION 'Não foi possível actualizar os controlos de emissão fiscal.'; END IF;
 EXECUTE v_def;
END $$;