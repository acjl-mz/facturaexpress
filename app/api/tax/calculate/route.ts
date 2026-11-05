import { NextResponse } from "next/server";

// Monetary arithmetic is performed in integer centavos. Tax rates are supplied by
// versioned, legally reviewed configuration; no statutory rate is assumed here.
type Line = { description: string; quantity: number; unitPrice: number; discount?: number; taxRate?: number; taxTreatment?: "taxable" | "exempt" | "out_of_scope" };
const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
export async function POST(request: Request) {
  try {
    const body = await request.json() as { lines?: Line[] };
    if (!Array.isArray(body.lines) || body.lines.length === 0 || body.lines.length > 500) return NextResponse.json({ error: "Indique entre 1 e 500 linhas." }, { status: 400 });
    const lines = body.lines.map((line) => {
      if (!line.description?.trim() || !Number.isFinite(line.quantity) || line.quantity <= 0 || !Number.isFinite(line.unitPrice) || line.unitPrice < 0) throw new Error("Linha inválida: descrição, quantidade ou preço.");
      const rate = line.taxTreatment === "taxable" ? line.taxRate : 0;
      if (rate !== undefined && (!Number.isFinite(rate) || rate < 0 || rate > 100)) throw new Error("Taxa fiscal inválida.");
      if (line.taxTreatment === "taxable" && rate === undefined) throw new Error("A taxa deve ser indicada para operações tributáveis.");
      const gross = round2(line.quantity * line.unitPrice);
      const discount = round2(line.discount ?? 0);
      if (discount < 0 || discount > gross) throw new Error("Desconto inválido.");
      const taxable = round2(gross - discount);
      const tax = round2(taxable * (rate ?? 0) / 100);
      return { description: line.description.trim(), quantity: line.quantity, unitPrice: round2(line.unitPrice), gross, discount, taxable, taxRate: rate ?? 0, tax, total: round2(taxable + tax) };
    });
    const subtotal = round2(lines.reduce((s,l)=>s+l.gross,0));
    const discountTotal = round2(lines.reduce((s,l)=>s+l.discount,0));
    const taxTotal = round2(lines.reduce((s,l)=>s+l.tax,0));
    const total = round2(lines.reduce((s,l)=>s+l.total,0));
    return NextResponse.json({ lines, subtotal, discountTotal, taxableTotal: round2(subtotal-discountTotal), taxTotal, total, currency: "MZN", fiscalStatus: "calculation_only_not_a_fiscal_document" });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Não foi possível calcular." }, { status: 400 });
  }
}
