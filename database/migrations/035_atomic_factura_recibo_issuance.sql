-- Atomic Factura-Recibo issuance: fiscal issuance and full payment are one Postgres transaction.
-- The existing fiscal authorization, company/customer checks, document snapshot and series logic remain authoritative.
DO $migration$
DECLARE
  v_definition text;
  v_old_fr text := $old$IF v_doc.document_type='FR' THEN RAISE EXCEPTION 'A emissão de Factura-Recibo está temporariamente bloqueada até a integração transaccional do comprovativo de pagamento.'; END IF;$old$;
  v_new_fr text := $new$IF v_doc.document_type='FR' AND coalesce(pg_catalog.current_setting('app.facturaexpress_fr_payment',true),'off') <> 'on' THEN RAISE EXCEPTION 'A Factura-Recibo só pode ser emitida juntamente com o registo transaccional do pagamento.'; END IF;$new$;
  v_old_type text := $old$IF v_doc.document_type<>'FT' THEN RAISE EXCEPTION 'Tipo documental ainda não habilitado para emissão fiscal.'; END IF;$old$;
  v_new_type text := $new$IF v_doc.document_type NOT IN ('FT','FR') THEN RAISE EXCEPTION 'Tipo documental ainda não habilitado para emissão fiscal.'; END IF;$new$;
BEGIN
  SELECT pg_catalog.pg_get_functiondef('public.issue_fiscal_document(uuid,text)'::regprocedure) INTO v_definition;
  IF position(v_old_fr in v_definition)=0 OR position(v_old_type in v_definition)=0 THEN
    RAISE EXCEPTION 'A definição actual de issue_fiscal_document não corresponde à versão esperada; migração cancelada.';
  END IF;
  v_definition := replace(v_definition,v_old_fr,v_new_fr);
  v_definition := replace(v_definition,v_old_type,v_new_type);
  EXECUTE v_definition;
END;
$migration$;

CREATE OR REPLACE FUNCTION public.issue_fiscal_document_with_payment(
  p_document_id uuid,
  p_software_version text,
  p_amount numeric,
  p_payment_method text,
  p_payment_reference text,
  p_notes text,
  p_received_at timestamptz,
  p_client_operation_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_tenant uuid;
  v_role text;
  v_doc public.fiscal_documents%ROWTYPE;
  v_existing public.customer_payments%ROWTYPE;
  v_issue jsonb;
  v_payment_id uuid;
  v_receipt_code text;
  v_expected numeric(18,2);
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Sessão inválida.'; END IF;
  SELECT tu.tenant_id,tu.role INTO v_tenant,v_role
  FROM public.tenant_users tu
  JOIN public.tenants t ON t.id=tu.tenant_id AND t.status='active'
  WHERE tu.user_id=v_user
  ORDER BY tu.created_at LIMIT 1;
  IF v_tenant IS NULL OR NOT private.is_tenant_member(v_tenant) THEN
    RAISE EXCEPTION 'Utilizador sem empresa activa.';
  END IF;
  IF v_role NOT IN ('owner','admin','issuer','accountant') THEN
    RAISE EXCEPTION 'Sem permissão para emitir documentos fiscais.';
  END IF;
  IF p_client_operation_id IS NULL THEN RAISE EXCEPTION 'Identificador da operação obrigatório.'; END IF;
  IF p_payment_method NOT IN ('cash','bank_transfer','mobile_money','pos','cheque','other') THEN
    RAISE EXCEPTION 'Meio de pagamento inválido.';
  END IF;
  IF p_amount IS NULL OR p_amount<=0 OR p_amount<>round(p_amount,2) THEN
    RAISE EXCEPTION 'O valor recebido deve ser positivo e ter no máximo duas casas decimais.';
  END IF;

  SELECT * INTO v_doc
  FROM public.fiscal_documents
  WHERE id=p_document_id AND tenant_id=v_tenant
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Documento não encontrado nesta empresa.'; END IF;
  IF v_doc.document_type<>'FR' THEN RAISE EXCEPTION 'Esta operação está reservada a Facturas-Recibo.'; END IF;

  SELECT * INTO v_existing
  FROM public.customer_payments
  WHERE tenant_id=v_tenant AND local_operation_id=p_client_operation_id;
  IF FOUND THEN
    IF v_existing.document_id<>p_document_id OR v_existing.amount<>p_amount OR v_existing.payment_method<>p_payment_method THEN
      RAISE EXCEPTION 'O identificador da operação já foi utilizado com outros dados.';
    END IF;
    RETURN jsonb_build_object(
      'document',jsonb_build_object('id',v_doc.id,'document_number',v_doc.document_number,'status',v_doc.status,'idempotent',true),
      'payment_id',v_existing.id,'internal_receipt_code',v_existing.internal_receipt_code,'idempotent',true
    );
  END IF;

  IF v_doc.status<>'draft' THEN RAISE EXCEPTION 'A Factura-Recibo já foi processada ou não está em rascunho.'; END IF;
  v_expected := round(coalesce(v_doc.grand_total,0)-coalesce(v_doc.withholding_total,0),2);
  IF v_expected<=0 OR p_amount<>v_expected THEN
    RAISE EXCEPTION 'A Factura-Recibo exige a liquidação integral do valor devido (%).',v_expected;
  END IF;

  -- The flag is transaction-local and only set inside this restricted wrapper.
  PERFORM pg_catalog.set_config('app.facturaexpress_fr_payment','on',true);
  v_issue := public.issue_fiscal_document(p_document_id,p_software_version);
  PERFORM pg_catalog.set_config('app.facturaexpress_fr_payment','off',true);

  -- If payment insertion or validation fails, PostgreSQL rolls back the issue, series counter,
  -- snapshot, events and audit records from the preceding call as part of this same transaction.
  v_payment_id := public.register_customer_payment(
    p_document_id,p_amount,p_payment_method,p_payment_reference,p_notes,
    coalesce(p_received_at,pg_catalog.now()),p_client_operation_id
  );
  SELECT internal_receipt_code INTO v_receipt_code
  FROM public.customer_payments
  WHERE id=v_payment_id AND tenant_id=v_tenant;

  RETURN jsonb_build_object(
    'document',v_issue,
    'payment_id',v_payment_id,
    'internal_receipt_code',v_receipt_code,
    'idempotent',false
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.issue_fiscal_document_with_payment(uuid,text,numeric,text,text,text,timestamptz,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.issue_fiscal_document_with_payment(uuid,text,numeric,text,text,text,timestamptz,uuid) TO authenticated;
