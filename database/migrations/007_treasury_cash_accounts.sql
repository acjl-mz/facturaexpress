BEGIN;

CREATE TABLE IF NOT EXISTS public.treasury_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  name text NOT NULL CHECK (length(trim(name)) > 0),
  account_type text NOT NULL CHECK (account_type IN ('cash','bank','mobile_money')),
  institution text,
  account_reference text,
  currency char(3) NOT NULL DEFAULT 'MZN' CHECK (currency = 'MZN'),
  opening_balance numeric(18,2) NOT NULL DEFAULT 0 CHECK (opening_balance >= 0),
  active boolean NOT NULL DEFAULT true,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id)
);

CREATE UNIQUE INDEX IF NOT EXISTS treasury_accounts_tenant_name_uq
  ON public.treasury_accounts (tenant_id, lower(name));
CREATE INDEX IF NOT EXISTS treasury_accounts_tenant_active_idx
  ON public.treasury_accounts (tenant_id, active, name);

CREATE TABLE IF NOT EXISTS public.treasury_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  account_id uuid NOT NULL,
  transaction_type text NOT NULL CHECK (transaction_type IN ('income','expense')),
  category text NOT NULL CHECK (length(trim(category)) > 0),
  description text NOT NULL CHECK (length(trim(description)) > 0),
  amount numeric(18,2) NOT NULL CHECK (amount > 0),
  payment_method text CHECK (payment_method IN ('cash','bank_transfer','mobile_money','pos','cheque','other')),
  reference text,
  transaction_date timestamptz NOT NULL DEFAULT now(),
  local_operation_id uuid NOT NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT treasury_transactions_account_tenant_fk
    FOREIGN KEY (tenant_id, account_id)
    REFERENCES public.treasury_accounts (tenant_id, id) ON DELETE RESTRICT,
  CONSTRAINT treasury_transactions_idempotency_uq
    UNIQUE (tenant_id, local_operation_id)
);

CREATE INDEX IF NOT EXISTS treasury_transactions_tenant_date_idx
  ON public.treasury_transactions (tenant_id, transaction_date DESC);
CREATE INDEX IF NOT EXISTS treasury_transactions_account_date_idx
  ON public.treasury_transactions (tenant_id, account_id, transaction_date DESC);

ALTER TABLE public.treasury_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treasury_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS treasury_accounts_select_member ON public.treasury_accounts;
CREATE POLICY treasury_accounts_select_member
  ON public.treasury_accounts FOR SELECT TO authenticated
  USING (private.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS treasury_accounts_insert_finance ON public.treasury_accounts;
CREATE POLICY treasury_accounts_insert_finance
  ON public.treasury_accounts FOR INSERT TO authenticated
  WITH CHECK (
    private.is_tenant_member(tenant_id)
    AND EXISTS (
      SELECT 1 FROM public.tenant_users tu
      WHERE tu.tenant_id = treasury_accounts.tenant_id
        AND tu.user_id = (SELECT auth.uid())
        AND tu.role IN ('owner','admin','accountant')
    )
    AND created_by = (SELECT auth.uid())
  );

DROP POLICY IF EXISTS treasury_accounts_update_admin ON public.treasury_accounts;
CREATE POLICY treasury_accounts_update_admin
  ON public.treasury_accounts FOR UPDATE TO authenticated
  USING (
    private.is_tenant_member(tenant_id)
    AND EXISTS (
      SELECT 1 FROM public.tenant_users tu
      WHERE tu.tenant_id = treasury_accounts.tenant_id
        AND tu.user_id = (SELECT auth.uid())
        AND tu.role IN ('owner','admin')
    )
  )
  WITH CHECK (
    private.is_tenant_member(tenant_id)
    AND EXISTS (
      SELECT 1 FROM public.tenant_users tu
      WHERE tu.tenant_id = treasury_accounts.tenant_id
        AND tu.user_id = (SELECT auth.uid())
        AND tu.role IN ('owner','admin')
    )
  );

DROP POLICY IF EXISTS treasury_transactions_select_member ON public.treasury_transactions;
CREATE POLICY treasury_transactions_select_member
  ON public.treasury_transactions FOR SELECT TO authenticated
  USING (private.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS treasury_transactions_insert_finance ON public.treasury_transactions;
CREATE POLICY treasury_transactions_insert_finance
  ON public.treasury_transactions FOR INSERT TO authenticated
  WITH CHECK (
    private.is_tenant_member(tenant_id)
    AND created_by = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.tenant_users tu
      WHERE tu.tenant_id = treasury_transactions.tenant_id
        AND tu.user_id = (SELECT auth.uid())
        AND tu.role IN ('owner','admin','accountant')
    )
    AND EXISTS (
      SELECT 1 FROM public.treasury_accounts a
      WHERE a.id = treasury_transactions.account_id
        AND a.tenant_id = treasury_transactions.tenant_id
        AND a.active
    )
  );

REVOKE ALL ON public.treasury_accounts FROM anon, authenticated;
REVOKE ALL ON public.treasury_transactions FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.treasury_accounts TO authenticated;
GRANT SELECT, INSERT ON public.treasury_transactions TO authenticated;

COMMIT;