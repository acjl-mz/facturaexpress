BEGIN;
ALTER TABLE public.tax_rules
 ADD COLUMN IF NOT EXISTS validation_status text NOT NULL DEFAULT 'pending' CHECK(validation_status IN ('pending','approved','rejected')),
 ADD COLUMN IF NOT EXISTS applicability jsonb NOT NULL DEFAULT '{}'::jsonb,
 ADD COLUMN IF NOT EXISTS calculation_method text NOT NULL DEFAULT 'percentage' CHECK(calculation_method IN ('percentage','fixed','turnover_bracket','manual')),
 ADD COLUMN IF NOT EXISTS source_document text,
 ADD COLUMN IF NOT EXISTS source_article text;
UPDATE public.tax_rules SET validation_status='pending' WHERE validation_status IS NULL;
CREATE INDEX IF NOT EXISTS tax_rules_lookup_idx ON public.tax_rules(tenant_id,code,valid_from DESC) WHERE active=true;

CREATE TABLE IF NOT EXISTS public.tenant_tax_profiles (
 tenant_id uuid PRIMARY KEY REFERENCES public.tenants(id) ON DELETE RESTRICT,
 regime_code text NOT NULL CHECK(regime_code IN ('IVA_REGULAR','ISPC','IVA_EXEMPT','NON_SUBJECT','OTHER')),
 activity_category text CHECK(activity_category IN ('trade_agriculture_industry','general_services','liberal_profession','mixed','other')),
 ispc_opt_in boolean NOT NULL DEFAULT false,
 ispc_start_date date,
 annual_turnover_estimate numeric(18,2) CHECK(annual_turnover_estimate IS NULL OR annual_turnover_estimate>=0),
 vat_registration_number text,
 exemption_reference text,
 exemption_valid_from date,
 exemption_valid_to date,
 confirmation_status text NOT NULL DEFAULT 'pending' CHECK(confirmation_status IN ('pending','confirmed','needs_review')),
 confirmed_by uuid,
 confirmed_at timestamptz,
 notes text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(exemption_valid_to IS NULL OR exemption_valid_from IS NULL OR exemption_valid_to>=exemption_valid_from),
 CHECK(regime_code<>'ISPC' OR ispc_opt_in=true),
 CHECK(regime_code<>'IVA_EXEMPT' OR nullif(trim(exemption_reference),'') IS NOT NULL)
);
ALTER TABLE public.tenant_tax_profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_tax_profile_member_read ON public.tenant_tax_profiles;
CREATE POLICY tenant_tax_profile_member_read ON public.tenant_tax_profiles FOR SELECT TO authenticated USING(private.is_tenant_member(tenant_id));
DROP POLICY IF EXISTS tenant_tax_profile_admin_insert ON public.tenant_tax_profiles;
CREATE POLICY tenant_tax_profile_admin_insert ON public.tenant_tax_profiles FOR INSERT TO authenticated WITH CHECK(private.is_tenant_admin(tenant_id));
DROP POLICY IF EXISTS tenant_tax_profile_admin_update ON public.tenant_tax_profiles;
CREATE POLICY tenant_tax_profile_admin_update ON public.tenant_tax_profiles FOR UPDATE TO authenticated USING(private.is_tenant_admin(tenant_id)) WITH CHECK(private.is_tenant_admin(tenant_id));
REVOKE ALL ON public.tenant_tax_profiles FROM anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON public.tenant_tax_profiles TO authenticated;

DROP POLICY IF EXISTS tax_rules_select_global_or_tenant ON public.tax_rules;
DROP POLICY IF EXISTS tenant_access_select ON public.tax_rules;
CREATE POLICY tax_rules_select_global_or_tenant ON public.tax_rules FOR SELECT TO authenticated USING(tenant_id IS NULL OR private.is_tenant_member(tenant_id));

INSERT INTO public.tax_rules(tenant_id,code,label,tax_type,rate,legal_reference,valid_from,active,validation_status,calculation_method,source_document,source_article,applicability)
SELECT NULL,'IVA_STD_16','IVA — taxa normal (16%)','IVA',16,'Lei n.º 10/2025, de 29 de Dezembro',DATE '2026-01-01',true,'approved','percentage','Lei n.º 10/2025','Código do IVA, artigo 34 (base tributável com imposto incluído)','{"regime":"IVA_REGULAR","currency":"MZN"}'::jsonb
WHERE NOT EXISTS(SELECT 1 FROM public.tax_rules WHERE tenant_id IS NULL AND code='IVA_STD_16' AND valid_from=DATE '2026-01-01');

