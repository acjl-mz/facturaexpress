import {NextRequest,NextResponse} from "next/server";
import {getSession} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";

const csv=(value:unknown)=>{const s=value===null||value===undefined?"":String(value);return '"'+s.replace(/"/g,'""')+'"';};
const money=(value:unknown)=>Number(value||0).toFixed(2);

export async function GET(req:NextRequest){
 const user=await getSession();
 if(!user)return NextResponse.json({error:"Não autenticado."},{status:401});
 const month=req.nextUrl.searchParams.get("month")||"";
 if(!/^\d{4}-\d{2}$/.test(month))return NextResponse.json({error:"Indique um mês válido no formato AAAA-MM."},{status:400});
 const start=month+"-01";
 const next=new Date(Date.UTC(Number(month.slice(0,4)),Number(month.slice(5,7)),1));
 const end=next.toISOString().slice(0,10);
 const db=await createClient();
 const [{data:company,error:companyError},{data:profile,error:profileError},{data:docs,error:docsError}]=await Promise.all([
  db.from("tenants").select("legal_name,trade_name,nuit,address").eq("id",user.tenantId).single(),
  db.from("tenant_tax_profiles").select("regime_code,confirmation_status").eq("tenant_id",user.tenantId).maybeSingle(),
  db.from("fiscal_documents").select("id,document_type,document_number,status,issue_date,currency,exchange_rate,subtotal,discount_total,tax_total,withholding_total,grand_total,customers(name,nuit,address),fiscal_document_lines(description,quantity,unit,unit_price,discount_amount,tax_code,tax_rate,taxable_amount,tax_amount,line_total)").eq("tenant_id",user.tenantId).in("status",["issued","paid","partially_paid","voided"]).gte("issue_date",start+"T00:00:00Z").lt("issue_date",end+"T00:00:00Z").order("issue_date",{ascending:true}).limit(5000)
 ]);
 if(profileError)return NextResponse.json({error:"Não foi possível confirmar o regime fiscal."},{status:500});
 if(!profile)return NextResponse.json({error:"O regime fiscal da empresa ainda não está configurado. A exportação foi bloqueada."},{status:409});
 if(profile.regime_code==="ISPC")return NextResponse.json({error:"A comunicação mensal prevista no Aviso n.º 40/AT/DGI/2025 não deve ser aplicada automaticamente ao regime ISPC. Consulte as obrigações específicas do seu regime."},{status:409});
 if(companyError||docsError){console.error("AT invoice report query failed",companyError?.message,docsError?.message);return NextResponse.json({error:"Não foi possível preparar a exportação."},{status:500});}
 const rows:string[][]=[["REPORT_TYPE","PRELIMINARY_INVOICE_DATA_FOR_REVIEW","NOT_OFFICIAL_AT_SCHEMA"],["REFERENCE_MONTH",month],["SOFTWARE","FacturaExpress"],["NOTICE","Aviso n.º 40/AT/DGI/2025"],["DISCLAIMER","Exportação preliminar. Não é ficheiro oficial validado, não está comprimido e não constitui submissão à AT."],["ISSUER_NAME",company?.legal_name||""],["ISSUER_TRADE_NAME",company?.trade_name||""],["ISSUER_NUIT",company?.nuit||""],[],["DOCUMENT_TYPE","DOCUMENT_NUMBER","STATUS","ISSUE_DATE","ISSUER_NUIT","CUSTOMER_NAME","CUSTOMER_NUIT","CUSTOMER_ADDRESS","CURRENCY","EXCHANGE_RATE","SUBTOTAL","DISCOUNT","TAX_TOTAL","WITHHOLDING","GRAND_TOTAL","LINE_DESCRIPTION","QUANTITY","UNIT","UNIT_PRICE","LINE_DISCOUNT","TAX_CODE","TAX_RATE","TAXABLE_AMOUNT","TAX_AMOUNT","LINE_TOTAL"]];
 for(const d of docs||[]){
  const customer=Array.isArray(d.customers)?d.customers[0]:d.customers;
  const lines=Array.isArray(d.fiscal_document_lines)?d.fiscal_document_lines:[];
  if(!lines.length){rows.push([d.document_type,d.document_number,d.status,d.issue_date,company?.nuit,customer?.name,customer?.nuit,customer?.address,d.currency,d.exchange_rate,money(d.subtotal),money(d.discount_total),money(d.tax_total),money(d.withholding_total),money(d.grand_total)]);continue;}
  for(const l of lines)rows.push([d.document_type,d.document_number,d.status,d.issue_date,company?.nuit,customer?.name,customer?.nuit,customer?.address,d.currency,d.exchange_rate,money(d.subtotal),money(d.discount_total),money(d.tax_total),money(d.withholding_total),money(d.grand_total),l.description,l.quantity,l.unit,l.unit_price,l.discount_amount,l.tax_code,l.tax_rate,l.taxable_amount,l.tax_amount,l.line_total]);
 }
 const body="\uFEFF"+rows.map(row=>row.map(csv).join(";")).join(String.fromCharCode(13,10));
 return new NextResponse(body,{status:200,headers:{"Content-Type":"text/csv; charset=utf-8","Content-Disposition":'attachment; filename="FacturaExpress-AT-'+month+'.csv"',"Cache-Control":"no-store"}});
}
