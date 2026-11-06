-- Fase 4: pagamentos e recibos internos de recebimento.
-- Não emite recibo fiscal certificado nem altera a numeração fiscal.
CREATE TABLE IF NOT EXISTS public.customer_payments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenants(id),
 document_id uuid NOT NULL REFERENCES public.fiscal_documents(id),
 internal_receipt_code text NOT NULL UNIQUE,
 amount numeric(18,2) NOT NULL CHECK (amount > 0),
 payment_method text NOT NULL CHECK (payment_method IN ('cash','bank_transfer','mobile_money','pos','cheque','other')),
 payment_reference text,
 notes text,
 received_at timestamptz NOT NULL DEFAULT now(),
 local_operation_id uuid NOT NULL,
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT customer_payments_idempotency UNIQUE (tenant_id,local_operation_id)
);
CREATE INDEX IF NOT EXISTS idx_customer_payments_tenant_date ON public.customer_payments(tenant_id,received_at DESC);
CREATE INDEX IF NOT EXISTS idx_customer_payments_document ON public.customer_payments(tenant_id,document_id,received_at DESC);
CREATE INDEX IF NOT EXISTS idx_customer_payments_document_fk ON public.customer_payments(document_id);
ALTER TABLE public.customer_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS customer_payments_select_member ON public.customer_payments;
CREATE POLICY customer_payments_select_member ON public.customer_payments FOR SELECT TO authenticated USING (private.is_tenant_member(tenant_id));
REVOKE ALL ON public.customer_payments FROM anon,authenticated;
GRANT SELECT ON public.customer_payments TO authenticated;

CREATE OR REPLACE FUNCTION public.register_customer_payment(
 p_document_id uuid,p_amount numeric,p_payment_method text,p_payment_reference text,p_notes text,p_received_at timestamptz,p_client_operation_id uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_user_id uuid:=auth.uid();v_tenant_id uuid;v_status text;v_doc_number text;
 v_grand_total numeric(18,2);v_withholding numeric(18,2);v_paid numeric(18,2);
 v_balance numeric(18,2);v_existing public.customer_payments%ROWTYPE;v_payment_id uuid;v_code text;
BEGIN
 IF v_user_id IS NULL THEN RAISE EXCEPTION 'Sessão inválida.'; END IF;
 SELECT m.tenant_id INTO v_tenant_id FROM public.tenant_users m JOIN public.tenants t ON t.id=m.tenant_id
 WHERE m.user_id=v_user_id AND t.status='active' ORDER BY m.created_at ASC LIMIT 1;
 IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'Utilizador sem empresa activa.'; END IF;
 IF p_client_operation_id IS NULL THEN RAISE EXCEPTION 'Identificador da operação obrigatório.'; END IF;
 IF p_amount IS NULL OR p_amount<=0 OR p_amount<>round(p_amount,2) THEN RAISE EXCEPTION 'O valor recebido deve ser positivo e ter no máximo duas casas decimais.'; END IF;
 IF p_payment_method NOT IN ('cash','bank_transfer','mobile_money','pos','cheque','other') THEN RAISE EXCEPTION 'Meio de pagamento inválido.'; END IF;
 SELECT * INTO v_existing FROM public.customer_payments WHERE tenant_id=v_tenant_id AND local_operation_id=p_client_operation_id;
 IF FOUND THEN
  IF v_existing.document_id<>p_document_id OR v_existing.amount<>p_amount OR v_existing.payment_method<>p_payment_method THEN RAISE EXCEPTION 'O identificador da operação já foi utilizado com outros dados.'; END IF;
  RETURN v_existing.id;
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_document_id::text,0));
 SELECT d.status,d.document_number,d.grand_total,d.withholding_total INTO v_status,v_doc_number,v_grand_total,v_withholding
 FROM public.fiscal_documents d WHERE d.id=p_document_id AND d.tenant_id=v_tenant_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Documento não encontrado nesta empresa.'; END IF;
 IF v_status NOT IN ('issued','partially_paid') OR v_doc_number IS NULL THEN RAISE EXCEPTION 'Só é possível registar recebimentos em documentos fiscalmente emitidos.'; END IF;
 SELECT COALESCE(sum(p.amount),0) INTO v_paid FROM public.customer_payments p WHERE p.tenant_id=v_tenant_id AND p.document_id=p_document_id;
 v_balance:=round(v_grand_total-COALESCE(v_withholding,0)-v_paid,2);
 IF v_balance<=0 THEN RAISE EXCEPTION 'Este documento já se encontra totalmente liquidado.'; END IF;
 IF p_amount>v_balance THEN RAISE EXCEPTION 'O valor excede o saldo em dívida (%).',v_balance; END IF;
 v_payment_id:=gen_random_uuid();
 v_code:='PG-INT-'||to_char(COALESCE(p_received_at,now()) AT TIME ZONE 'Africa/Maputo','YYYYMM')||'-'||upper(substr(replace(v_payment_id::text,'-',''),1,8));
 INSERT INTO public.customer_payments(id,tenant_id,document_id,internal_receipt_code,amount,payment_method,payment_reference,notes,received_at,local_operation_id,created_by)
 VALUES(v_payment_id,v_tenant_id,p_document_id,v_code,p_amount,p_payment_method,nullif(trim(p_payment_reference),''),nullif(trim(p_notes),''),COALESCE(p_received_at,now()),p_client_operation_id,v_user_id);
 SELECT COALESCE(sum(p.amount),0) INTO v_paid FROM public.customer_payments p WHERE p.tenant_id=v_tenant_id AND p.document_id=p_document_id;
 v_balance:=round(v_grand_total-COALESCE(v_withholding,0)-v_paid,2);
 UPDATE public.fiscal_documents SET status=CASE WHEN v_balance=0 THEN 'paid' ELSE 'partially_paid' END,updated_at=now()
 WHERE id=p_document_id AND tenant_id=v_tenant_id;
 INSERT INTO public.document_events(tenant_id,document_id,event_type,actor_id,payload)
 VALUES(v_tenant_id,p_document_id,'payment_received',v_user_id,jsonb_build_object('payment_id',v_payment_id,'amount',p_amount,'internal_reference',v_code,'method',p_payment_method,'remaining_balance',v_balance));
 INSERT INTO public.audit_events(tenant_id,actor_user_id,event_type,target_type,target_id,details)
 VALUES(v_tenant_id,v_user_id,'payment.received','customer_payment',v_payment_id,jsonb_build_object('document_id',p_document_id,'amount',p_amount,'method',p_payment_method,'remaining_balance',v_balance));
 RETURN v_payment_id;
END;$function$;
REVOKE ALL ON FUNCTION public.register_customer_payment(uuid,numeric,text,text,text,timestamptz,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.register_customer_payment(uuid,numeric,text,text,text,timestamptz,uuid) TO authenticated;
