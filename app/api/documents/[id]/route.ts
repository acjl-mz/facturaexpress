import {NextRequest,NextResponse} from "next/server";
import {getSession} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
export async function GET(_req:NextRequest,{params}:{params:Promise<{id:string}>}){
 const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});
 const {id}=await params;const s=await createClient();
 const {data:doc,error}=await s.from("fiscal_documents").select("id,tenant_id,customer_id,invoice_template_id,document_type,document_number,status,issue_date,due_date,currency,subtotal,discount_total,tax_total,withholding_total,grand_total,notes,issued_snapshot,created_at,customers(name,nuit,address,email,phone)").eq("tenant_id",u.tenantId).eq("id",id).single();
 if(error||!doc)return NextResponse.json({error:"Documento não encontrado."},{status:404});
 const [{data:lines,error:le},{data:tenant,error:te},{data:template,error:templateError},{data:events,error:eventsError},{data:payments,error:paymentsError}]=await Promise.all([
  s.from("fiscal_document_lines").select("id,item_id,description,quantity,unit,unit_price,discount_amount,tax_code,tax_rate,tax_eligibility_reference,tax_eligibility_category,taxable_amount,tax_amount,line_total").eq("document_id",id).order("id"),
  s.from("tenants").select("legal_name,trade_name,nuit,address,email,phone,currency").eq("id",u.tenantId).single(),
  doc.invoice_template_id?s.from("invoice_templates").select("id,name,settings").eq("id",doc.invoice_template_id).eq("tenant_id",u.tenantId).maybeSingle():Promise.resolve({data:null,error:null}),
  s.from("document_events").select("id,event_type,actor_id,payload,created_at").eq("document_id",id).eq("tenant_id",u.tenantId).order("created_at",{ascending:false}).limit(100),
  s.from("customer_payments").select("id,internal_receipt_code,amount,payment_method,payment_reference,notes,received_at,created_by").eq("document_id",id).eq("tenant_id",u.tenantId).order("received_at",{ascending:false}).limit(100)
 ]);
 if(le||te||templateError||eventsError||paymentsError)return NextResponse.json({error:"Não foi possível carregar todos os dados do documento."},{status:500});
 const paid=(payments??[]).reduce((sum:any,p:any)=>sum+Number(p.amount||0),0);
 const balance=Math.max(0,Number(doc.grand_total||0)-Number(doc.withholding_total||0)-paid);
 return NextResponse.json({document:doc,lines:lines??[],tenant,template,events:events??[],payments:payments??[],paymentSummary:{paid,balance}});
}