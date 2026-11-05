import { Pool } from "pg";
declare global { var facturaExpressPool: Pool | undefined; }
function createPool() {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error("DATABASE_URL não está configurada.");
  return new Pool({
    connectionString,
    max: Number(process.env.DB_POOL_MAX ?? 10),
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
    ssl: process.env.DATABASE_SSL === "true" ? { rejectUnauthorized: true } : undefined,
  });
}
function getPool() { if (!global.facturaExpressPool) global.facturaExpressPool = createPool(); return global.facturaExpressPool; }
export const db = new Proxy({} as Pool, { get(_target, property) { if (property === "then") return undefined; const pool=getPool(); const value: unknown=Reflect.get(pool,property,pool); return typeof value==="function"?value.bind(pool):value; } });
