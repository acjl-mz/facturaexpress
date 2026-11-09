BEGIN;
ALTER TABLE public.treasury_movements ADD CONSTRAINT treasury_movements_tenant_id_id_key UNIQUE (tenant_id,id);
CREATE TABLE IF NOT EXISTS public.invoice_templates (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
 name text NOT NULL CHECK (length(trim(name)) BETWEEN 2 AND 80),
 description text,
 is_default boolean NOT NULL DEFAULT false,
 is_active boolean NOT NULL DEFAULT true,
 settings jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (tenant_id,id),
 CHECK (jsonb_typeof(settings)='object')
);
CREATE UNIQUE INDEX IF NOT EXISTS invoice_templates_one_default_per_tenant ON public.invoice_templates(tenant_id) WHERE is_default AND is_active;
CREATE INDEX IF NOT EXISTS invoice_templates_tenant_active_idx ON public.invoice_templates(tenant_id,is_active,name);
ALTER TABLE public.invoice_templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS invoice_templates_select_member ON public.invoice_templates;
CREATE POLICY invoice_templates_select_member ON public.invoice_templates FOR SELECT TO authenticated USING (private.is_tenant_member(tenant_id));
DROP POLICY IF EXISTS invoice_templates_insert_admin ON public.invoice_templates;
CREATE POLICY invoice_templates_insert_admin ON public.invoice_templates FOR INSERT TO authenticated WITH CHECK (private.is_tenant_admin(tenant_id) AND created_by=(select auth.uid()));
DROP POLICY IF EXISTS invoice_templates_update_admin ON public.invoice_templates;
CREATE POLICY invoice_templates_update_admin ON public.invoice_templates FOR UPDATE TO authenticated USING (private.is_tenant_admin(tenant_id)) WITH CHECK (private.is_tenant_admin(tenant_id));
DROP POLICY IF EXISTS invoice_templates_delete_admin ON public.invoice_templates;
CREATE POLICY invoice_templates_delete_admin ON public.invoice_templates FOR DELETE TO authenticated USING (private.is_tenant_admin(tenant_id));
REVOKE ALL ON public.invoice_templates FROM anon;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.invoice_templates TO authenticated;
CREATE TABLE IF NOT EXISTS public.bank_statement_lines (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
 account_id uuid NOT NULL,
 transaction_date timestamptz NOT NULL,
 description text NOT NULL CHECK (length(trim(description)) BETWEEN 2 AND 240),
 reference text,
 amount numeric(18,2) NOT NULL CHECK (amount<>0 AND amount=round(amount,2)),
 matched_movement_id uuid,
 reconciliation_status text NOT NULL DEFAULT 'open' CHECK (reconciliation_status IN ('open','matched','ignored')),
 notes text,
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (tenant_id,account_id) REFERENCES public.treasury_accounts(tenant_id,id) ON DELETE RESTRICT,
 FOREIGN KEY (tenant_id,matched_movement_id) REFERENCES public.treasury_movements(tenant_id,id) ON DELETE RESTRICT,
 CHECK ((reconciliation_status='matched' AND matched_movement_id IS NOT NULL) OR (reconciliation_status<>'matched' AND matched_movement_id IS NULL))
);
CREATE INDEX IF NOT EXISTS bank_statement_lines_tenant_date_idx ON public.bank_statement_lines(tenant_id,account_id,transaction_date DESC);
CREATE INDEX IF NOT EXISTS bank_statement_lines_status_idx ON public.bank_statement_lines(tenant_id,reconciliation_status,transaction_date);
CREATE UNIQUE INDEX IF NOT EXISTS bank_statement_lines_one_match_idx ON public.bank_statement_lines(tenant_id,matched_movement_id) WHERE matched_movement_id IS NOT NULL;
ALTER TABLE public.bank_statement_lines ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bank_statement_lines_select_member ON public.bank_statement_lines;
CREATE POLICY bank_statement_lines_select_member ON public.bank_statement_lines FOR SELECT TO authenticated USING (private.is_tenant_member(tenant_id));
DROP POLICY IF EXISTS bank_statement_lines_insert_finance ON public.bank_statement_lines;
CREATE POLICY bank_statement_lines_insert_finance ON public.bank_statement_lines FOR INSERT TO authenticated WITH CHECK (
 private.is_tenant_member(tenant_id) AND created_by=(select auth.uid())
 AND EXISTS (SELECT 1 FROM public.tenant_users tu WHERE tu.tenant_id=bank_statement_lines.tenant_id AND tu.user_id=(select auth.uid()) AND tu.role IN ('owner','admin','accountant'))
);
REVOKE ALL ON public.bank_statement_lines FROM anon,authenticated;
GRANT SELECT,INSERT ON public.bank_statement_lines TO authenticated;
CREATE OR REPLACE FUNCTION public.reconcile_bank_statement_line(p_line_id uuid,p_movement_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE v_user uuid:=auth.uid();v_tenant uuid;v_line public.bank_statement_lines%ROWTYPE;v_move public.treasury_movements%ROWTYPE;v_signed numeric(18,2);
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Sessão inválida.'; END IF;
 SELECT tu.tenant_id INTO v_tenant FROM public.tenant_users tu JOIN public.tenants t ON t.id=tu.tenant_id
 WHERE tu.user_id=v_user AND t.status='active' AND tu.role IN ('owner','admin','accountant') ORDER BY tu.created_at LIMIT 1;
 IF v_tenant IS NULL THEN RAISE EXCEPTION 'Sem permissão para reconciliar.'; END IF;
 SELECT * INTO v_line FROM public.bank_statement_lines WHERE id=p_line_id AND tenant_id=v_tenant FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Linha de extracto não encontrada.'; END IF;
 IF p_movement_id IS NULL THEN
  UPDATE public.bank_statement_lines SET matched_movement_id=NULL,reconciliation_status='open',updated_at=now() WHERE id=p_line_id AND tenant_id=v_tenant;
  RETURN p_line_id;
 END IF;
 SELECT * INTO v_move FROM public.treasury_movements WHERE id=p_movement_id AND tenant_id=v_tenant FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Movimento não encontrado nesta empresa.'; END IF;
 IF v_line.account_id=v_move.account_id THEN v_signed:=CASE WHEN v_move.movement_type='income' THEN v_move.amount ELSE -v_move.amount END;
 ELSIF v_line.account_id=v_move.destination_account_id AND v_move.movement_type='transfer' THEN v_signed:=v_move.amount;
 ELSE RAISE EXCEPTION 'O movimento não pertence à conta do extracto.'; END IF;
 IF round(v_signed,2)<>round(v_line.amount,2) THEN RAISE EXCEPTION 'O valor ou o sentido do movimento não coincide com o extracto.'; END IF;
 UPDATE public.bank_statement_lines SET matched_movement_id=p_movement_id,reconciliation_status='matched',updated_at=now() WHERE id=p_line_id AND tenant_id=v_tenant;
 INSERT INTO public.audit_events(tenant_id,actor_user_id,event_type,target_type,target_id,details)
 VALUES(v_tenant,v_user,'treasury.bank_line_reconciled','bank_statement_line',p_line_id,jsonb_build_object('movement_id',p_movement_id));
 RETURN p_line_id;
END;$function$;
REVOKE ALL ON FUNCTION public.reconcile_bank_statement_line(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reconcile_bank_statement_line(uuid,uuid) TO authenticated;
COMMIT;