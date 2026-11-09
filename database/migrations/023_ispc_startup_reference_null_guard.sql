DO $$
DECLARE v_def text;
BEGIN
 v_def:=pg_get_functiondef('public.preview_ispc_quarter(integer,integer,numeric,numeric)'::regprocedure);
 v_def:=replace(v_def,
 'NOT (v_profile.at_startup_turnover_confirmation AND v_profile.ispc_start_date>=make_date(p_tax_year,1,1))',
 'NOT (v_profile.at_startup_turnover_confirmation AND v_profile.ispc_start_date IS NOT NULL AND v_profile.ispc_start_date>=make_date(p_tax_year,1,1))');
 IF position('v_profile.ispc_start_date IS NOT NULL' in v_def)=0 THEN RAISE EXCEPTION 'Não foi possível aplicar a validação de início de actividade.'; END IF;
 EXECUTE v_def;
END $$;