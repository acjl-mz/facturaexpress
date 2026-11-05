import pg from "pg";
import {readdir,readFile} from "node:fs/promises";
import {join} from "node:path";
const {Pool}=pg;
if(!process.env.DATABASE_URL){console.error("DATABASE_URL não está configurada.");process.exit(1);}
const pool=new Pool({connectionString:process.env.DATABASE_URL,ssl:process.env.DATABASE_SSL==="true"?{rejectUnauthorized:true}:undefined});
const client=await pool.connect();
try{
 await client.query("CREATE TABLE IF NOT EXISTS schema_migrations(version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())");
 const dir=join(process.cwd(),"database","migrations");
 const files=(await readdir(dir)).filter(f=>f.endsWith(".sql")).sort();
 for(const file of files){
  const version=file.replace(/\.sql$/,"");
  const done=await client.query("SELECT 1 FROM schema_migrations WHERE version=$1",[version]);
  if(done.rowCount){console.log("Já aplicada:",version);continue;}
  console.log("A aplicar:",version);
  const sql=await readFile(join(dir,file),"utf8");
  await client.query(sql);
  await client.query("INSERT INTO schema_migrations(version) VALUES($1)",[version]);
  console.log("Aplicada:",version);
 }
 console.log("Migrações concluídas.");
}catch(error){console.error("Falha nas migrações:",error.message);process.exitCode=1;}finally{client.release();await pool.end();}
