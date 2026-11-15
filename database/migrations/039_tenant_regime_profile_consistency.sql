-- Keep the tenant's legacy tax_regime field aligned with the confirmed fiscal profile.
CREATE OR REPLACE FUNCTION private.enforce_tenant_regime_matches_profile()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $$
DECLARE v_profile_regime text;
BEGIN
 IF NEW.tax_regime IS NOT DISTINCT FROM OLD.tax_regime THEN RETURN NEW; END IF;
 SELECT regime_code INTO v_profile_regime
 FROM public.tenant_tax_profiles
 WHERE tenant_id=NEW.id;
 IF v_profile_regime IS NULL THEN
  RAISE EXCEPTION 'Configure o perfil fiscal antes de alterar o regime fiscal da empresa.';
 END IF;
 IF (v_profile_regime='IVA_REGULAR' AND NEW.tax_regime<>'IVA')
  OR (v_profile_regime='ISPC' AND NEW.tax_regime<>'ISPC')
  OR (v_profile_regime NOT IN ('IVA_REGULAR','ISPC') AND NEW.tax_regime IS DISTINCT FROM v_profile_regime) THEN
  RAISE EXCEPTION 'O regime fiscal da empresa deve coincidir com o perfil fiscal confirmado.';
 END IF;
 RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_tenant_regime_matches_profile ON public.tenants;
CREATE TRIGGER trg_tenant_regime_matches_profile
BEFORE UPDATE OF tax_regime ON public.tenants
FOR EACH ROW EXECUTE FUNCTION private.enforce_tenant_regime_matches_profile();
REVOKE ALL ON FUNCTION private.enforce_tenant_regime_matches_profile() FROM PUBLIC,anon,authenticated;