BEGIN;
DROP POLICY IF EXISTS treasury_accounts_insert_admin ON public.treasury_accounts;
DROP INDEX IF EXISTS public.treasury_accounts_created_by_idx;
CREATE INDEX IF NOT EXISTS treasury_accounts_created_by_idx ON public.treasury_accounts(created_by);
CREATE INDEX IF NOT EXISTS treasury_movements_destination_fk_idx ON public.treasury_movements(tenant_id,destination_account_id);
CREATE INDEX IF NOT EXISTS treasury_movements_created_by_idx ON public.treasury_movements(created_by);
COMMIT;