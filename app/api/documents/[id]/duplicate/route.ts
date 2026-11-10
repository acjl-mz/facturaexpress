import {NextRequest,NextResponse} from "next/server";
import {getSession} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";

export async function POST(_req:NextRequest,{params}:{params:Promise<{id:string}>}){
 const user=await getSession();
 if(!user)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin","issuer","accountant"].includes(user.role))return NextResponse.json({error:"Sem permissão para duplicar documentos."},{status:403});
 const {id}=await params;const db=await createClient();
 const {data:source,error:sourceError}=await db.from("fiscal_documents").select("id,tenant_id,customer_id,document_type,status,notes,invoice_template_id").eq("id",id).eq("tenant_id",user.tenantId).single();
 if(sourceError||!source)return NextResponse.json({error:"Documento não encontrado nesta empresa."},{status:404});
 if(!["issued","paid","partially_paid"].includes(source.status))return NextResponse.json({error:"Só é possível duplicar documentos emitidos. Para rascunhos, utilize a edição."},{status:409});
 const {data:sourceLines,error:linesError}=await db.from("fiscal_document_lines").select("item_id,description,quantity,unit,unit_price,discount_amount,tax_code,tax_eligibility_reference,tax_eligibility_category").eq("document_id",id).order("id");
 if(linesError||!sourceLines?.length)return NextResponse.json({error:"Não foi possível recuperar as linhas do documento original."},{status:500});
 const lines=sourceLines.map(line=>({...line}));
 const {data:newId,error}=await db.rpc("create_fiscal_document_draft",{
  p_customer_id:source.customer_id,
  p_document_type:source.document_type,
  p_due_date:null,
  p_notes:source.notes||"",
  p_lines:lines,
  p_client_operation_id:crypto.randomUUID()
 });
 if(error){console.error("Duplicate document RPC failed",error.message);return NextResponse.json({error:"Não foi possível criar o novo rascunho a partir do documento."},{status:400});}
 if(source.invoice_template_id){
  const {error:templateError}=await db.from("fiscal_documents").update({invoice_template_id:source.invoice_template_id}).eq("id",newId).eq("tenant_id",user.tenantId).eq("status","draft");
  if(templateError){console.error("Duplicate template copy failed",templateError.message);return NextResponse.json({id:newId,warning:"Rascunho criado, mas o template original não foi copiado."},{status:201});}
 }
 return NextResponse.json({id:newId,status:"draft",message:"Foi criado um novo rascunho. A numeração fiscal será atribuída apenas no processo de emissão."},{status:201});
}
