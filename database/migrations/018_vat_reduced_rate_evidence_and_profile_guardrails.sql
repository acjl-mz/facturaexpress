BEGIN;
ALTER TABLE public.fiscal_document_lines ADD COLUMN IF NOT EXISTS tax_eligibility_reference text;
DO $$
DECLARE v_def text;
BEGIN
 v_def:=pg_get_functiondef('public.issue_fiscal_document(uuid,text)'::regprocedure);
 v_def:=replace(v_def,'''tax_code'',l.tax_code,''tax_rate''','''tax_code'',l.tax_code,''tax_eligibility_reference'',l.tax_eligibility_reference,''tax_rate''');
 EXECUTE v_def;
END $$;
CREATE OR REPLACE FUNCTION public.create_fiscal_document_draft(p_customer_id uuid,p_document_type text,p_due_date date,p_notes text,p_lines jsonb,p_client_operation_id uuid)
RETURNS uuid LANGUAGE plpgsql SET search_path=public,private AS $function$
DECLARE
 v_tenant_id uuid;v_doc_id uuid;v_line jsonb;v_item_id uuid;v_description text;v_unit text;v_qty numeric(18,4);v_price numeric(18,4);v_discount numeric(18,2);v_gross numeric(18,2);v_taxable numeric(18,2);v_rate numeric(9,4);v_tax numeric(18,2);v_tax_code text;v_tax_type text;v_eligibility_ref text;v_subtotal numeric(18,2):=0;v_discount_total numeric(18,2):=0;v_tax_total numeric(18,2):=0;v_grand_total numeric(18,2):=0;v_profile public.tenant_tax_profiles%ROWTYPE;v_rule public.tax_rules%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão inválida.'; END IF;
 SELECT tenant_id INTO v_tenant_id FROM public.tenant_users WHERE user_id=auth.uid() ORDER BY created_at LIMIT 1;
 IF v_tenant_id IS NULL OR NOT private.is_tenant_member(v_tenant_id) THEN RAISE EXCEPTION 'Utilizador sem empresa activa.'; END IF;
 IF p_document_type NOT IN ('FT','FR') THEN RAISE EXCEPTION 'Tipo de documento não permitido nesta fase.'; END IF;
 IF jsonb_typeof(p_lines)<>'array' OR jsonb_array_length(p_lines)<1 OR jsonb_array_length(p_lines)>100 THEN RAISE EXCEPTION 'O documento deve conter entre 1 e 100 linhas.'; END IF;
 IF p_client_operation_id IS NOT NULL THEN SELECT id INTO v_doc_id FROM public.fiscal_documents WHERE tenant_id=v_tenant_id AND local_operation_id=p_client_operation_id; IF v_doc_id IS NOT NULL THEN RETURN v_doc_id; END IF; END IF;
 IF p_customer_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.customers WHERE id=p_customer_id AND tenant_id=v_tenant_id) THEN RAISE EXCEPTION 'Cliente inválido para esta empresa.'; END IF;
 SELECT * INTO v_profile FROM public.tenant_tax_profiles WHERE tenant_id=v_tenant_id;
 IF NOT FOUND OR v_profile.confirmation_status<>'confirmed' THEN RAISE EXCEPTION 'Configure e confirme o perfil fiscal da empresa antes de preparar documentos.'; END IF;
 INSERT INTO public.fiscal_documents(tenant_id,customer_id,document_type,status,due_date,currency,notes,local_operation_id,created_by)
 VALUES(v_tenant_id,p_customer_id,p_document_type,'draft',p_due_date,'MZN',nullif(trim(p_notes),''),p_client_operation_id,auth.uid()) RETURNING id INTO v_doc_id;
 FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
  v_item_id:=nullif(v_line->>'item_id','')::uuid;v_description:=trim(coalesce(v_line->>'description',''));v_unit:=coalesce(nullif(trim(v_line->>'unit'),''),'UN');v_qty:=(v_line->>'quantity')::numeric;v_price:=(v_line->>'unit_price')::numeric;v_discount:=coalesce(nullif(v_line->>'discount_amount','')::numeric,0);v_tax_code:=nullif(trim(v_line->>'tax_code'),'');v_eligibility_ref:=nullif(trim(v_line->>'tax_eligibility_reference'),'');
  IF v_description='' OR v_qty<=0 OR v_price<0 THEN RAISE EXCEPTION 'Descrição, quantidade ou preço inválido.'; END IF;
  IF v_item_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.items WHERE id=v_item_id AND tenant_id=v_tenant_id AND active) THEN RAISE EXCEPTION 'Artigo inválido para esta empresa.'; END IF;
  v_gross:=round(v_qty*v_price,2);IF v_discount<0 OR v_discount>v_gross THEN RAISE EXCEPTION 'Desconto inválido.';END IF;v_taxable:=round(v_gross-v_discount,2);v_rate:=0;v_tax:=0;v_tax_type:=NULL;
  IF v_profile.regime_code='ISPC' THEN
   IF v_tax_code IS NOT NULL THEN RAISE EXCEPTION 'O regime ISPC não inclui IVA nas facturas. Remova a classificação IVA.';END IF;
  ELSIF v_profile.regime_code='IVA_REGULAR' THEN
   IF v_tax_code IS NULL THEN RAISE EXCEPTION 'Classifique fiscalmente cada linha antes de guardar.';END IF;
   SELECT * INTO v_rule FROM public.tax_rules WHERE code=v_tax_code AND (tenant_id=v_tenant_id OR tenant_id IS NULL) AND active AND validation_status='approved' AND valid_from<=current_date AND (valid_to IS NULL OR valid_to>=current_date) ORDER BY (tenant_id IS NOT NULL) DESC,valid_from DESC LIMIT 1;
   IF NOT FOUND OR v_rule.rate IS NULL OR v_rule.tax_type<>'IVA' THEN RAISE EXCEPTION 'Regra de IVA não aprovada, inválida ou fora da vigência: %.',v_tax_code;END IF;
   IF v_tax_code='IVA_RED_5' AND v_eligibility_ref IS NULL THEN RAISE EXCEPTION 'A taxa reduzida de 5%% exige referência documental que comprove a categoria legal elegível.';END IF;
   v_rate:=v_rule.rate;v_tax_type:=v_rule.tax_type;v_tax:=round(v_taxable*v_rate/100,2);
  ELSIF v_profile.regime_code='IVA_EXEMPT' THEN
   RAISE EXCEPTION 'O antigo regime geral de isenção de IVA foi revogado. Confirme o enquadramento transitório aplicável e configure IVA regular ou outro fundamento legal específico.';
  ELSE RAISE EXCEPTION 'O regime fiscal seleccionado ainda não permite preparar documentos neste fluxo. Solicite revisão do enquadramento.';END IF;
  INSERT INTO public.fiscal_document_lines(document_id,item_id,description,quantity,unit,unit_price,discount_amount,tax_code,tax_rate,tax_eligibility_reference,taxable_amount,tax_amount,line_total)
  VALUES(v_doc_id,v_item_id,v_description,v_qty,v_unit,v_price,v_discount,v_tax_code,v_rate,v_eligibility_ref,v_taxable,v_tax,round(v_taxable+v_tax,2));
  v_subtotal:=v_subtotal+v_gross;v_discount_total:=v_discount_total+v_discount;v_tax_total:=v_tax_total+v_tax;
 END LOOP;
 v_grand_total:=round(v_subtotal-v_discount_total+v_tax_total,2);
 UPDATE public.fiscal_documents SET subtotal=v_subtotal,discount_total=v_discount_total,tax_total=v_tax_total,grand_total=v_grand_total,updated_at=now() WHERE id=v_doc_id AND tenant_id=v_tenant_id;
 INSERT INTO public.document_events(tenant_id,document_id,event_type,actor_id,payload) VALUES(v_tenant_id,v_doc_id,'draft_created',auth.uid(),jsonb_build_object('document_type',p_document_type,'tax_regime',v_profile.regime_code,'tax_total',v_tax_total));
 INSERT INTO public.audit_events(tenant_id,actor_user_id,event_type,target_type,target_id,details) VALUES(v_tenant_id,auth.uid(),'document.draft_created','fiscal_document',v_doc_id,jsonb_build_object('document_type',p_document_type,'line_count',jsonb_array_length(p_lines),'tax_regime',v_profile.regime_code));
 RETURN v_doc_id;
END;$function$;
REVOKE ALL ON FUNCTION public.create_fiscal_document_draft(uuid,text,date,text,jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_fiscal_document_draft(uuid,text,date,text,jsonb,uuid) TO authenticated;
COMMIT;