"use client";
import { useEffect, useState, FormEvent } from "react";
import { useRouter } from "next/navigation";
import { ArrowLeft, Calculator, Info, ShieldAlert } from "lucide-react";

type Assessment = { id:string; quarter:number; activity_category:string; status:string; payment_due:number };
const money = (v:number) => new Intl.NumberFormat("pt-MZ",{style:"currency",currency:"MZN"}).format(Number(v||0));
export default function IspcPage() {
 const router=useRouter();
 const [year,setYear]=useState(String(new Date().getFullYear()));
 const [quarter,setQuarter]=useState("1");
 const [before,setBefore]=useState("0");
 const [turnover,setTurnover]=useState("");
 const [result,setResult]=useState<any>(null);
 const [history,setHistory]=useState<Assessment[]>([]);
 const [error,setError]=useState("");
 const [busy,setBusy]=useState(false);
 useEffect(() => {
  let active = true;
  fetch("/api/ispc/preview?year=" + year)
   .then(async (response) => {
    const data = await response.json();
    if (active && response.ok) setHistory(data.assessments || []);
   })
   .catch(() => {
    if (active) setHistory([]);
   });
  return () => { active = false; };
 }, [year]);
 async function calculate(e:FormEvent) {
  e.preventDefault();setBusy(true);setError("");setResult(null);
  try {
   const response=await fetch("/api/ispc/preview",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({taxYear:Number(year),quarter:Number(quarter),turnoverBefore:Number(before),quarterTurnover:Number(turnover)})});
   const data=await response.json();if(!response.ok)throw new Error(data.error);
   setResult(data.preview);
   setHistory(old=>[data.assessment,...old.filter(x=>x.quarter!==Number(quarter))].sort((a,b)=>a.quarter-b.quarter));
  } catch(e) {setError(e instanceof Error?e.message:"Não foi possível calcular.");}
  finally {setBusy(false);}
 }
 return (
  <main className="simple-page">
   <header><button onClick={()=>router.push("/tax")}><ArrowLeft size={17}/> Motor fiscal</button><div><b>ISPC trimestral</b><small>Pré-cálculo conforme Lei n.º 9/2025</small></div></header>
   <section className="simple-card">
    <h1>Simulador de ISPC</h1>
    <p>Calcula uma prévia com base no perfil ISPC confirmado e no volume de negócios do trimestre. Não submete declaração nem efectua pagamento.</p>
    <div className="draft-warning"><ShieldAlert size={18}/><span>O cálculo depende da confirmação do volume de negócios de referência e da elegibilidade do contribuinte. Confirme os dados com a AT.</span></div>
    {error && <div className="form-message">{error}</div>}
    <form onSubmit={calculate}>
     <div className="form-grid">
      <label>Ano fiscal<input type="number" min="2026" value={year} onChange={e=>setYear(e.target.value)}/></label>
      <label>Trimestre<select value={quarter} onChange={e=>setQuarter(e.target.value)}><option value="1">1.º trimestre</option><option value="2">2.º trimestre</option><option value="3">3.º trimestre</option><option value="4">4.º trimestre</option></select></label>
      <label>Volume de negócios acumulado antes do trimestre (MZN)<input type="number" min="0" step="0.01" value={before} onChange={e=>setBefore(e.target.value)}/></label>
      <label>Volume de negócios do trimestre (MZN)<input required type="number" min="0" step="0.01" value={turnover} onChange={e=>setTurnover(e.target.value)}/></label>
     </div>
     <div className="form-actions"><button className="auth-submit" disabled={busy}><Calculator size={16}/>{busy?"A calcular…":"Calcular e guardar prévia"}</button></div>
    </form>
    {result && (
     <div className="report-card" style={{marginTop:20}}>
      <h2>Resultado estimado</h2>
      <div className="stats">
       <article className="stat-card"><small>Taxa aplicável</small><strong>{result.applicable_rate}%</strong></article>
       <article className="stat-card"><small>Imposto calculado</small><strong>{money(result.calculated_tax)}</strong></article>
       <article className="stat-card"><small>Pagamento devido</small><strong>{money(result.payment_due)}</strong></article>
      </div>
      <div className="sync-row"><span>Base dentro do limite</span><b>{money(result.taxable_within_limit)}</b></div>
      <div className="sync-row"><span>Base excedente a 20%</span><b>{money(result.taxable_over_limit)}</b></div>
      <div className="sync-row"><span>Escalão</span><b>{result.rate_code}</b></div>
      <div className="draft-warning"><Info size={18}/><span>{result.payment_threshold_exemption?"O imposto calculado é inferior a 500 MT: não há pagamento desta prestação, mas a obrigação declarativa mantém-se.":"Esta é uma prévia, sujeita à confirmação do volume de negócios e das regras aplicáveis."}</span></div>
      <small>Fundamento: {result.legal_reference}</small>
     </div>
    )}
    <h2 className="report-section-title">Histórico de apuramentos · {year}</h2>
    <div className="users-table">
     {history.map(item=><div className="document-row" key={item.id}><span><b>{item.quarter}.º trimestre</b><small>{item.activity_category} · {item.status}</small></span><span className="draft-state">{item.status==="preview"?"Prévia":item.status}</span><strong className="item-price">{money(item.payment_due)}</strong></div>)}
     {!history.length && <p className="empty">Ainda não existem prévias guardadas.</p>}
    </div>
   </section>
  </main>
 );
}
