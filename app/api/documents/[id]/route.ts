import {NextRequest,NextResponse} from "next/server";
import {getSession} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
export async function GET(_req:NextRequest,{params}:{params:Promise<{id:string}>}){
 const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});
 const {id}=await params;const s=await createClient();
 const {data:doc,error}=await s.from("fiscal_documents").select("id,tenant_id,customer_id,invoice_template_id,document_type,document_number,status,issue_date,due_date,currency,subtotal,discount_total,tax_total,withholding_total,grand_total,notes,issued_snapshot,created_at,customers(name,nuit,address,email,phone)").eq("tenant_id",u.tenantId).eq("id",id).single();
 if(error||!doc)return NextResponse.json({error:"Documento não encontrado."},{status:404});
 const [{data:lines,error:le},{data:tenant,error:te},{data:template,error:templateError}]=await Promise.all([
  s.from("fiscal_document_lines").select("id,item_id,description,quantity,unit,unit_price,discount_amount,tax_code,tax_rate,tax_eligibility_reference,tax_eligibility_category,tax_eligibility_reference,tax_eligibility_category,taxable_amount,tax_amount,line_total").eq("document_id",id).order("id"),
  s.from("tenants").select("legal_name,trade_name,nuit,address,email,phone,currency").eq("id",u.tenantId).single(),
  doc.invoice_template_id?s.from("invoice_templates").select("id,name,settings").eq("id",doc.invoice_template_id).eq("tenant_id",u.tenantId).maybeSingle():Promise.resolve({data:null,error:null})
 ]);
 if(le||te||templateError)return NextResponse.json({error:"Não foi possível carregar todos os dados do documento."},{status:500});
 return NextResponse.json({document:doc,lines:lines??[],tenant,template});
}