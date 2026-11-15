"use client";
import { useEffect, useState, FormEvent } from "react";
import { useRouter } from "next/navigation";
import { ArrowLeft, Calculator, Info, ShieldAlert, FileText } from "lucide-react";

type Assessment = { id:string; quarter:number; activity_category:string; status:string; payment_due:number; quarter_turnover:number; applicable_rate:number; calculated_tax:number; taxable_within_limit:number; taxable_over_limit:number; annual_reference_turnover:number; payment_threshold_exemption:boolean; legal_reference:string };
const money = (v:number) => new Intl.NumberFormat("pt-MZ",{style:"currency",currency:"MZN"}).format(Number(v||0));
export default function IspcPage() {
 const router=useRouter();
 const [year,setYear]=useState(String(new Date().getFullYear()));
 const [quarter,setQuarter]=useState("1");
 const [before,setBefore]=useState("0");
 const [turnover,setTurnover]=useState("");
 const [result,setResult]=useState<any>(null);
 const [history,setHistory]=useState<Assessment[]>([]);
 const [company,setCompany]=useState<any>(null);const [profile,setProfile]=useState<any>(null);
 const [error,setError]=useState("");
 const [busy,setBusy]=useState(false);
 useEffect(() => {
  let active = true;
  fetch("/api/ispc/preview?year=" + year)
   .then(async (response) => {
    const data = await response.json();
    if (active && response.ok) { setHistory(data.assessments || []); setCompany(data.company || null); setProfile(data.profile || null); }
   })
   .catch(() => {
    if (active) setHistory([]);
   });
  return () => { active = false; };
 }, [year]);
 const printable = result ? ({...result,quarter:Number(quarter),status:"preview",quarter_turnover:Number(turnover),payment_due:result.payment_due,applicable_rate:result.applicable_rate,calculated_tax:result.calculated_tax} as any) : history.find(x=>x.quarter===Number(quarter));
 function printQuarter(){if(!printable){setError("Calcule ou seleccione um trimestre antes de imprimir.");return;}window.print();}
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
      <div className="sync-row"><span>Escalão</span><b>{result.rate_code}</b></div><div className="sync-row"><span>Categoria que determina a taxa</span><b>{result.activity_category==="liberal_profession"?"Profissões liberais":result.activity_category==="general_services"?"Serviços técnicos":"Comércio, agricultura e indústria"}</b></div><div className="sync-row"><span>Actividades consideradas</span><b>{(result.activity_categories||[]).map((v:string)=>v==="liberal_profession"?"Profissões liberais":v==="general_services"?"Serviços técnicos":"Comércio/agricultura/indústria").join(" · ")}</b></div>
      <div className="draft-warning"><Info size={18}/><span>{result.payment_threshold_exemption?"O imposto calculado é inferior a 500 MT: não há pagamento desta prestação, mas a obrigação declarativa mantém-se.":"Esta é uma prévia, sujeita à confirmação do volume de negócios e das regras aplicáveis."}</span></div>
      <small>Fundamento: {result.legal_reference}</small>
     </div>
    )}
    <div className="form-actions"><button type="button" className="auth-submit" disabled={!printable} onClick={printQuarter}><FileText size={16}/> Gerar Modelo B — Geral / imprimir</button></div>
    {printable && <div className="print-sheet"><div className="print-brand">REPÚBLICA DE MOÇAMBIQUE · MINISTÉRIO DAS FINANÇAS</div><h1>AUTORIDADE TRIBUTÁRIA DE MOÇAMBIQUE</h1><h2>DECLARAÇÃO PERIÓDICA — MODELO B · GERAL</h2><p className="print-subtitle">Imposto Simplificado para Pequenos Contribuintes (ISPC)</p><div className="print-status">FORMULÁRIO AUXILIAR DE PREPARAÇÃO — VALIDAR NO MODELO B-GERAL DA AT</div><table><tbody><tr><th colSpan={2}>01 · IDENTIFICAÇÃO DO SUJEITO PASSIVO</th></tr><tr><td>NUIT<br/><b>{company?.nuit||"—"}</b></td><td>Nome / designação social<br/><b>{company?.legal_name||"—"}</b></td></tr><tr><td>Nome comercial<br/><b>{company?.trade_name||"—"}</b></td><td>Actividade / CAE<br/><b>{company?.activity||"—"}</b></td></tr><tr><td colSpan={2}>Endereço<br/><b>{company?.address||"—"}</b></td></tr><tr><th colSpan={2}>02 · PERÍODO DECLARATIVO</th></tr><tr><td>Ano fiscal<br/><b>{year}</b></td><td>Trimestre<br/><b>{printable.quarter}º trimestre</b></td></tr><tr><th colSpan={2}>03 · ENQUADRAMENTO E ACTIVIDADE</th></tr><tr><td>Actividade principal (código)<br/><b>{profile?.ispc_primary_activity_code||"—"}</b></td><td>Categoria fiscal<br/><b>{printable.activity_category==="liberal_profession"?"Profissões liberais":printable.activity_category==="general_services"?"Prestação de serviços técnicos":"Comércio, agricultura e indústria"}</b></td></tr><tr><td>Volume anual de referência confirmado<br/><b>{money(Number(profile?.ispc_annual_reference_turnover||0))}</b></td><td>Taxa aplicada<br/><b>{printable.applicable_rate}%</b></td></tr><tr><th colSpan={2}>04 · APURAMENTO DO TRIMESTRE</th></tr><tr><td>Volume de negócios do trimestre<br/><b>{money(Number(printable.quarter_turnover||0))}</b></td><td>Volume acumulado de referência<br/><b>{money(Number(printable.annual_reference_turnover||profile?.ispc_annual_reference_turnover||0))}</b></td></tr><tr><td>Base tributável dentro do limite<br/><b>{money(Number(printable.taxable_within_limit||0))}</b></td><td>Base excedente tributada a 20%<br/><b>{money(Number(printable.taxable_over_limit||0))}</b></td></tr><tr><td>Imposto calculado<br/><b>{money(Number(printable.calculated_tax||0))}</b></td><td>Prestação a pagar<br/><b>{money(Number(printable.payment_due||0))}</b></td></tr><tr><td colSpan={2}>Dispensa de pagamento por valor inferior a 500 MT: <b>{printable.payment_threshold_exemption?"SIM — mantém-se a obrigação declarativa":"NÃO"}</b></td></tr><tr><th colSpan={2}>05 · DECLARAÇÃO, PAGAMENTO E CONFERÊNCIA</th></tr><tr><td>Referência legal<br/><b>{printable.legal_reference||"Lei n.º 9/2025, de 29 de Dezembro"}</b></td><td>Estado interno<br/><b>{printable.status==="preview"?"Prévia para revisão":printable.status}</b></td></tr><tr><td>Referência documental de enquadramento AT<br/><b>{profile?.at_activity_confirmation_reference||"—"}</b></td><td>Data de preparação<br/><b>{new Date().toLocaleDateString("pt-MZ")}</b></td></tr><tr><td colSpan={2}>A preencher/conferir no formulário Modelo B — Geral da AT: campos de identificação complementares, volume de negócios declarado, liquidação, penalidades/juros se aplicáveis, dados de pagamento e validação/recepção da repartição fiscal.</td></tr></tbody></table><p className="print-foot">A Lei n.º 9/2025 determina a declaração periódica trimestral e o pagamento trimestral. O comunicado da AT de 7 de Outubro de 2026 orienta a utilização do Modelo B — Geral enquanto o sistema específico não estiver preparado. Este mapa não é comprovativo de submissão nem guia oficial de pagamento.</p><p className="print-link">Portal do Contribuinte: portaldocontribuinte.at.gov.mz</p></div>}
    <style jsx global>{`@media screen {.print-sheet{display:none}} @media print {body *{visibility:hidden!important}.print-sheet,.print-sheet *{visibility:visible!important}.print-sheet{display:block!important;position:absolute;inset:0 auto auto 0;width:100%;padding:10mm;color:#111;background:#fff;font:10pt Arial,sans-serif}.print-sheet h1{text-align:center;font-size:15pt;margin:8px 0}.print-sheet h2{text-align:center;font-size:13pt;margin:8px 0}.print-brand,.print-subtitle,.print-link{text-align:center}.print-status{border:1px solid #333;padding:8px;text-align:center;font-weight:bold;margin:12px 0}.print-sheet table{width:100%;border-collapse:collapse;margin-top:12px}.print-sheet th,.print-sheet td{border:1px solid #555;padding:7px;vertical-align:top;text-align:left}.print-sheet th{background:#eee}.print-foot{margin-top:14px;font-size:9pt}.print-link{margin-top:12px}@page{size:A4 portrait;margin:10mm}}`}</style>
    <h2 className="report-section-title">Histórico de apuramentos · {year}</h2>
    <div className="users-table">
     {history.map(item=><div className="document-row" key={item.id}><span><b>{item.quarter}.º trimestre</b><small>{item.activity_category} · {item.status}</small></span><span className="draft-state">{item.status==="preview"?"Prévia":item.status}</span><strong className="item-price">{money(item.payment_due)}</strong></div>)}
     {!history.length && <p className="empty">Ainda não existem prévias guardadas.</p>}
    </div>
   </section>
  </main>
 );
}
