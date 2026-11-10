"use client";
import {useEffect,useState} from "react";
import {useRouter} from "next/navigation";
import {ArrowLeft,FilePlus2,FileText,Search,ChevronLeft,ChevronRight} from "lucide-react";

type Doc={id:string;document_type:string;document_number:string|null;status:string;created_at:string;issue_date:string|null;grand_total:number;customers:{name:string;nuit?:string|null}|null};
type Result={documents:Doc[];total:number;page:number;pageSize:number};
const money=(v:number)=>new Intl.NumberFormat("pt-MZ",{style:"currency",currency:"MZN"}).format(Number(v||0));

export default function DocumentsPage(){
 const router=useRouter();
 const [docs,setDocs]=useState<Doc[]>([]);
 const [q,setQ]=useState("");
 const [debouncedQ,setDebouncedQ]=useState("");
 const [loading,setLoading]=useState(true);
 const [error,setError]=useState("");
 const [status,setStatus]=useState("");
 const [type,setType]=useState("");
 const [from,setFrom]=useState("");
 const [to,setTo]=useState("");
 const [page,setPage]=useState(1);
 const [total,setTotal]=useState(0);
 const pageSize=25;
 const pages=Math.max(1,Math.ceil(total/pageSize));

 useEffect(()=>{
  const timer=window.setTimeout(()=>setDebouncedQ(q.trim()),300);
  return()=>window.clearTimeout(timer);
 },[q]);

 useEffect(()=>{
  let active=true;
  setLoading(true);setError("");
  const params=new URLSearchParams({page:String(page),pageSize:String(pageSize)});
  if(debouncedQ)params.set("q",debouncedQ);
  if(status)params.set("status",status);
  if(type)params.set("type",type);
  if(from)params.set("from",from);
  if(to)params.set("to",to);
  fetch("/api/documents?"+params.toString())
   .then(async response=>{const body=await response.json();if(response.status===401){router.replace("/login");return null;}if(!response.ok)throw new Error(body.error||"Não foi possível consultar documentos.");return body as Result;})
   .then(result=>{if(!active||!result)return;setDocs(result.documents||[]);setTotal(result.total||0);})
   .catch(reason=>{if(active)setError(reason instanceof Error?reason.message:"Não foi possível carregar documentos.");})
   .finally(()=>{if(active)setLoading(false);});
  return()=>{active=false;};
 },[debouncedQ,status,type,from,to,page,router]);

 function resetFilters(){setQ("");setDebouncedQ("");setStatus("");setType("");setFrom("");setTo("");setPage(1);}
 function changeFilter(setter:(value:string)=>void,value:string){setter(value);setPage(1);}
 return <main className="simple-page">
  <header><button onClick={()=>router.push("/")}><ArrowLeft size={17}/> Voltar</button><div><b>Documentos</b><small>Facturação e documentos em preparação</small></div></header>
  <section className="simple-card">
   <div className="users-heading"><div><h1>Documentos de facturação</h1><p>Pesquise por número, cliente ou NUIT e filtre por tipo, estado e período de registo.</p></div><button className="auth-submit" onClick={()=>router.push("/documents/new")}><FilePlus2 size={16}/> Novo documento</button></div>
   <div className="list-search"><Search size={16}/><input aria-label="Pesquisar documentos" placeholder="Pesquisar número, cliente ou NUIT…" value={q} onChange={event=>{setQ(event.target.value);setPage(1);}}/></div>
   <div className="form-grid">
    <label>Tipo de documento<select value={type} onChange={event=>changeFilter(setType,event.target.value)}><option value="">Todos os tipos</option><option value="FT">Factura</option><option value="FR">Factura-recibo</option><option value="PF">Proforma</option><option value="NC">Nota de crédito</option><option value="ND">Nota de débito</option></select></label>
    <label>Estado<select value={status} onChange={event=>changeFilter(setStatus,event.target.value)}><option value="">Todos os estados</option><option value="draft">Rascunho</option><option value="issued">Emitido</option><option value="paid">Pago</option><option value="partially_paid">Parcialmente pago</option><option value="voided">Anulado</option></select></label>
    <label>Registado de<input type="date" value={from} onChange={event=>changeFilter(setFrom,event.target.value)}/></label>
    <label>Registado até<input type="date" value={to} min={from||undefined} onChange={event=>changeFilter(setTo,event.target.value)}/></label>
    <label><span>&nbsp;</span><button type="button" className="secondary-action" onClick={resetFilters}>Limpar filtros</button></label>
   </div>
   {error&&<div className="form-message">{error}</div>}
   <div className="documents-results-heading"><b>{total} documento(s)</b><small>{loading?"A actualizar resultados…":`Página ${page} de ${pages}`}</small></div>
   {loading?<p>A carregar documentos…</p>:<div className="users-table">
    {docs.map(document=><button className="document-row" key={document.id} onClick={()=>router.push("/documents/"+document.id)}>
     <span className="user-avatar"><FileText size={16}/></span>
     <span><b>{document.document_type} · {document.document_number||"RASCUNHO"}</b><small>{document.customers?.name||"Consumidor final"} · {new Date(document.issue_date||document.created_at).toLocaleDateString("pt-MZ")}</small></span>
     <span className="draft-state">{document.status==="draft"?"Rascunho":document.status==="issued"?"Emitido":document.status==="paid"?"Pago":document.status==="partially_paid"?"Parcialmente pago":document.status==="voided"?"Anulado":document.status}</span>
     <strong className="item-price">{money(document.grand_total)}</strong>
    </button>)}
    {!docs.length&&<p className="empty">Não foram encontrados documentos com os filtros seleccionados.</p>}
   </div>}
   <div className="documents-pagination"><button className="secondary-action" disabled={loading||page<=1} onClick={()=>setPage(value=>Math.max(1,value-1))}><ChevronLeft size={16}/> Anterior</button><span>{page} / {pages}</span><button className="secondary-action" disabled={loading||page>=pages} onClick={()=>setPage(value=>Math.min(pages,value+1))}>Seguinte <ChevronRight size={16}/></button></div>
  </section>
 </main>;
}
