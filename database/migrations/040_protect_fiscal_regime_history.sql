CREATE OR REPLACE FUNCTION private.enforce_tenant_tax_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
 v_activity public.ispc_activity_catalog%ROWTYPE;
 v_role text;
BEGIN
 IF auth.uid() IS NOT NULL THEN
  SELECT role INTO v_role FROM public.tenant_users
  WHERE tenant_id=NEW.tenant_id AND user_id=auth.uid();
  IF v_role NOT IN ('owner','admin') THEN
   RAISE EXCEPTION 'Apenas o proprietário ou administrador pode alterar o perfil fiscal.';
  END IF;
 END IF;

 IF TG_OP='UPDATE' AND OLD.regime_code IS DISTINCT FROM NEW.regime_code THEN
  IF EXISTS(SELECT 1 FROM public.fiscal_documents d WHERE d.tenant_id=NEW.tenant_id AND d.status IN ('issued','paid','partially_paid','voided')) THEN
   RAISE EXCEPTION 'O regime fiscal não pode ser alterado directamente depois da emissão de documentos. É necessário um processo formal de alteração de enquadramento.';
  END IF;
 END IF;

 IF NEW.regime_code NOT IN ('IVA_REGULAR','ISPC','NON_SUBJECT','OTHER') THEN
  RAISE EXCEPTION 'Regime fiscal inválido.';
 END IF;

 IF NEW.regime_code <> 'ISPC' THEN
  IF coalesce(NEW.ispc_opt_in,false) OR NEW.ispc_primary_activity_code IS NOT NULL OR coalesce(cardinality(NEW.ispc_activity_areas),0)>0 THEN
   RAISE EXCEPTION 'Uma empresa fora do ISPC não pode manter opções ou actividades ISPC activas.';
  END IF;
  RETURN NEW;
 END IF;

 IF NOT coalesce(NEW.ispc_opt_in,false) THEN RAISE EXCEPTION 'A opção pelo regime ISPC deve estar confirmada.'; END IF;
 IF nullif(trim(NEW.ispc_primary_activity_code),'') IS NULL THEN RAISE EXCEPTION 'O ISPC exige uma actividade principal seleccionada.'; END IF;

 SELECT * INTO v_activity FROM public.ispc_activity_catalog
 WHERE activity_code=NEW.ispc_primary_activity_code AND active=true AND valid_from<=current_date
 AND (valid_to IS NULL OR valid_to>=current_date);
 IF NOT FOUND OR NEW.activity_category IS DISTINCT FROM v_activity.activity_category THEN
  RAISE EXCEPTION 'A actividade principal não corresponde ao catálogo ISPC vigente.';
 END IF;

 IF NEW.confirmation_status='confirmed' THEN
  IF NEW.ispc_annual_reference_turnover IS NULL OR NEW.ispc_annual_reference_turnover<0
   OR NEW.ispc_annual_reference_turnover>4000000 OR NOT coalesce(NEW.ispc_reference_confirmed,false)
   OR NEW.ispc_reference_year IS NULL OR nullif(trim(NEW.at_activity_confirmation_reference),'') IS NULL THEN
   RAISE EXCEPTION 'O perfil ISPC confirmado exige volume anual de referência, ano e referência documental da AT, dentro do limite legal.';
  END IF;
  IF coalesce(NEW.has_ispc_shareholding_exclusion,false) OR coalesce(NEW.has_unidentified_shareholders,false)
   OR coalesce(NEW.has_multiple_establishments,false) OR coalesce(NEW.liberal_service_over_183_days_same_client,false)
   OR coalesce(NEW.requires_organized_accounting,false) OR coalesce(NEW.has_other_noneligible_activities,false) THEN
   RAISE EXCEPTION 'Existem factores de exclusão do ISPC. O perfil não pode ser confirmado.';
  END IF;
 END IF;
 RETURN NEW;
END;
$$;