import {NextRequest,NextResponse} from "next/server";
import {getSession,writeAudit} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
export async function POST(_req:NextRequest,{params}:{params:Promise<{id:string}>}){
 const user=await getSession();if(!user)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin","issuer","accountant"].includes(user.role))return NextResponse.json({error:"Sem permissão para converter proformas."},{status:403});
 const {id}=await params;const db=await createClient();
 const {data:source,error:sourceError}=await db.from("fiscal_documents").select("id,customer_id,document_type,document_number,status,notes,invoice_template_id,due_date").eq("id",id).eq("tenant_id",user.tenantId).maybeSingle();
 if(sourceError||!source)return NextResponse.json({error:"Proforma não encontrada nesta empresa."},{status:404});
 if(source.document_type!=="PF")return NextResponse.json({error:"A conversão está disponível apenas para proformas."},{status:409});
 if(!["draft","issued","paid","partially_paid"].includes(source.status))return NextResponse.json({error:"O estado actual da proforma não permite conversão."},{status:409});
 const {data:lines,error:linesError}=await db.from("fiscal_document_lines").select("item_id,description,quantity,unit,unit_price,discount_amount,tax_code,tax_eligibility_reference,tax_eligibility_category").eq("document_id",id).order("id");
 if(linesError||!lines?.length)return NextResponse.json({error:"Não foi possível recuperar as linhas da proforma."},{status:500});
 const reference=source.document_number||id;
 const notes=[source.notes||"", "Factura preparada a partir da proforma "+reference+" (referência interna: "+id+")."].filter(Boolean).join("\n");
 const {data:newId,error}=await db.rpc("create_fiscal_document_draft",{p_customer_id:source.customer_id,p_document_type:"FT",p_due_date:source.due_date||null,p_notes:notes,p_lines:lines,p_client_operation_id:crypto.randomUUID()});
 if(error){console.error("Proforma conversion failed",error.message);return NextResponse.json({error:"Não foi possível criar a factura a partir da proforma."},{status:400});}
 if(source.invoice_template_id){
  const {error:templateError}=await db.from("fiscal_documents").update({invoice_template_id:source.invoice_template_id}).eq("id",newId).eq("tenant_id",user.tenantId).eq("status","draft");
  if(templateError)return NextResponse.json({id:newId,status:"draft",warning:"Factura criada, mas o modelo visual não foi copiado."},{status:201});
 }
 await writeAudit(user,"document.proforma_converted","fiscal_document",newId,{source_document_id:id,source_document_number:source.document_number});
 return NextResponse.json({id:newId,status:"draft",sourceDocumentId:id,message:"Nova factura em rascunho criada. A proforma original foi preservada e a numeração fiscal será atribuída apenas na emissão."},{status:201});
}