BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE tenants ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active';
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS tax_regime text;
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS activity text;
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

ALTER TABLE tenant_users
 ADD CONSTRAINT tenant_users_app_user_fk
 FOREIGN KEY (user_id) REFERENCES app_users(id) ON DELETE RESTRICT;

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

-- The application connects only through its private server-side PostgreSQL connection.
-- The Supabase public API roles must not read or mutate these business tables.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated;
COMMIT;
