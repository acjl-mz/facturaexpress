BEGIN;
DROP POLICY IF EXISTS treasury_movements_insert_authorized ON public.treasury_movements;
CREATE POLICY treasury_movements_insert_authorized ON public.treasury_movements FOR INSERT TO authenticated WITH CHECK (
 private.is_tenant_member(treasury_movements.tenant_id)
 AND treasury_movements.created_by=(select auth.uid())
 AND EXISTS (SELECT 1 FROM public.treasury_accounts a WHERE a.id=treasury_movements.account_id AND a.tenant_id=treasury_movements.tenant_id AND a.active)
 AND (treasury_movements.destination_account_id IS NULL OR EXISTS (SELECT 1 FROM public.treasury_accounts d WHERE d.id=treasury_movements.destination_account_id AND d.tenant_id=treasury_movements.tenant_id AND d.active))
);
COMMIT;