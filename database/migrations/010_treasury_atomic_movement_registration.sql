CREATE OR REPLACE FUNCTION public.register_treasury_movement(
 p_account_id uuid,p_destination_account_id uuid,p_movement_type text,p_category text,p_description text,
 p_amount numeric,p_transaction_date timestamptz,p_reference text,p_notes text,p_client_operation_id uuid
) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public
AS $function$
DECLARE
 v_user uuid:=auth.uid();v_tenant uuid;v_opening numeric(18,2);v_balance numeric(18,2);v_id uuid;v_existing public.treasury_movements%ROWTYPE;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Sessão inválida.'; END IF;
 SELECT tu.tenant_id INTO v_tenant FROM public.tenant_users tu JOIN public.tenants t ON t.id=tu.tenant_id
 WHERE tu.user_id=v_user AND t.status='active' AND tu.role IN ('owner','admin','accountant') ORDER BY tu.created_at LIMIT 1;
 IF v_tenant IS NULL OR NOT private.is_tenant_member(v_tenant) THEN RAISE EXCEPTION 'Sem permissão para movimentar a tesouraria.'; END IF;
 IF p_client_operation_id IS NULL THEN RAISE EXCEPTION 'Identificador idempotente obrigatório.'; END IF;
 IF p_movement_type NOT IN ('income','expense','transfer') OR p_amount IS NULL OR p_amount<=0 OR p_amount<>round(p_amount,2) THEN RAISE EXCEPTION 'Tipo de movimento ou valor inválido.'; END IF;
 IF length(trim(coalesce(p_category,'')))<2 OR length(trim(coalesce(p_description,'')))<2 THEN RAISE EXCEPTION 'Categoria e descrição são obrigatórias.'; END IF;
 SELECT * INTO v_existing FROM public.treasury_movements WHERE tenant_id=v_tenant AND client_operation_id=p_client_operation_id;
 IF FOUND THEN
  IF v_existing.account_id<>p_account_id OR v_existing.destination_account_id IS DISTINCT FROM p_destination_account_id OR v_existing.movement_type<>p_movement_type OR v_existing.amount<>p_amount THEN RAISE EXCEPTION 'Identificador da operação já utilizado com outros dados.'; END IF;
  RETURN v_existing.id;
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_account_id::text,0));
 SELECT opening_balance INTO v_opening FROM public.treasury_accounts WHERE id=p_account_id AND tenant_id=v_tenant AND active FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Conta de origem inválida.'; END IF;
 IF p_movement_type='transfer' THEN
  IF p_destination_account_id IS NULL OR p_destination_account_id=p_account_id OR NOT EXISTS(SELECT 1 FROM public.treasury_accounts WHERE id=p_destination_account_id AND tenant_id=v_tenant AND active) THEN RAISE EXCEPTION 'Conta de destino inválida.'; END IF;
 ELSIF p_destination_account_id IS NOT NULL THEN RAISE EXCEPTION 'Apenas transferências admitem conta de destino.'; END IF;
 SELECT v_opening+COALESCE(sum(CASE WHEN movement_type='income' THEN amount WHEN movement_type IN ('expense','transfer') THEN -amount ELSE 0 END),0)
 INTO v_balance FROM public.treasury_movements WHERE tenant_id=v_tenant AND account_id=p_account_id;
 SELECT v_balance+COALESCE(sum(amount),0) INTO v_balance FROM public.treasury_movements WHERE tenant_id=v_tenant AND destination_account_id=p_account_id AND movement_type='transfer';
 IF p_movement_type IN ('expense','transfer') AND v_balance<p_amount THEN RAISE EXCEPTION 'Saldo insuficiente na conta. Saldo disponível: % MZN.',v_balance; END IF;
 v_id:=gen_random_uuid();
 INSERT INTO public.treasury_movements(id,tenant_id,account_id,destination_account_id,movement_type,category,description,amount,currency,transaction_date,reference,notes,client_operation_id,created_by)
 VALUES(v_id,v_tenant,p_account_id,p_destination_account_id,p_movement_type,trim(p_category),trim(p_description),p_amount,'MZN',COALESCE(p_transaction_date,now()),nullif(trim(p_reference),''),nullif(trim(p_notes),''),p_client_operation_id,v_user);
 INSERT INTO public.audit_events(tenant_id,actor_user_id,event_type,target_type,target_id,details)
 VALUES(v_tenant,v_user,'treasury.movement_created','treasury_movement',v_id,jsonb_build_object('type',p_movement_type,'amount',p_amount,'account_id',p_account_id,'destination_account_id',p_destination_account_id));
 RETURN v_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.register_treasury_movement(uuid,uuid,text,text,text,numeric,timestamptz,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.register_treasury_movement(uuid,uuid,text,text,text,numeric,timestamptz,text,text,uuid) TO authenticated;
