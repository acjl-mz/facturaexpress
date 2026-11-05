import pg from "pg";
import bcrypt from "bcryptjs";
const {Pool}=pg;
const required=["DATABASE_URL","BOOTSTRAP_COMPANY_NAME","BOOTSTRAP_NUIT","BOOTSTRAP_ADMIN_NAME","BOOTSTRAP_ADMIN_EMAIL","BOOTSTRAP_ADMIN_PASSWORD"];
const missing=required.filter(k=>!process.env[k]);
if(missing.length){console.error("Variáveis obrigatórias em falta:",missing.join(", "));process.exit(1);}
if(!/^\d{9}$/.test(process.env.BOOTSTRAP_NUIT)){console.error("BOOTSTRAP_NUIT deve conter 9 algarismos.");process.exit(1);}
if(process.env.BOOTSTRAP_ADMIN_PASSWORD.length<12){console.error("A palavra-passe inicial deve ter pelo menos 12 caracteres.");process.exit(1);}
const pool=new Pool({connectionString:process.env.DATABASE_URL,ssl:process.env.DATABASE_SSL==="true"?{rejectUnauthorized:true}:undefined});
const client=await pool.connect();
try{
 await client.query("BEGIN");
 const exists=await client.query("SELECT id FROM tenant_users LIMIT 1");
 if(exists.rowCount){throw new Error("Já existem utilizadores provisionados. O bootstrap inicial foi bloqueado.");}
 const tenant=await client.query("INSERT INTO tenants(legal_name,trade_name,nuit,currency,status) VALUES($1,$2,$3,'MZN','active') RETURNING id",[process.env.BOOTSTRAP_COMPANY_NAME.trim(),process.env.BOOTSTRAP_COMPANY_TRADE_NAME?.trim()||null,process.env.BOOTSTRAP_NUIT]);
 const hash=await bcrypt.hash(process.env.BOOTSTRAP_ADMIN_PASSWORD,12);
 const user=await client.query("INSERT INTO app_users(email,full_name,password_hash,status) VALUES($1,$2,$3,'active') RETURNING id",[process.env.BOOTSTRAP_ADMIN_EMAIL.trim().toLowerCase(),process.env.BOOTSTRAP_ADMIN_NAME.trim(),hash]);
 await client.query("INSERT INTO tenant_users(tenant_id,user_id,role) VALUES($1,$2,'owner')",[tenant.rows[0].id,user.rows[0].id]);
 await client.query("COMMIT");
 console.log("Administrador inicial criado com sucesso. Guarde as credenciais num gestor de palavras-passe e remova as variáveis BOOTSTRAP_* do ambiente.");
}catch(error){await client.query("ROLLBACK");console.error(error.message);process.exitCode=1;}finally{client.release();await pool.end();}
