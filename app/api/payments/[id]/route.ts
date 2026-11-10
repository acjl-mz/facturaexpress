import {NextRequest,NextResponse} from "next/server";
import {getSession} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
export async function GET(_req:NextRequest,{params}:{params:Promise<{id:string}>}){const u=await getSession();if(!u)return NextResponse.json({error:"Sessão inválida."},{status:401});const{id}=await params;const s=await createClient();
 const {data:payment,error}=await s.from("customer_payments").select("id,tenant_id,document_id,internal_receipt_code,amount,payment_method,payment_reference,notes,received_at,created_at").eq("tenant_id",u.tenantId).eq("id",id).single();
 if(error||!payment)return NextResponse.json({error:"Recebimento não encontrado."},{status:404});
 const [{data:doc,error:de},{data:tenant,error:te}]=await Promise.all([
 s.from("fiscal_documents").select("id,document_type,document_number,currency,grand_total,withholding_total,customers(name,nuit,address,email,phone)").eq("tenant_id",u.tenantId).eq("id",payment.document_id).single(),
 s.from("tenants").select("legal_name,trade_name,nuit,address,email,phone").eq("id",u.tenantId).single()]);
 if(de||te)return NextResponse.json({error:"Não foi possível carregar o comprovativo."},{status:500});
 const {data:all,error:ae}=await s.from("customer_payments").select("amount").eq("tenant_id",u.tenantId).eq("document_id",payment.document_id);
 if(ae)return NextResponse.json({error:"Não foi possível calcular o saldo."},{status:500});
 const paid=(all??[]).reduce((n,p)=>n+Number(p.amount),0);
 const {data:corrections,error:ce}=await s.from("fiscal_documents").select("document_type,grand_total").eq("tenant_id",u.tenantId).eq("corrects_document_id",payment.document_id).in("status",["issued","paid","partially_paid"]);
 if(ce)return NextResponse.json({error:"Não foi possível calcular o saldo após rectificações."},{status:500});
 const correctionAdjustment=(corrections??[]).reduce((n,c)=>n+(c.document_type==="NC"?-1:1)*Number(c.grand_total||0),0);
 const balance=Math.max(0,Number(doc.grand_total)-Number(doc.withholding_total||0)+correctionAdjustment-paid);
 return NextResponse.json({payment,document:doc,tenant,paid_total:paid,correction_adjustment:correctionAdjustment,balance});
}