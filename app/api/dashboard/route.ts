import {NextResponse} from "next/server";
import {getSession} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";

export async function GET(){
 const user=await getSession();
 if(!user)return NextResponse.json({error:"Sessão inválida ou expirada."},{status:401});
 const db=await createClient();
 const now=new Date();
 const monthStart=new Date(now.getFullYear(),now.getMonth(),1).toISOString();
 const nextMonth=new Date(now.getFullYear(),now.getMonth()+1,1).toISOString();
 const [companyResult,customerResult,docsResult]=await Promise.all([
  db.from("tenants").select("id,legal_name,trade_name,nuit,address,currency,tax_regime,activity").eq("id",user.tenantId).maybeSingle(),
  db.from("customers").select("id",{count:"exact",head:true}).eq("tenant_id",user.tenantId),
  db.from("fiscal_documents").select("id,document_type,document_number,status,issue_date,due_date,grand_total,withholding_total,created_at,customers(name,nuit)").eq("tenant_id",user.tenantId).not("document_number","is",null).order("issue_date",{ascending:false}).limit(500)
 ]);
 if(companyResult.error||customerResult.error||docsResult.error){
  console.error("Dashboard query failed",companyResult.error?.message,customerResult.error?.message,docsResult.error?.message);
  return NextResponse.json({error:"Não foi possível carregar os indicadores da empresa."},{status:500});
 }
 const docs=docsResult.data??[];
 const issued=docs.filter(d=>["issued","partially_paid","paid"].includes(d.status));
 const monthDocs=issued.filter(d=>d.issue_date&&d.issue_date>=monthStart&&d.issue_date<nextMonth);
 const documentIds=docs.map(d=>d.id);
 let payments:any[]=[];
 if(documentIds.length){
  const {data,error}=await db.from("customer_payments").select("document_id,amount,received_at").eq("tenant_id",user.tenantId).in("document_id",documentIds);
  if(error){console.error("Dashboard payments query failed",error.message);return NextResponse.json({error:"Não foi possível calcular os recebimentos."},{status:500});}
  payments=data??[];
 }
 const paidByDocument=new Map<string,number>();
 for(const payment of payments)paidByDocument.set(payment.document_id,(paidByDocument.get(payment.document_id)||0)+Number(payment.amount||0));
 const adjustments=new Map<string,number>();
 if(documentIds.length){
  const {data:corrections,error}=await db.from("fiscal_documents").select("corrects_document_id,document_type,grand_total").eq("tenant_id",user.tenantId).in("corrects_document_id",documentIds).in("status",["issued","partially_paid","paid"]);
  if(error)return NextResponse.json({error:"Não foi possível calcular rectificações."},{status:500});
  for(const correction of corrections??[]){const delta=Number(correction.grand_total||0)*(correction.document_type==="NC"?-1:1);adjustments.set(correction.corrects_document_id,(adjustments.get(correction.corrects_document_id)||0)+delta);}
 }
 const invoicedMonth=monthDocs.reduce((sum,d)=>sum+Number(d.grand_total||0),0);
 const outstanding=issued.filter(d=>["FT","FR"].includes(d.document_type)).reduce((sum,d)=>sum+Math.max(0,Number(d.grand_total||0)-Number(d.withholding_total||0)+(adjustments.get(d.id)||0)-(paidByDocument.get(d.id)||0)),0);
 const overdue=issued.filter(d=>["FT","FR"].includes(d.document_type)&&d.due_date&&d.due_date<now.toISOString().slice(0,10)&&Number(d.grand_total||0)-Number(d.withholding_total||0)+(adjustments.get(d.id)||0)>(paidByDocument.get(d.id)||0));
 const recent=docs.slice(0,8).map(d=>({...d,paid_total:paidByDocument.get(d.id)||0,balance:Math.max(0,Number(d.grand_total||0)-Number(d.withholding_total||0)+(adjustments.get(d.id)||0)-(paidByDocument.get(d.id)||0))}));
 const paymentMonth=payments.filter(p=>p.received_at&&p.received_at>=monthStart&&p.received_at<nextMonth).reduce((sum,p)=>sum+Number(p.amount||0),0);
 return NextResponse.json({
  company:companyResult.data,
  metrics:{invoicedMonth,receivable:outstanding,documentsMonth:monthDocs.length,customers:customerResult.count??0,overdueCount:overdue.length,paymentsMonth:paymentMonth},
  recentDocuments:recent,
  generatedAt:now.toISOString()
 });
}