CREATE OR REPLACE FUNCTION public.create_fiscal_document_draft(p_customer_id uuid,p_document_type text,p_due_date date,p_notes text,p_lines jsonb,p_client_operation_id uuid)
RETURNS uuid LANGUAGE plpgsql SET search_path=public,private AS $function$
DECLARE
 v_tenant_id uuid; v_doc_id uuid; v_line jsonb; v_item_id uuid; v_description text; v_unit text;
 v_qty numeric(18,4); v_price numeric(18,4); v_discount numeric(18,2); v_gross numeric(18,2);
 v_taxable numeric(18,2); v_rate numeric(9,4); v_tax numeric(18,2); v_tax_code text; v_tax_type text;
 v_subtotal numeric(18,2):=0; v_discount_total numeric(18,2):=0; v_tax_total numeric(18,2):=0; v_grand_total numeric(18,2):=0;
 v_regime text; v_profile public.tenant_tax_profiles%ROWTYPE; v_rule public.tax_rules%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão inválida.'; END IF;
 SELECT tenant_id INTO v_tenant_id FROM public.tenant_users WHERE user_id=auth.uid() ORDER BY created_at LIMIT 1;
 IF v_tenant_id IS NULL OR NOT private.is_tenant_member(v_tenant_id) THEN RAISE EXCEPTION 'Utilizador sem empresa activa.'; END IF;
 IF p_document_type NOT IN ('FT','FR') THEN RAISE EXCEPTION 'Tipo de documento não permitido nesta fase.'; END IF;
 IF jsonb_typeof(p_lines)<>'array' OR jsonb_array_length(p_lines)<1 OR jsonb_array_length(p_lines)>100 THEN RAISE EXCEPTION 'O documento deve conter entre 1 e 100 linhas.'; END IF;
 IF p_client_operation_id IS NOT NULL THEN SELECT id INTO v_doc_id FROM public.fiscal_documents WHERE tenant_id=v_tenant_id AND local_operation_id=p_client_operation_id; IF v_doc_id IS NOT NULL THEN RETURN v_doc_id; END IF; END IF;
 IF p_customer_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.customers WHERE id=p_customer_id AND tenant_id=v_tenant_id) THEN RAISE EXCEPTION 'Cliente inválido para esta empresa.'; END IF;
 SELECT * INTO v_profile FROM public.tenant_tax_profiles WHERE tenant_id=v_tenant_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Configure o perfil fiscal da empresa antes de preparar documentos.'; END IF;
 IF v_profile.confirmation_status<>'confirmed' THEN RAISE EXCEPTION 'O perfil fiscal está pendente de confirmação pelo administrador.'; END IF;
 v_regime:=v_profile.regime_code;
 INSERT INTO public.fiscal_documents(tenant_id,customer_id,document_type,status,due_date,currency,notes,local_operation_id,created_by)
 VALUES(v_tenant_id,p_customer_id,p_document_type,'draft',p_due_date,'MZN',nullif(trim(p_notes),''),p_client_operation_id,auth.uid()) RETURNING id INTO v_doc_id;
 FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
  v_item_id:=nullif(v_line->>'item_id','')::uuid; v_description:=trim(coalesce(v_line->>'description',''));
  v_unit:=coalesce(nullif(trim(v_line->>'unit'),''),'UN'); v_qty:=(v_line->>'quantity')::numeric;
  v_price:=(v_line->>'unit_price')::numeric; v_discount:=coalesce(nullif(v_line->>'discount_amount','')::numeric,0);
  v_tax_code:=nullif(trim(v_line->>'tax_code'),'');
  IF v_description='' OR v_qty<=0 OR v_price<0 THEN RAISE EXCEPTION 'Descrição, quantidade ou preço inválido.'; END IF;
  IF v_item_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.items WHERE id=v_item_id AND tenant_id=v_tenant_id AND active) THEN RAISE EXCEPTION 'Artigo inválido para esta empresa.'; END IF;
  v_gross:=round(v_qty*v_price,2); IF v_discount<0 OR v_discount>v_gross THEN RAISE EXCEPTION 'Desconto inválido.'; END IF;
  v_taxable:=round(v_gross-v_discount,2); v_rate:=0; v_tax:=0; v_tax_type:=NULL;
  IF v_regime='ISPC' THEN
   IF v_tax_code IS NOT NULL THEN RAISE EXCEPTION 'O regime ISPC não permite incluir IVA nas facturas. Remova o código de IVA.'; END IF;
  ELSIF v_regime='IVA_REGULAR' THEN
   IF v_tax_code IS NULL THEN RAISE EXCEPTION 'Classifique fiscalmente cada linha. Para a taxa normal, seleccione IVA_STD_16.'; END IF;
   SELECT * INTO v_rule FROM public.tax_rules WHERE code=v_tax_code AND (tenant_id=v_tenant_id OR tenant_id IS NULL) AND active AND validation_status='approved' AND valid_from<=current_date AND (valid_to IS NULL OR valid_to>=current_date) ORDER BY (tenant_id IS NOT NULL) DESC,valid_from DESC LIMIT 1;
   IF NOT FOUND OR v_rule.rate IS NULL OR v_rule.tax_type<>'IVA' THEN RAISE EXCEPTION 'Regra de IVA não aprovada, inválida ou fora da vigência: %.',v_tax_code; END IF;
   v_rate:=v_rule.rate; v_tax_type:=v_rule.tax_type; v_tax:=round(v_taxable*v_rate/100,2);
  ELSIF v_regime='IVA_EXEMPT' THEN
   IF v_tax_code IS NULL OR nullif(trim(v_profile.exemption_reference),'') IS NULL THEN RAISE EXCEPTION 'O enquadramento de isenção carece de referência legal e classificação por linha.'; END IF;
   SELECT * INTO v_rule FROM public.tax_rules WHERE code=v_tax_code AND (tenant_id=v_tenant_id OR tenant_id IS NULL) AND active AND validation_status='approved' AND valid_from<=current_date AND (valid_to IS NULL OR valid_to>=current_date) ORDER BY (tenant_id IS NOT NULL) DESC,valid_from DESC LIMIT 1;
   IF NOT FOUND OR v_rule.rate<>0 OR v_rule.tax_type NOT IN ('IVA_ISENTO','IVA_NAO_SUJEITO') OR nullif(trim(v_rule.legal_reference),'') IS NULL THEN RAISE EXCEPTION 'A classificação de isenção/não sujeição não tem fundamento legal aprovado.'; END IF;
   v_rate:=0; v_tax_type:=v_rule.tax_type;
  ELSE
   RAISE EXCEPTION 'O regime fiscal seleccionado ainda não permite preparar documentos neste fluxo. Solicite validação do enquadramento.';
  END IF;
  INSERT INTO public.fiscal_document_lines(document_id,item_id,description,quantity,unit,unit_price,discount_amount,tax_code,tax_rate,taxable_amount,tax_amount,line_total)
  VALUES(v_doc_id,v_item_id,v_description,v_qty,v_unit,v_price,v_discount,v_tax_code,v_rate,v_taxable,v_tax,round(v_taxable+v_tax,2));
  v_subtotal:=v_subtotal+v_gross; v_discount_total:=v_discount_total+v_discount; v_tax_total:=v_tax_total+v_tax;
 END LOOP;
 v_grand_total:=round(v_subtotal-v_discount_total+v_tax_total,2);
 UPDATE public.fiscal_documents SET subtotal=v_subtotal,discount_total=v_discount_total,tax_total=v_tax_total,grand_total=v_grand_total,updated_at=now() WHERE id=v_doc_id AND tenant_id=v_tenant_id;
 INSERT INTO public.document_events(tenant_id,document_id,event_type,actor_id,payload) VALUES(v_tenant_id,v_doc_id,'draft_created',auth.uid(),jsonb_build_object('document_type',p_document_type,'tax_regime',v_regime,'tax_total',v_tax_total));
 INSERT INTO public.audit_events(tenant_id,actor_user_id,event_type,target_type,target_id,details) VALUES(v_tenant_id,auth.uid(),'document.draft_created','fiscal_document',v_doc_id,jsonb_build_object('document_type',p_document_type,'line_count',jsonb_array_length(p_lines),'tax_regime',v_regime));
 RETURN v_doc_id;
END;$function$;
REVOKE ALL ON FUNCTION public.create_fiscal_document_draft(uuid,text,date,text,jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_fiscal_document_draft(uuid,text,date,text,jsonb,uuid) TO authenticated;
COMMIT;