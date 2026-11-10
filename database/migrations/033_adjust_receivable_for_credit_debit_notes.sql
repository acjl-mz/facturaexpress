-- 033: notas rectificativas emitidas ajustam o saldo da factura original.
create or replace function public.register_customer_payment(
 p_document_id uuid,p_amount numeric,p_payment_method text,p_payment_reference text,p_notes text,p_received_at timestamptz,p_client_operation_id uuid
) returns uuid language plpgsql security definer set search_path='' as $function$
declare
 v_user_id uuid:=auth.uid();v_tenant_id uuid;v_status text;v_doc_number text;
 v_grand_total numeric(18,2);v_withholding numeric(18,2);v_paid numeric(18,2);
 v_adjustment numeric(18,2);v_balance numeric(18,2);
 v_existing public.customer_payments%rowtype;v_payment_id uuid;v_code text;
begin
 if v_user_id is null then raise exception 'Sessão inválida.';end if;
 select m.tenant_id into v_tenant_id from public.tenant_users m join public.tenants t on t.id=m.tenant_id where m.user_id=v_user_id and t.status='active' order by m.created_at asc limit 1;
 if v_tenant_id is null then raise exception 'Utilizador sem empresa activa.';end if;
 if p_client_operation_id is null then raise exception 'Identificador da operação obrigatório.';end if;
 if p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2) then raise exception 'O valor recebido deve ser positivo e ter no máximo duas casas decimais.';end if;
 if p_payment_method not in ('cash','bank_transfer','mobile_money','pos','cheque','other') then raise exception 'Meio de pagamento inválido.';end if;
 select * into v_existing from public.customer_payments where tenant_id=v_tenant_id and local_operation_id=p_client_operation_id;
 if found then if v_existing.document_id<>p_document_id or v_existing.amount<>p_amount or v_existing.payment_method<>p_payment_method then raise exception 'O identificador da operação já foi utilizado com outros dados.';end if;return v_existing.id;end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_document_id::text,0));
 select * into v_existing from public.customer_payments where tenant_id=v_tenant_id and local_operation_id=p_client_operation_id;
 if found then if v_existing.document_id<>p_document_id or v_existing.amount<>p_amount or v_existing.payment_method<>p_payment_method then raise exception 'O identificador da operação já foi utilizado com outros dados.';end if;return v_existing.id;end if;
 select d.status,d.document_number,d.grand_total,d.withholding_total into v_status,v_doc_number,v_grand_total,v_withholding from public.fiscal_documents d where d.id=p_document_id and d.tenant_id=v_tenant_id for update;
 if not found then raise exception 'Documento não encontrado nesta empresa.';end if;
 if v_status not in ('issued','partially_paid') or v_doc_number is null then raise exception 'Só é possível registar recebimentos em documentos fiscalmente emitidos.';end if;
 select coalesce(sum(p.amount),0) into v_paid from public.customer_payments p where p.tenant_id=v_tenant_id and p.document_id=p_document_id;
 select coalesce(sum(case when c.document_type='ND' then c.grand_total when c.document_type='NC' then -c.grand_total else 0 end),0) into v_adjustment from public.fiscal_documents c where c.tenant_id=v_tenant_id and c.corrects_document_id=p_document_id and c.status in ('issued','paid','partially_paid');
 v_balance:=round(v_grand_total-coalesce(v_withholding,0)+v_adjustment-v_paid,2);
 if v_balance<=0 then raise exception 'Este documento não tem saldo em dívida após rectificações e recebimentos.';end if;
 if p_amount>v_balance then raise exception 'O valor excede o saldo em dívida após rectificações (%).',v_balance;end if;
 v_payment_id:=gen_random_uuid();v_code:='PG-INT-'||to_char(coalesce(p_received_at,now()) at time zone 'Africa/Maputo','YYYYMM')||'-'||upper(substr(replace(v_payment_id::text,'-',''),1,8));
 insert into public.customer_payments(id,tenant_id,document_id,internal_receipt_code,amount,payment_method,payment_reference,notes,received_at,local_operation_id,created_by) values(v_payment_id,v_tenant_id,p_document_id,v_code,p_amount,p_payment_method,nullif(trim(p_payment_reference),''),nullif(trim(p_notes),''),coalesce(p_received_at,now()),p_client_operation_id,v_user_id);
 select coalesce(sum(p.amount),0) into v_paid from public.customer_payments p where p.tenant_id=v_tenant_id and p.document_id=p_document_id;
 v_balance:=round(v_grand_total-coalesce(v_withholding,0)+v_adjustment-v_paid,2);
 update public.fiscal_documents set status=case when v_balance=0 then 'paid' else 'partially_paid' end,updated_at=now() where id=p_document_id and tenant_id=v_tenant_id;
 insert into public.document_events(tenant_id,document_id,event_type,actor_id,payload) values(v_tenant_id,p_document_id,'payment_received',v_user_id,jsonb_build_object('payment_id',v_payment_id,'amount',p_amount,'internal_reference',v_code,'method',p_payment_method,'remaining_balance',v_balance,'correction_adjustment',v_adjustment));
 insert into public.audit_events(tenant_id,actor_user_id,event_type,target_type,target_id,details) values(v_tenant_id,v_user_id,'payment.received','customer_payment',v_payment_id,jsonb_build_object('document_id',p_document_id,'amount',p_amount,'method',p_payment_method,'remaining_balance',v_balance,'correction_adjustment',v_adjustment));
 return v_payment_id;
end;$function$;
revoke all on function public.register_customer_payment(uuid,numeric,text,text,text,timestamptz,uuid) from public,anon;
grant execute on function public.register_customer_payment(uuid,numeric,text,text,text,timestamptz,uuid) to authenticated;