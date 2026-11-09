import {NextRequest,NextResponse} from "next/server";
import {getSession} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";

const validYear=(y:number)=>Number.isInteger(y)&&y>=2020&&y<=2100;
export async function GET(req:NextRequest){
 const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});
 const year=Number(req.nextUrl.searchParams.get("year")||new Date().getFullYear());
 if(!validYear(year))return NextResponse.json({error:"Ano inválido."},{status:400});
 const s=await createClient();const {data,error}=await s.from("tax_return_periods").select("*").eq("tenant_id",u.tenantId).eq("tax_type","IVA").eq("tax_year",year).order("tax_period");
 if(error)return NextResponse.json({error:"Não foi possível consultar as declarações."},{status:500});
 return NextResponse.json({returns:data||[]});
}
export async function POST(req:NextRequest){
 const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin"].includes(u.role))return NextResponse.json({error:"Sem permissões para preparar declarações."},{status:403});
 try{
  const b=await req.json();const year=Number(b.year),month=Number(b.month),inputCredit=Number(b.inputTaxCredit||0),priorCredit=Number(b.priorPeriodCredit||0);
  if(!validYear(year)||!Number.isInteger(month)||month<1||month>12||!Number.isFinite(inputCredit)||inputCredit<0||!Number.isFinite(priorCredit)||priorCredit<0)return NextResponse.json({error:"Período ou créditos inválidos."},{status:400});
  const s=await createClient();const {data:existing,error:existingError}=await s.from("tax_return_periods").select("id,status").eq("tenant_id",u.tenantId).eq("tax_type","IVA").eq("tax_year",year).eq("tax_period",month).maybeSingle();if(existingError)throw existingError;if(existing&&existing.status!=="draft")return NextResponse.json({error:"Este período já foi revisto ou submetido e não pode ser recalculado. Registe uma rectificação através do fluxo próprio."},{status:409});const {data:profile,error:profileError}=await s.from("tenant_tax_profiles").select("regime_code,confirmation_status").eq("tenant_id",u.tenantId).maybeSingle();
  if(profileError||!profile||profile.regime_code!=="IVA_REGULAR"||profile.confirmation_status!=="confirmed")return NextResponse.json({error:"É necessário um perfil IVA normal confirmado para preparar esta declaração."},{status:400});
  const start=new Date(Date.UTC(year,month-1,1));const end=new Date(Date.UTC(year,month,1));
  const iso=(d:Date)=>d.toISOString().slice(0,10);const periodStart=iso(start),periodEnd=iso(new Date(end.getTime()-86400000));
  const {data:docs,error:docsError}=await s.from("fiscal_documents").select("id,document_type,document_number,issue_date,status,grand_total,fiscal_document_lines(id,tax_code,taxable_amount,tax_amount)").eq("tenant_id",u.tenantId).in("status",["issued","paid","partially_paid"]).gte("issue_date",start.toISOString()).lt("issue_date",end.toISOString()).order("issue_date");
  if(docsError)throw docsError;
  let base=0,output=0,zero=0,exempt=0,nonTax=0;const snapshotDocs=(docs||[]).map((d:any)=>{
   const sign=d.document_type==="NC"?-1:1;
   for(const l of d.fiscal_document_lines||[]){const amount=Number(l.taxable_amount||0)*sign;const tax=Number(l.tax_amount||0)*sign;base+=amount;output+=tax;if(l.tax_code==="IVA_ZERO")zero+=amount;else if(l.tax_code==="IVA_ISENTO")exempt+=amount;else if(l.tax_code==="IVA_NAO_SUJEITO")nonTax+=amount;}
   return {id:d.id,document_type:d.document_type,document_number:d.document_number,issue_date:d.issue_date,status:d.status,grand_total:d.grand_total};
  });
  const due=Math.max(0,Math.round((output-inputCredit-priorCredit)*100)/100);
  const payload={tenant_id:u.tenantId,tax_type:"IVA",tax_year:year,tax_period:month,status:"draft",period_start:periodStart,period_end:periodEnd,sales_taxable_base:Math.round(base*100)/100,output_tax:Math.round(output*100)/100,input_tax_credit:inputCredit,prior_period_credit:priorCredit,tax_due:due,zero_rated_base:Math.round(zero*100)/100,exempt_base:Math.round(exempt*100)/100,non_taxable_base:Math.round(nonTax*100)/100,source_document_count:(docs||[]).length,source_snapshot:{generated_at:new Date().toISOString(),document_ids:snapshotDocs.map((d:any)=>d.id),documents:snapshotDocs,method:"Cálculo de apoio baseado em documentos emitidos no período; créditos de IVA suportado e crédito anterior introduzidos e comprovados pelo utilizador."},notes:String(b.notes||"").trim()||null,created_by:u.id,updated_at:new Date().toISOString()};
  const {data,error}=await s.from("tax_return_periods").upsert(payload,{onConflict:"tenant_id,tax_type,tax_year,tax_period"}).select().single();
  if(error)throw error;
  return NextResponse.json({return:data,message:"Apuramento de apoio preparado. Verifique os documentos e os créditos antes de revisão."});
 }catch(e){console.error("IVA return preparation",e);return NextResponse.json({error:e instanceof Error?e.message:"Não foi possível preparar o apuramento."},{status:400});}
}
