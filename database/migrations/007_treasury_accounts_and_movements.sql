BEGIN;
CREATE TABLE IF NOT EXISTS public.treasury_accounts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
 name text NOT NULL CHECK (length(trim(name)) BETWEEN 2 AND 100),
 account_type text NOT NULL CHECK (account_type IN ('cash','bank','mobile_wallet')),
 institution text,
 account_reference text,
 currency char(3) NOT NULL DEFAULT 'MZN' CHECK (currency='MZN'),
 opening_balance numeric(18,2) NOT NULL DEFAULT 0 CHECK (opening_balance >= 0),
 active boolean NOT NULL DEFAULT true,
 notes text,
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (tenant_id,id)
);
CREATE TABLE IF NOT EXISTS public.treasury_movements (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
 account_id uuid NOT NULL,
 destination_account_id uuid,
 movement_type text NOT NULL CHECK (movement_type IN ('income','expense','transfer')),
 category text NOT NULL CHECK (length(trim(category)) BETWEEN 2 AND 80),
 description text NOT NULL CHECK (length(trim(description)) BETWEEN 2 AND 240),
 amount numeric(18,2) NOT NULL CHECK (amount > 0),
 currency char(3) NOT NULL DEFAULT 'MZN' CHECK (currency='MZN'),
 transaction_date timestamptz NOT NULL DEFAULT now(),
 reference text,
 notes text,
 client_operation_id uuid NOT NULL,
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT treasury_movement_idempotency UNIQUE (tenant_id,client_operation_id),
 CONSTRAINT treasury_movement_source_fk FOREIGN KEY (tenant_id,account_id) REFERENCES public.treasury_accounts(tenant_id,id) ON DELETE RESTRICT,
 CONSTRAINT treasury_movement_destination_fk FOREIGN KEY (tenant_id,destination_account_id) REFERENCES public.treasury_accounts(tenant_id,id) ON DELETE RESTRICT,
 CONSTRAINT treasury_transfer_accounts CHECK (
   (movement_type='transfer' AND destination_account_id IS NOT NULL AND destination_account_id<>account_id)
   OR (movement_type<>'transfer' AND destination_account_id IS NULL)
 )
);
CREATE INDEX IF NOT EXISTS treasury_accounts_tenant_active_idx ON public.treasury_accounts(tenant_id,active,name);
CREATE INDEX IF NOT EXISTS treasury_movements_tenant_date_idx ON public.treasury_movements(tenant_id,transaction_date DESC);
CREATE INDEX IF NOT EXISTS treasury_movements_account_date_idx ON public.treasury_movements(tenant_id,account_id,transaction_date DESC);
ALTER TABLE public.treasury_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treasury_movements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS treasury_accounts_select_member ON public.treasury_accounts;
CREATE POLICY treasury_accounts_select_member ON public.treasury_accounts FOR SELECT TO authenticated USING (private.is_tenant_member(tenant_id));
DROP POLICY IF EXISTS treasury_accounts_insert_admin ON public.treasury_accounts;
CREATE POLICY treasury_accounts_insert_admin ON public.treasury_accounts FOR INSERT TO authenticated WITH CHECK (private.is_tenant_admin(tenant_id) AND created_by=auth.uid());
DROP POLICY IF EXISTS treasury_accounts_update_admin ON public.treasury_accounts;
CREATE POLICY treasury_accounts_update_admin ON public.treasury_accounts FOR UPDATE TO authenticated USING (private.is_tenant_admin(tenant_id)) WITH CHECK (private.is_tenant_admin(tenant_id));
DROP POLICY IF EXISTS treasury_movements_select_member ON public.treasury_movements;
CREATE POLICY treasury_movements_select_member ON public.treasury_movements FOR SELECT TO authenticated USING (private.is_tenant_member(tenant_id));
DROP POLICY IF EXISTS treasury_movements_insert_authorized ON public.treasury_movements;
CREATE POLICY treasury_movements_insert_authorized ON public.treasury_movements FOR INSERT TO authenticated WITH CHECK (
 private.is_tenant_member(tenant_id) AND created_by=auth.uid()
 AND EXISTS (SELECT 1 FROM public.treasury_accounts a WHERE a.id=account_id AND a.tenant_id=tenant_id AND a.active)
 AND (destination_account_id IS NULL OR EXISTS (SELECT 1 FROM public.treasury_accounts d WHERE d.id=destination_account_id AND d.tenant_id=tenant_id AND d.active))
);
REVOKE ALL ON public.treasury_accounts, public.treasury_movements FROM anon;
GRANT SELECT,INSERT,UPDATE ON public.treasury_accounts TO authenticated;
GRANT SELECT,INSERT ON public.treasury_movements TO authenticated;
COMMIT;