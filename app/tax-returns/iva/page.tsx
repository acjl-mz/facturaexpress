"use client";
import { useEffect, useState, FormEvent } from "react";
import { useRouter } from "next/navigation";
import { ArrowLeft, Calculator, FileText, ShieldAlert, RefreshCw } from "lucide-react";

type TaxReturn = {
 id: string; tax_year: number; tax_period: number; status: string;
 sales_taxable_base: number; output_tax: number; input_tax_credit: number;
 prior_period_credit: number; tax_due: number; source_document_count: number;
 period_start: string; period_end: string;
};
const money = (v: number) => new Intl.NumberFormat("pt-MZ", { style: "currency", currency: "MZN" }).format(Number(v || 0));
const months = ["Janeiro","Fevereiro","Março","Abril","Maio","Junho","Julho","Agosto","Setembro","Outubro","Novembro","Dezembro"];

export default function IvaReturnsPage() {
 const router = useRouter();
 const now = new Date();
 const [year, setYear] = useState(String(now.getFullYear()));
 const [month, setMonth] = useState(String(now.getMonth() + 1));
 const [inputCredit, setInputCredit] = useState("0");
 const [priorCredit, setPriorCredit] = useState("0");
 const [notes, setNotes] = useState("");
 const [rows, setRows] = useState<TaxReturn[]>([]);
 const [result, setResult] = useState<TaxReturn | null>(null);
 const [error, setError] = useState("");
 const [busy, setBusy] = useState(false);
 const [loading, setLoading] = useState(true);

 async function load() {
  const response = await fetch("/api/tax-returns/iva?year=" + year);
  if (response.status === 401) { router.replace("/login"); return; }
  const data = await response.json();
  if (!response.ok) throw new Error(data.error);
  setRows(data.returns || []);
 }
 useEffect(() => {
  load().catch((e) => setError(e.message)).finally(() => setLoading(false));
 }, [year]);

 async function prepare(e: FormEvent) {
  e.preventDefault(); setBusy(true); setError(""); setResult(null);
  try {
   const response = await fetch("/api/tax-returns/iva", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ year: Number(year), month: Number(month), inputTaxCredit: Number(inputCredit), priorPeriodCredit: Number(priorCredit), notes })
   });
   const data = await response.json();
   if (!response.ok) throw new Error(data.error);
   setResult(data.return); await load();
  } catch (e) { setError(e instanceof Error ? e.message : "Não foi possível preparar o apuramento."); }
  finally { setBusy(false); }
 }

 return (
  <main className="simple-page">
   <header>
    <button onClick={() => router.push("/tax")}><ArrowLeft size={17}/> Motor fiscal</button>
    <div><b>Obrigações declarativas</b><small>Apuramento mensal do IVA</small></div>
   </header>
   <section className="simple-card">
    <h1>Declaração periódica de IVA</h1>
    <p>Prepare um mapa mensal de apoio a partir dos documentos emitidos e registe os créditos de IVA suportado e de períodos anteriores com base nos comprovativos contabilísticos.</p>
    <div className="draft-warning"><ShieldAlert size={18}/><span><b>Documento de trabalho — não é uma declaração oficial.</b> Não submete à AT. O crédito de IVA suportado exige validação de facturas de fornecedores, dedutibilidade e documentos de suporte.</span></div>
    {error && <div className="form-message">{error}</div>}
    <form onSubmit={prepare}>
     <div className="form-grid">
      <label>Ano fiscal<input type="number" min="2020" max="2100" value={year} onChange={e => setYear(e.target.value)}/></label>
      <label>Mês<select value={month} onChange={e => setMonth(e.target.value)}>{months.map((name, i) => <option key={i} value={i + 1}>{name}</option>)}</select></label>
      <label>IVA suportado dedutível (MZN)<input type="number" min="0" step="0.01" value={inputCredit} onChange={e => setInputCredit(e.target.value)}/></label>
      <label>Crédito de IVA de período anterior (MZN)<input type="number" min="0" step="0.01" value={priorCredit} onChange={e => setPriorCredit(e.target.value)}/></label>
      <label className="wide">Notas e referências dos comprovativos<textarea rows={3} value={notes} onChange={e => setNotes(e.target.value)} placeholder="Referências de documentos de suporte e observações de revisão"/></label>
     </div>
     <div className="form-actions"><button className="auth-submit" disabled={busy}><Calculator size={16}/>{busy ? "A preparar…" : "Preparar apuramento"}</button></div>
    </form>
    {result && (
     <div className="report-card">
      <h2>Apuramento preparado · {months[result.tax_period - 1]} {result.tax_year}</h2>
      <div className="stats">
       <article className="stat-card"><small>BASE TRIBUTÁVEL</small><strong>{money(result.sales_taxable_base)}</strong></article>
       <article className="stat-card"><small>IVA LIQUIDADO</small><strong>{money(result.output_tax)}</strong></article>
       <article className="stat-card"><small>IVA SUPORTADO</small><strong>{money(result.input_tax_credit)}</strong></article>
       <article className="stat-card"><small>IVA A PAGAR (PRÉVIA)</small><strong>{money(result.tax_due)}</strong></article>
      </div>
      <p>{result.source_document_count} documentos emitidos considerados. Estado: rascunho.</p>
     </div>
    )}
    <h2 className="report-section-title">Histórico de apuramentos · {year}</h2>
    {loading ? <p>A carregar…</p> : (
     <div className="users-table">
      {rows.map((item) => (
       <div className="document-row" key={item.id}>
        <span className="user-avatar"><FileText size={16}/></span>
        <span><b>{months[item.tax_period - 1]} {item.tax_year}</b><small>{item.source_document_count} documentos · Base {money(item.sales_taxable_base)}</small></span>
        <span className="draft-state">{item.status === "draft" ? "Rascunho" : item.status}</span>
        <strong className="item-price">{money(item.tax_due)}</strong>
       </div>
      ))}
      {!rows.length && <p className="empty">Ainda não existem apuramentos para este ano.</p>}
     </div>
    )}
    <div className="draft-warning"><RefreshCw size={17}/><span>Ao preparar novamente o mesmo mês, o apuramento é actualizado com os documentos emitidos mais recentes. Registos revistos/submetidos não são recalculados automaticamente.</span></div>
   </section>
  </main>
 );
}
