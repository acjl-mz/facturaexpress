CREATE OR REPLACE FUNCTION private.enforce_fiscal_document_line_regime()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
 v_document public.fiscal_documents%ROWTYPE;
 v_profile public.tenant_tax_profiles%ROWTYPE;
 v_rule public.tax_rules%ROWTYPE;
 v_expected_base numeric(18,2);
 v_expected_tax numeric(18,2);
BEGIN
 SELECT * INTO v_document FROM public.fiscal_documents
 WHERE id=CASE WHEN TG_OP='DELETE' THEN OLD.document_id ELSE NEW.document_id END;
 IF NOT FOUND THEN RAISE EXCEPTION 'Documento associado à linha não encontrado.'; END IF;
 IF v_document.status<>'draft' THEN RAISE EXCEPTION 'As linhas só podem ser alteradas enquanto o documento estiver em rascunho.'; END IF;

 IF TG_OP='DELETE' THEN RETURN OLD; END IF;

 SELECT * INTO v_profile FROM public.tenant_tax_profiles WHERE tenant_id=v_document.tenant_id;
 IF NOT FOUND OR v_profile.confirmation_status<>'confirmed' THEN
  RAISE EXCEPTION 'Confirme o perfil fiscal da empresa antes de alterar linhas documentais.';
 END IF;
 IF v_profile.regime_code NOT IN ('IVA_REGULAR','ISPC') THEN
  RAISE EXCEPTION 'O regime fiscal da empresa não está habilitado para facturação.';
 END IF;

 IF NEW.quantity IS NULL OR NEW.quantity<=0 OR NEW.unit_price IS NULL OR NEW.unit_price<0
  OR NEW.discount_amount IS NULL OR NEW.discount_amount<0
  OR NEW.discount_amount>round(NEW.quantity*NEW.unit_price,2) THEN
  RAISE EXCEPTION 'Quantidade, preço ou desconto inválido.';
 END IF;

 v_expected_base:=round(NEW.quantity*NEW.unit_price-NEW.discount_amount,2);
 IF NEW.taxable_amount IS DISTINCT FROM v_expected_base THEN
  RAISE EXCEPTION 'A base tributável da linha não corresponde à quantidade, preço e desconto.';
 END IF;

 IF v_profile.regime_code='ISPC' THEN
  IF NEW.tax_code IS NOT NULL OR coalesce(NEW.tax_rate,0)<>0 OR coalesce(NEW.tax_amount,0)<>0 THEN
   RAISE EXCEPTION 'No regime ISPC não é permitido associar IVA às linhas.';
  END IF;
  v_expected_tax:=0;
 ELSE
  IF nullif(trim(NEW.tax_code),'') IS NULL THEN RAISE EXCEPTION 'No regime IVA todas as linhas exigem classificação fiscal.'; END IF;
  SELECT * INTO v_rule FROM public.tax_rules
  WHERE code=NEW.tax_code AND (tenant_id=v_document.tenant_id OR tenant_id IS NULL)
   AND active=true AND validation_status='approved' AND tax_type='IVA'
   AND valid_from<=current_date AND (valid_to IS NULL OR valid_to>=current_date)
  ORDER BY (tenant_id IS NOT NULL) DESC,valid_from DESC LIMIT 1;
  IF NOT FOUND OR v_rule.rate IS NULL THEN RAISE EXCEPTION 'Código IVA não aprovado ou fora da vigência.'; END IF;
  IF NEW.tax_rate IS DISTINCT FROM v_rule.rate THEN RAISE EXCEPTION 'A taxa da linha não corresponde à regra fiscal vigente.'; END IF;
  IF NEW.tax_code='IVA_RED_5' AND (
    nullif(trim(NEW.tax_eligibility_reference),'') IS NULL OR
    NEW.tax_eligibility_category NOT IN ('private_health','recognized_private_education','professional_training','private_lessons')
  ) THEN RAISE EXCEPTION 'A taxa reduzida exige categoria elegível e referência documental.'; END IF;
  v_expected_tax:=round(v_expected_base*v_rule.rate/100,2);
 END IF;

 IF NEW.tax_amount IS DISTINCT FROM v_expected_tax OR NEW.line_total IS DISTINCT FROM round(v_expected_base+v_expected_tax,2) THEN
  RAISE EXCEPTION 'O imposto ou total da linha não corresponde ao cálculo fiscal do servidor.';
 END IF;
 RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_fiscal_document_line_regime ON public.fiscal_document_lines;
CREATE TRIGGER trg_enforce_fiscal_document_line_regime
BEFORE INSERT OR UPDATE OR DELETE ON public.fiscal_document_lines
FOR EACH ROW EXECUTE FUNCTION private.enforce_fiscal_document_line_regime();
REVOKE ALL ON FUNCTION private.enforce_fiscal_document_line_regime() FROM PUBLIC,anon,authenticated;