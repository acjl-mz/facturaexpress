-- Atomic editing of draft documents. Issued documents remain immutable.
CREATE OR REPLACE FUNCTION public.update_fiscal_document_draft(
 p_document_id uuid,
 p_customer_id uuid,
 p_due_date date,
 p_notes text,
 p_lines jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path=public
AS $$
DECLARE
 v_tenant_id uuid;
 v_doc public.fiscal_documents%ROWTYPE;
 v_line jsonb;
 v_item_id uuid;
 v_description text;
 v_unit text;
 v_qty numeric(18,4);
 v_price numeric(18,4);
 v_discount numeric(18,2);
 v_gross numeric(18,2);
 v_taxable numeric(18,2);
 v_rate numeric(9,4);
 v_tax numeric(18,2);
 v_tax_code text;
 v_tax_type text;
 v_subtotal numeric(18,2):=0;
 v_discount_total numeric(18,2):=0;
 v_tax_total numeric(18,2):=0;
 v_customer_name text;
 v_regime text;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão inválida.'; END IF;
 SELECT tenant_id INTO v_tenant_id
 FROM public.tenant_users
 WHERE user_id=auth.uid()
 ORDER BY created_at ASC LIMIT 1;
 IF v_tenant_id IS NULL OR NOT private.is_tenant_member(v_tenant_id) THEN
  RAISE EXCEPTION 'Utilizador sem empresa activa.';
 END IF;
 IF jsonb_typeof(p_lines)<>'array' OR jsonb_array_length(p_lines)<1 OR jsonb_array_length(p_lines)>100 THEN
  RAISE EXCEPTION 'O documento deve conter entre 1 e 100 linhas.';
 END IF;
 SELECT * INTO v_doc FROM public.fiscal_documents
 WHERE id=p_document_id AND tenant_id=v_tenant_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Documento não encontrado.'; END IF;
 IF v_doc.status<>'draft' THEN RAISE EXCEPTION 'Apenas rascunhos podem ser alterados.'; END IF;
 IF p_customer_id IS NOT NULL THEN
  SELECT name INTO v_customer_name FROM public.customers
  WHERE id=p_customer_id AND tenant_id=v_tenant_id;
  IF v_customer_name IS NULL THEN RAISE EXCEPTION 'Cliente inválido para esta empresa.'; END IF;
 END IF;
 SELECT tax_regime INTO v_regime FROM public.tenants WHERE id=v_tenant_id;
 DELETE FROM public.fiscal_document_lines WHERE document_id=p_document_id;
 FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
  v_item_id:=nullif(v_line->>'item_id','')::uuid;
  v_description:=trim(coalesce(v_line->>'description',''));
  v_unit:=coalesce(nullif(trim(v_line->>'unit'),''),'UN');
  v_qty:=(v_line->>'quantity')::numeric;
  v_price:=(v_line->>'unit_price')::numeric;
  v_discount:=coalesce(nullif(v_line->>'discount_amount','')::numeric,0);
  v_tax_code:=nullif(trim(v_line->>'tax_code'),'');
  IF v_description='' OR v_qty<=0 OR v_price<0 THEN RAISE EXCEPTION 'Descrição, quantidade ou preço inválido.'; END IF;
  IF v_item_id IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM public.items WHERE id=v_item_id AND tenant_id=v_tenant_id AND active
  ) THEN RAISE EXCEPTION 'Artigo inválido para esta empresa.'; END IF;
  v_gross:=round(v_qty*v_price,2);
  IF v_discount<0 OR v_discount>v_gross THEN RAISE EXCEPTION 'Desconto inválido.'; END IF;
  v_taxable:=round(v_gross-v_discount,2);
  v_rate:=NULL;v_tax_type:=NULL;v_tax:=0;
  IF v_tax_code IS NOT NULL THEN
   SELECT rate,tax_type INTO v_rate,v_tax_type FROM public.tax_rules
   WHERE tenant_id=v_tenant_id AND code=v_tax_code AND active
    AND valid_from<=current_date AND (valid_to IS NULL OR valid_to>=current_date)
   ORDER BY valid_from DESC LIMIT 1;
   IF NOT FOUND OR v_rate IS NULL THEN RAISE EXCEPTION 'Regra fiscal não encontrada ou inválida: %.',v_tax_code; END IF;
   IF upper(v_tax_type)='IVA' AND coalesce(upper(v_regime),'')<>'IVA' THEN
    RAISE EXCEPTION 'Configure e confirme o regime de IVA da empresa antes de aplicar IVA.';
   END IF;
   v_tax:=round(v_taxable*v_rate/100,2);
  END IF;
  INSERT INTO public.fiscal_document_lines(
   document_id,item_id,description,quantity,unit,unit_price,discount_amount,
   tax_code,tax_rate,taxable_amount,tax_amount,line_total
  ) VALUES(
   p_document_id,v_item_id,v_description,v_qty,v_unit,v_price,v_discount,
   v_tax_code,v_rate,v_taxable,v_tax,round(v_taxable+v_tax,2)
  );
  v_subtotal:=v_subtotal+v_gross;
  v_discount_total:=v_discount_total+v_discount;
  v_tax_total:=v_tax_total+v_tax;
 END LOOP;
 UPDATE public.fiscal_documents SET
  customer_id=p_customer_id,due_date=p_due_date,notes=nullif(trim(p_notes),''),
  subtotal=v_subtotal,discount_total=v_discount_total,tax_total=v_tax_total,
  grand_total=round(v_subtotal-v_discount_total+v_tax_total,2),updated_at=now()
 WHERE id=p_document_id AND tenant_id=v_tenant_id AND status='draft';
 INSERT INTO public.document_events(tenant_id,document_id,event_type,actor_id,payload)
 VALUES(v_tenant_id,p_document_id,'draft_updated',auth.uid(),
  jsonb_build_object('line_count',jsonb_array_length(p_lines)));
 INSERT INTO public.audit_events(tenant_id,actor_user_id,event_type,target_type,target_id,details)
 VALUES(v_tenant_id,auth.uid(),'document.draft_updated','fiscal_document',p_document_id,
  jsonb_build_object('line_count',jsonb_array_length(p_lines)));
 RETURN p_document_id;
END;
$$;
REVOKE ALL ON FUNCTION public.update_fiscal_document_draft(uuid,uuid,date,text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_fiscal_document_draft(uuid,uuid,date,text,jsonb) TO authenticated;
