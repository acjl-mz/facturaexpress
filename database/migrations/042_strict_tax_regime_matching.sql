CREATE OR REPLACE FUNCTION private.enforce_tenant_regime_matches_profile()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $$
DECLARE v_profile_regime text;
BEGIN
 IF NEW.tax_regime IS NOT DISTINCT FROM OLD.tax_regime THEN RETURN NEW; END IF;
 SELECT regime_code INTO v_profile_regime FROM public.tenant_tax_profiles WHERE tenant_id=NEW.id;
 IF v_profile_regime IS NULL THEN RAISE EXCEPTION 'Configure o perfil fiscal antes de alterar o regime fiscal da empresa.'; END IF;
 IF (v_profile_regime='IVA_REGULAR' AND NEW.tax_regime IS DISTINCT FROM 'IVA')
  OR (v_profile_regime='ISPC' AND NEW.tax_regime IS DISTINCT FROM 'ISPC')
  OR (v_profile_regime NOT IN ('IVA_REGULAR','ISPC') AND NEW.tax_regime IS DISTINCT FROM v_profile_regime) THEN
  RAISE EXCEPTION 'O regime fiscal da empresa deve coincidir com o perfil fiscal confirmado.';
 END IF;
 RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.enforce_fiscal_document_regime()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $$
DECLARE v_profile public.tenant_tax_profiles%ROWTYPE; v_tenant_regime text;
BEGIN
 IF OLD.status IS DISTINCT FROM NEW.status AND OLD.status='draft' AND NEW.status IN ('issued','paid','partially_paid') THEN
  SELECT * INTO v_profile FROM public.tenant_tax_profiles WHERE tenant_id=NEW.tenant_id;
  IF NOT FOUND OR v_profile.confirmation_status<>'confirmed' THEN RAISE EXCEPTION 'Emissão bloqueada: o perfil fiscal da empresa não está confirmado.'; END IF;
  IF v_profile.regime_code NOT IN ('IVA_REGULAR','ISPC') THEN RAISE EXCEPTION 'Emissão bloqueada: o regime fiscal seleccionado não está habilitado para facturação.'; END IF;
  SELECT tax_regime INTO v_tenant_regime FROM public.tenants WHERE id=NEW.tenant_id;
  IF (v_profile.regime_code='IVA_REGULAR' AND v_tenant_regime IS DISTINCT FROM 'IVA') OR (v_profile.regime_code='ISPC' AND v_tenant_regime IS DISTINCT FROM 'ISPC') THEN
   RAISE EXCEPTION 'Emissão bloqueada: o regime fiscal do perfil e da empresa não coincide.';
  END IF;
  IF NEW.document_type NOT IN ('FT','FR') THEN RAISE EXCEPTION 'Tipo documental não permitido no regime fiscal configurado.'; END IF;
  IF v_profile.regime_code='ISPC' THEN
   IF NOT coalesce(v_profile.ispc_opt_in,false) OR nullif(trim(v_profile.ispc_primary_activity_code),'') IS NULL OR v_profile.ispc_annual_reference_turnover IS NULL OR NOT coalesce(v_profile.ispc_reference_confirmed,false) OR nullif(trim(v_profile.at_activity_confirmation_reference),'') IS NULL THEN
    RAISE EXCEPTION 'Emissão ISPC bloqueada: falta confirmação do enquadramento, actividade principal ou volume de referência.';
   END IF;
   IF EXISTS(SELECT 1 FROM public.fiscal_document_lines l WHERE l.document_id=NEW.id AND (l.tax_code IS NOT NULL OR coalesce(l.tax_rate,0)<>0 OR coalesce(l.tax_amount,0)<>0)) THEN
    RAISE EXCEPTION 'No regime ISPC não é permitido incluir IVA nas linhas do documento.';
   END IF;
  ELSIF v_profile.regime_code='IVA_REGULAR' THEN
   IF EXISTS(SELECT 1 FROM public.fiscal_document_lines l WHERE l.document_id=NEW.id AND (nullif(trim(l.tax_code),'') IS NULL OR l.tax_rate IS NULL)) THEN
    RAISE EXCEPTION 'No regime IVA todas as linhas devem ter classificação fiscal.';
   END IF;
  END IF;
 END IF;
 RETURN NEW;
END;
$$;