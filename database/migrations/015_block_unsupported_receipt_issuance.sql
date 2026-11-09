CREATE OR REPLACE FUNCTION public.issue_fiscal_document(p_document_id uuid,p_software_version text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,private,pg_temp AS $$
DECLARE
 v_user uuid:=auth.uid(); v_tenant uuid; v_role text; v_doc public.fiscal_documents%ROWTYPE;
 v_company public.tenants%ROWTYPE; v_customer public.customers%ROWTYPE;
 v_auth public.tenant_fiscal_authorizations%ROWTYPE; v_series public.document_series%ROWTYPE;
 v_no bigint; v_number text; v_date timestamptz:=now(); v_lines jsonb; v_snapshot jsonb;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Sessão inválida.'; END IF;
 SELECT tu.tenant_id,tu.role INTO v_tenant,v_role FROM public.tenant_users tu JOIN public.tenants t ON t.id=tu.tenant_id AND t.status='active' WHERE tu.user_id=v_user ORDER BY tu.created_at LIMIT 1;
 IF v_tenant IS NULL OR NOT private.is_tenant_member(v_tenant) THEN RAISE EXCEPTION 'Utilizador sem empresa activa.'; END IF;
 IF v_role NOT IN ('owner','admin','issuer','accountant') THEN RAISE EXCEPTION 'Sem permissão para emitir documentos fiscais.'; END IF;
 SELECT * INTO v_doc FROM public.fiscal_documents WHERE id=p_document_id AND tenant_id=v_tenant FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Documento não encontrado.'; END IF;
 IF v_doc.status IN ('issued','paid','partially_paid') THEN RETURN jsonb_build_object('id',v_doc.id,'document_number',v_doc.document_number,'status',v_doc.status,'idempotent',true); END IF;
 IF v_doc.status<>'draft' THEN RAISE EXCEPTION 'Estado do documento não permite emissão.'; END IF;
 IF v_doc.document_type='FR' THEN RAISE EXCEPTION 'A emissão de Factura-Recibo está temporariamente bloqueada até a integração transaccional do comprovativo de pagamento.'; END IF;
 IF v_doc.document_type<>'FT' THEN RAISE EXCEPTION 'Tipo documental ainda não habilitado para emissão fiscal.'; END IF;
 IF nullif(trim(p_software_version),'') IS NULL THEN RAISE EXCEPTION 'Versão do software não indicada.'; END IF;
 SELECT * INTO v_auth FROM public.tenant_fiscal_authorizations WHERE tenant_id=v_tenant;
 IF NOT FOUND OR v_auth.status<>'approved' OR nullif(trim(v_auth.authorization_reference),'') IS NULL OR v_auth.authorization_date IS NULL OR v_auth.approved_software_version IS DISTINCT FROM p_software_version THEN
  RAISE EXCEPTION 'EMISSÃO BLOQUEADA: falta autorização/certificação aplicável da AT para esta versão do FacturaExpress.';
 END IF;
 SELECT * INTO v_company FROM public.tenants WHERE id=v_tenant;
 IF nullif(trim(v_company.legal_name),'') IS NULL OR nullif(trim(v_company.nuit),'') IS NULL OR nullif(trim(v_company.address),'') IS NULL THEN RAISE EXCEPTION 'Complete denominação legal, NUIT e endereço da empresa.'; END IF;
 IF v_doc.currency<>'MZN' THEN RAISE EXCEPTION 'A emissão fiscal nesta configuração exige valores em Meticais (MZN).'; END IF;
 IF v_doc.customer_id IS NULL THEN RAISE EXCEPTION 'Identifique o adquirente antes da emissão.'; END IF;
 SELECT * INTO v_customer FROM public.customers WHERE id=v_doc.customer_id AND tenant_id=v_tenant;
 IF NOT FOUND OR nullif(trim(v_customer.name),'') IS NULL OR nullif(trim(v_customer.nuit),'') IS NULL OR nullif(trim(v_customer.address),'') IS NULL THEN RAISE EXCEPTION 'O adquirente deve ter nome, NUIT e domicílio preenchidos. As excepções para consumidor final serão parametrizadas após validação legal.'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('description',l.description,'quantity',l.quantity,'unit',l.unit,'unit_price',l.unit_price,'discount_amount',l.discount_amount,'tax_code',l.tax_code,'tax_rate',l.tax_rate,'taxable_amount',l.taxable_amount,'tax_amount',l.tax_amount,'line_total',l.line_total) ORDER BY l.id),'[]'::jsonb) INTO v_lines FROM public.fiscal_document_lines l WHERE l.document_id=v_doc.id;
 IF jsonb_array_length(v_lines)=0 THEN RAISE EXCEPTION 'O documento não contém linhas.'; END IF;
 IF EXISTS(SELECT 1 FROM public.fiscal_document_lines l WHERE l.document_id=v_doc.id AND (nullif(trim(l.tax_code),'') IS NULL OR l.tax_rate IS NULL)) THEN RAISE EXCEPTION 'Classifique fiscalmente todas as linhas, incluindo fundamento de isenção/não sujeição, antes da emissão.'; END IF;
 SELECT * INTO v_series FROM public.document_series WHERE tenant_id=v_tenant AND document_type=v_doc.document_type AND status='active' AND fiscal_year=extract(year FROM(v_date AT TIME ZONE 'Africa/Maputo'))::integer ORDER BY created_at LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Não existe série activa para este tipo documental e exercício fiscal.'; END IF;
 UPDATE public.document_series SET next_number=next_number+1 WHERE id=v_series.id RETURNING next_number-1 INTO v_no;
 v_number:=v_series.series_code||'/'||v_series.fiscal_year::text||'/'||lpad(v_no::text,6,'0');
 v_snapshot:=jsonb_build_object('software','FacturaExpress','software_version',p_software_version,'authorization_reference',v_auth.authorization_reference,'authorization_date',v_auth.authorization_date,'issuer',jsonb_build_object('legal_name',v_company.legal_name,'trade_name',v_company.trade_name,'nuit',v_company.nuit,'address',v_company.address,'email',v_company.email,'phone',v_company.phone),'customer',jsonb_build_object('name',v_customer.name,'nuit',v_customer.nuit,'address',v_customer.address,'email',v_customer.email,'phone',v_customer.phone),'lines',v_lines,'document_type',v_doc.document_type,'document_number',v_number,'issue_date',v_date,'currency','MZN','subtotal',v_doc.subtotal,'discount_total',v_doc.discount_total,'tax_total',v_doc.tax_total,'withholding_total',v_doc.withholding_total,'grand_total',v_doc.grand_total);
 UPDATE public.fiscal_documents SET series_id=v_series.id,document_number=v_number,status='issued',issue_date=v_date,issued_snapshot=v_snapshot,updated_at=now() WHERE id=v_doc.id AND tenant_id=v_tenant AND status='draft';
 INSERT INTO public.document_events(tenant_id,document_id,event_type,actor_id,payload) VALUES(v_tenant,v_doc.id,'fiscal_document_issued',v_user,jsonb_build_object('document_number',v_number,'series',v_series.series_code,'fiscal_year',v_series.fiscal_year,'authorization_reference',v_auth.authorization_reference));
 INSERT INTO public.audit_events(tenant_id,actor_user_id,event_type,target_type,target_id,details) VALUES(v_tenant,v_user,'document.fiscal_issued','fiscal_document',v_doc.id,jsonb_build_object('document_number',v_number,'software_version',p_software_version));
 RETURN jsonb_build_object('id',v_doc.id,'document_number',v_number,'status','issued','idempotent',false);
END;$$;
REVOKE ALL ON FUNCTION public.issue_fiscal_document(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.issue_fiscal_document(uuid,text) TO authenticated;