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
 useEffect(() => { const requestedYear = new URLSearchParams(window.location.search).get("year"); if (requestedYear && /^\\d{4}$/.test(requestedYear)) setYear(requestedYear); }, []);
 const now = new Date();
 const [year, setYear] = useState(String(now.getFullYear()));
 const [month, setMonth] = useState(String(now.getMonth() + 1));
 const [inputCredit, setInputCredit] = useState("0");
 const [priorCredit, setPriorCredit] = useState("0");
 const [notes, setNotes] = useState("");
 const [rows, setRows] = useState<TaxReturn[]>([]);
 const [company,setCompany] = useState<any>(null);
 const [result, setResult] = useState<TaxReturn | null>(null);
 const [error, setError] = useState("");
 const [busy, setBusy] = useState(false);
 const [loading, setLoading] = useState(true);

 async function load() {
  const response = await fetch("/api/tax-returns/iva?year=" + year);
  if (response.status === 401) { router.replace("/login"); return; }
  const data = await response.json();
  if (!response.ok) throw new Error(data.error);
  setRows(data.returns || []); setCompany(data.company || null);
 }
 useEffect(() => {
  load().catch((e) => setError(e.message)).finally(() => setLoading(false));
 }, [year]);

 const printable = result || rows.find((r) => r.tax_period === Number(month));
 function printDeclaration(){ if(!printable){setError("Prepare ou seleccione um período antes de imprimir.");return;} window.print(); }
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
    <div className="form-actions"><button type="button" className="auth-submit" disabled={!printable} onClick={printDeclaration}><FileText size={16}/> Imprimir declaração / guardar PDF</button></div>
    {printable && <div className="print-sheet"><div className="print-brand">REPÚBLICA DE MOÇAMBIQUE · MINISTÉRIO DAS FINANÇAS</div><h1>AUTORIDADE TRIBUTÁRIA DE MOÇAMBIQUE</h1><h2>DECLARAÇÃO PERIÓDICA DE IVA — MODELO A</h2><p className="print-subtitle">Regime normal · Artigo 36.º do Código do IVA</p><div className="print-status">MAPA DE APOIO GERADO PELO FACTURAEXPRESS — NÃO É RECIBO DE SUBMISSÃO DA AT</div><table><tbody><tr><th colSpan={2}>01 · IDENTIFICAÇÃO DO SUJEITO PASSIVO</th></tr><tr><td>NUIT<br/><b>{company?.nuit || "—"}</b></td><td>Nome / designação social<br/><b>{company?.legal_name || "—"}</b></td></tr><tr><td>Nome comercial<br/><b>{company?.trade_name || "—"}</b></td><td>CAE / actividade<br/><b>{company?.activity || "A confirmar"}</b></td></tr><tr><td colSpan={2}>Domicílio fiscal<br/><b>{company?.address || "—"}</b></td></tr><tr><th colSpan={2}>02 · PERÍODO A QUE RESPEITA</th></tr><tr><td>Mês / Ano<br/><b>{months[printable.tax_period-1]} / {printable.tax_year}</b></td><td>Tipo<br/><b>Declaração periódica · mapa de preparação</b></td></tr><tr><th colSpan={2}>03 · APURAMENTO — VALORES DISPONÍVEIS NO FACTURAEXPRESS</th></tr><tr><td>Operações tributáveis — base (campo 01, valor agregado)<br/><b>{money(printable.sales_taxable_base)}</b></td><td>IVA liquidado (campo 02, valor agregado)<br/><b>{money(printable.output_tax)}</b></td></tr><tr><td>Operações isentas — base agregada<br/><b>{money((printable as any).exempt_base)}</b></td><td>Operações não sujeitas — base agregada<br/><b>{money((printable as any).non_taxable_base)}</b></td></tr><tr><td>IVA suportado dedutível declarado para o apuramento<br/><b>{money(printable.input_tax_credit)}</b></td><td>Crédito de período anterior<br/><b>{money(printable.prior_period_credit)}</b></td></tr><tr><td>IVA a entregar — prévia<br/><b>{money(printable.tax_due)}</b></td><td>Documentos de venda considerados<br/><b>{printable.source_document_count}</b></td></tr><tr><td>Valor indicativo para liquidação / guia da AT<br/><b>{money(printable.tax_due)}</b></td><td>Juros de mora e outros acréscimos<br/><b>A apurar, se aplicável, no canal oficial da AT</b></td></tr><tr><th colSpan={2}>04 · CONFERÊNCIA E SUBMISSÃO</th></tr><tr><td colSpan={2}>Antes de entregar, transcreva/valide os campos no formulário oficial da AT, incluindo campos de imposto dedutível por natureza, regularizações, juros, excesso a reportar e eventual reembolso. Estes elementos não são integralmente discriminados no mapa actual e não são inventados neste documento.</td></tr><tr><td>Preparado em<br/><b>{new Date().toLocaleString("pt-MZ")}</b></td><td>Estado interno<br/><b>{printable.status === "draft" ? "Rascunho para revisão" : printable.status}</b></td></tr></tbody></table><p className="print-foot">Documento auxiliar para conferência e preenchimento do Modelo A oficial. A submissão é efectuada no Portal do Contribuinte ou nos canais autorizados pela AT. Não comprova entrega, pagamento ou aceitação.</p><p className="print-link">Portal do Contribuinte: portaldocontribuinte.at.gov.mz</p></div>}
    <style jsx global>{`@media screen {.print-sheet{display:none}} @media print {body *{visibility:hidden!important}.print-sheet,.print-sheet *{visibility:visible!important}.print-sheet{display:block!important;position:absolute;inset:0 auto auto 0;width:100%;padding:10mm;color:#111;background:#fff;font:10pt Arial,sans-serif}.print-sheet h1{text-align:center;font-size:15pt;margin:8px 0}.print-sheet h2{text-align:center;font-size:13pt;margin:8px 0}.print-brand,.print-subtitle,.print-link{text-align:center}.print-status{border:1px solid #333;padding:8px;text-align:center;font-weight:bold;margin:12px 0}.print-sheet table{width:100%;border-collapse:collapse;margin-top:12px}.print-sheet th,.print-sheet td{border:1px solid #555;padding:7px;vertical-align:top;text-align:left}.print-sheet th{background:#eee}.print-foot{margin-top:14px;font-size:9pt}.print-link{margin-top:12px} @page{size:A4 portrait;margin:10mm}}`}</style>
   </section>
  </main>
 );
}
