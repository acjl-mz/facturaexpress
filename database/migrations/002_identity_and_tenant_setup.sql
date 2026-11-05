BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE tenants ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active';
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS tax_regime text;
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS activity text;
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS nuit varchar(20);
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS address text;
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS email text;
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS trade_name text;
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE TABLE IF NOT EXISTS app_users (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 email text NOT NULL,
 full_name text NOT NULL CHECK(length(trim(full_name))>0),
 password_hash text NOT NULL,
 status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','disabled')),
 session_version integer NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS app_users_email_lower_uq ON app_users(lower(email));

CREATE TABLE IF NOT EXISTS tenant_users (
 tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
 user_id uuid NOT NULL REFERENCES app_users(id) ON DELETE RESTRICT,
 role text NOT NULL CHECK(role IN ('owner','admin','issuer','viewer','accountant')),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,user_id)
);

CREATE TABLE IF NOT EXISTS audit_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
 actor_user_id uuid REFERENCES app_users(id) ON DELETE RESTRICT,
 event_type text NOT NULL,
 target_type text NOT NULL,
 target_id uuid,
 details jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS audit_events_tenant_created_idx ON audit_events(tenant_id,created_at DESC);

ALTER TABLE customers ADD COLUMN IF NOT EXISTS tax_status text;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE items ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Tables are accessed through the server-side PostgreSQL connection only.
-- Direct access through Supabase's exposed API roles is denied.
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE items ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY;
DO $
BEGIN
 IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
   REVOKE ALL ON tenants,app_users,tenant_users,customers,items,audit_events FROM anon;
 END IF;
 IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
   REVOKE ALL ON tenants,app_users,tenant_users,customers,items,audit_events FROM authenticated;
 END IF;
END $;
COMMIT;
