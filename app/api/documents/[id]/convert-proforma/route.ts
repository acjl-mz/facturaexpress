import {NextRequest,NextResponse} from "next/server";
import {getSession,writeAudit} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";

export async function POST(_req:NextRequest,{params}:{params:Promise<{id:string}>}){
 const user=await getSession();
 if(!user)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin","issuer","accountant"].includes(user.role))
  return NextResponse.json({error:"Sem permissão para converter proformas."},{status:403});
 const {id}=await params;
 const db=await createClient();
 const operationId=crypto.randomUUID();
 const {data:newId,error}=await db.rpc("convert_proforma_to_invoice",{
  p_source_document_id:id,
  p_client_operation_id:operationId
 });
 if(error){
  const message=error.message||"Não foi possível converter a proforma.";
  const status=/não encontrada|não permite|apenas para proformas|sem empresa|sessão inválida/i.test(message)?409:400;
  console.error("Proforma conversion failed",message);
  return NextResponse.json({error:message},{status});
 }
 const {data:invoice,error:invoiceError}=await db.from("fiscal_documents")
  .select("id,status,document_type,converted_from_document_id")
  .eq("id",newId).eq("tenant_id",user.tenantId).single();
 if(invoiceError||!invoice)
  return NextResponse.json({error:"A conversão foi processada, mas não foi possível confirmar a factura criada."},{status:500});
 await writeAudit(user,"document.proforma_conversion_requested","fiscal_document",newId,{
  source_document_id:id,
  idempotent_retry:invoice.converted_from_document_id===id
 });
 return NextResponse.json({
  id:newId,
  status:invoice.status,
  sourceDocumentId:id,
  message:"Factura em rascunho preparada. A proforma original foi preservada e a numeração fiscal será atribuída apenas na emissão."
 },{status:201});
}
