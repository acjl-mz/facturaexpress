"use client";
import {useEffect,useState} from "react";
import {ArrowLeft,ShieldAlert,RefreshCw} from "lucide-react";
import {useRouter} from "next/navigation";
type Data={software:{name:string;version:string;build:string;deployment:string;platform:string;database:string};producer:{legalName:string|null;nuit:string|null;address:string|null;contact:string|null;notice:string};tenant:any;authorization:any};
export default function SoftwareInfoPage(){
 const router=useRouter();const [data,setData]=useState<Data|null>(null);const [error,setError]=useState("");
 async function load(){setError("");try{const r=await fetch("/api/system-info");const b=await r.json();if(r.status===401){router.replace("/login");return;}if(!r.ok)throw new Error(b.error||"Falha ao carregar.");setData(b);}catch(e){setError(e instanceof Error?e.message:"Falha ao carregar.");}}
 useEffect(()=>{load();},[]);
 return <main className="simple-page"><header><button onClick={()=>router.push("/")}><ArrowLeft size={17}/> Voltar</button><div><b>Identificação do software</b><small>Informação técnica para o dossier de avaliação pela AT</small></div></header>
 <section className="simple-card"><div className="users-heading"><div><h1>FacturaExpress</h1><p>Ficha técnica e identificação da versão instalada</p></div><button className="secondary-action" onClick={load}><RefreshCw size={15}/> Actualizar</button></div>
 {error&&<div className="form-message">{error}</div>}{!data?<p>A carregar informação…</p>:<>
 <div className="documents-export-panel"><ShieldAlert size={22}/><div><b>Estado de autorização: {data.authorization.status==="approved"&&data.authorization.version_matches?"registada para esta versão":data.authorization.status==="version_mismatch"?"versão não coincide":"não comprovado"}</b><small>{data.authorization.version_matches?"A versão autorizada coincide com a versão instalada. A autorização e o seu âmbito devem ainda ser confirmados documentalmente.":data.authorization.status==="version_mismatch"?"Existe um registo de autorização, mas a versão aprovada não coincide com a versão instalada. A emissão permanece bloqueada.":"Não existe autorização da AT registada para esta empresa e versão. A emissão fiscal permanece bloqueada."}</small></div></div>
 <h2>Identificação do produto</h2><div className="form-grid"><label>Nome do software<strong>{data.software.name}</strong></label><label>Versão<strong>{data.software.version}</strong></label><label>Build / commit<strong>{data.software.build}</strong></label><label>Ambiente<strong>{data.software.deployment}</strong></label><label>Plataforma<strong>{data.software.platform}</strong></label><label>Base de dados<strong>{data.software.database}</strong></label></div>
 <h2>Produtor do software</h2><p>Nome legal, NUIT, endereço e contacto do produtor não estão configurados como dados comprovados do produtor. Devem ser preenchidos com os dados da entidade que solicita a certificação, não com os dados de cada empresa cliente.</p>
 <h2>Dados da autorização</h2><div className="form-grid"><label>Estado<strong>{data.authorization.status||"Não registado"}</strong></label><label>Referência<strong>{data.authorization.authorization_reference||"Sem registo"}</strong></label><label>Versão aprovada<strong>{data.authorization.approved_software_version||"Sem registo"}</strong></label><label>Correspondência da versão<strong>{data.authorization.version_matches?"Sim":"Não"}</strong></label><label>Empresa activa<strong>{data.tenant?.legal_name||"—"}</strong></label><label>NUIT da empresa<strong>{data.tenant?.nuit||"—"}</strong></label></div>
 <p className="empty">Esta ficha é uma evidência interna de identificação técnica. Não constitui certificado, licença ou declaração de conformidade da AT.</p>
 </>}
 </section></main>;
}
