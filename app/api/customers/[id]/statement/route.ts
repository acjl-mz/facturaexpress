import {NextRequest,NextResponse} from "next/server";
import {getSession} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
export async function GET(req:NextRequest,{params}:{params:Promise<{id:string}>}){
 const user=await getSession();if(!user)return NextResponse.json({error:"Sessão inválida."},{status:401});
 const {id}=await params;const query=req.nextUrl.searchParams;const from=query.get("from")||"";const to=query.get("to")||"";
 const db=await createClient();
 const {data:customer,error:customerError}=await db.from("customers").select("id,name,nuit,address,email,phone").eq("id",id).eq("tenant_id",user.tenantId).maybeSingle();
 if(customerError||!customer)return NextResponse.json({error:"Cliente não encontrado nesta empresa."},{status:404});
 let q=db.from("fiscal_documents").select("id,document_type,document_number,status,issue_date,due_date,currency,subtotal,tax_total,withholding_total,grand_total,corrects_document_id,correction_reason,created_at").eq("tenant_id",user.tenantId).eq("customer_id",id).not("document_number","is",null).order("issue_date",{ascending:false}).limit(500);
 if(from)q=q.gte("issue_date",from);if(to)q=q.lte("issue_date",to);
 const {data:documents,error}=await q;if(error)return NextResponse.json({error:"Não foi possível consultar o extracto."},{status:500});
 const ids=(documents||[]).map(d=>d.id);let payments:any[]=[];let corrections:any[]=[];
 if(ids.length){
  const [p,c]=await Promise.all([
   db.from("customer_payments").select("id,document_id,internal_receipt_code,amount,payment_method,payment_reference,received_at").eq("tenant_id",user.tenantId).in("document_id",ids).order("received_at",{ascending:false}),
   db.from("fiscal_documents").select("id,document_type,document_number,status,issue_date,grand_total,corrects_document_id").eq("tenant_id",user.tenantId).in("corrects_document_id",ids).in("status",["issued","paid","partially_paid"])
  ]);
  if(p.error||c.error)return NextResponse.json({error:"Não foi possível carregar pagamentos ou rectificações."},{status:500});
  payments=p.data||[];corrections=c.data||[];
 }
 const paid=new Map<string,number>();for(const p of payments)paid.set(p.document_id,(paid.get(p.document_id)||0)+Number(p.amount||0));
 const adjustment=new Map<string,number>();for(const c of corrections)adjustment.set(c.corrects_document_id,(adjustment.get(c.corrects_document_id)||0)+Number(c.grand_total||0)*(c.document_type==="NC"?-1:1));
 const receivableTypes=["FT","FR"];const rows=(documents||[]).map(d=>{const isReceivable=receivableTypes.includes(d.document_type)&&d.status!=="voided";const paidTotal=paid.get(d.id)||0;const correctionAdjustment=adjustment.get(d.id)||0;return {...d,paid_total:paidTotal,correction_adjustment:correctionAdjustment,balance:isReceivable?Math.max(0,Number(d.grand_total||0)-Number(d.withholding_total||0)+correctionAdjustment-paidTotal):0};});
 const totals=rows.reduce((a,d)=>{const isReceivable=receivableTypes.includes(d.document_type)&&d.status!=="voided";return {gross:a.gross+(isReceivable?Number(d.grand_total||0):0),withholding:a.withholding+(isReceivable?Number(d.withholding_total||0):0),paid:a.paid+(isReceivable?Number(d.paid_total||0):0),adjustments:a.adjustments+(isReceivable?Number(d.correction_adjustment||0):0),balance:a.balance+Number(d.balance||0)};},{gross:0,withholding:0,paid:0,adjustments:0,balance:0});
 return NextResponse.json({customer,documents:rows,payments,corrections,totals,filters:{from,to}});
}