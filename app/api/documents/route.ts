import {NextRequest,NextResponse} from "next/server";
import {getSession,writeAudit} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";

const allowedStatuses = new Set(["draft","issued","paid","partially_paid","voided"]);
const allowedTypes = new Set(["FT","FR","PF","NC","ND"]);

export async function GET(req:NextRequest){
 const user=await getSession();
 if(!user)return NextResponse.json({error:"Não autenticado."},{status:401});
 const params=req.nextUrl.searchParams;
 const q=(params.get("q")||"").trim().slice(0,80);
 const requestedStatus=params.get("status")||"";
 const requestedType=params.get("type")||"";
 const from=params.get("from")||"";
 const to=params.get("to")||"";
 const page=Math.max(1,Math.min(10000,Number.parseInt(params.get("page")||"1",10)||1));
 const pageSize=Math.max(10,Math.min(100,Number.parseInt(params.get("pageSize")||"25",10)||25));
 if((requestedStatus&&!allowedStatuses.has(requestedStatus))||(requestedType&&!allowedTypes.has(requestedType)))
  return NextResponse.json({error:"Filtro documental inválido."},{status:400});
 const validDate=(value:string)=>/^\d{4}-\d{2}-\d{2}$/.test(value)&&!Number.isNaN(Date.parse(value+"T00:00:00Z"));
 if((from&&!validDate(from))||(to&&!validDate(to))||(from&&to&&from>to))
  return NextResponse.json({error:"Intervalo de datas inválido."},{status:400});

 const db=await createClient();
 let query=db.from("fiscal_documents")
  .select("id,document_type,document_number,status,issue_date,due_date,subtotal,discount_total,tax_total,grand_total,created_at,customers(name,nuit)",{count:"exact"})
  .eq("tenant_id",user.tenantId)
  .order("created_at",{ascending:false});

 if(requestedStatus)query=query.eq("status",requestedStatus);
 if(requestedType)query=query.eq("document_type",requestedType);
 // A listagem inclui rascunhos, por isso o período é explicitamente a data de registo.
 if(from)query=query.gte("created_at",from+"T00:00:00");
 if(to)query=query.lt("created_at",new Date(new Date(to+"T00:00:00").getTime()+86400000).toISOString());

 if(q){
  // Keep PostgREST filter syntax out of user-controlled input.
  const safe=q.replace(/[^\p{L}\p{N}\s._-]/gu," ").replace(/\s+/g," ").trim();
  if(!safe)return NextResponse.json({documents:[],total:0,page,pageSize});
  const [{data:customers,error:customerError},{data:direct,error:directError}]=await Promise.all([
   db.from("customers").select("id").eq("tenant_id",user.tenantId).or("name.ilike.%"+safe+"%,nuit.ilike.%"+safe+"%").limit(250),
   db.from("fiscal_documents").select("id").eq("tenant_id",user.tenantId).or("document_number.ilike.%"+safe+"%,document_type.ilike.%"+safe+"%").limit(500)
  ]);
  if(customerError||directError){
   console.error("Document search failed",customerError?.message,directError?.message);
   return NextResponse.json({error:"Não foi possível pesquisar documentos."},{status:500});
  }
  const customerIds=(customers||[]).map((customer:any)=>customer.id);
  const ids=(direct||[]).map((document:any)=>document.id);
  if(customerIds.length){
   const {data:byCustomer,error}=await db.from("fiscal_documents").select("id").eq("tenant_id",user.tenantId).in("customer_id",customerIds).limit(500);
   if(error)return NextResponse.json({error:"Não foi possível pesquisar documentos por cliente."},{status:500});
   ids.push(...(byCustomer||[]).map((document:any)=>document.id));
  }
  const unique=[...new Set(ids)];
  if(!unique.length)return NextResponse.json({documents:[],total:0,page,pageSize});
  query=query.in("id",unique);
 }
 const offset=(page-1)*pageSize;
 const {data,error,count}=await query.range(offset,offset+pageSize-1);
 if(error){
  console.error("Document list query failed",error.message);
  return NextResponse.json({error:"Não foi possível consultar documentos."},{status:500});
 }
 return NextResponse.json({documents:data??[],total:count??0,page,pageSize});
}

export async function POST(req:NextRequest){
 const user=await getSession();
 if(!user)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin","issuer","accountant"].includes(user.role))return NextResponse.json({error:"Sem permissão para preparar documentos."},{status:403});
 try{
  const b=await req.json();
  const documentType=String(b.documentType||"");
  if(!["FT","FR"].includes(documentType))return NextResponse.json({error:"Tipo de documento inválido."},{status:400});
  if(!Array.isArray(b.lines)||b.lines.length<1||b.lines.length>100)return NextResponse.json({error:"O documento deve conter entre 1 e 100 linhas."},{status:400});
  const operationId=String(b.operationId||"");
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(operationId))return NextResponse.json({error:"Identificador de operação inválido."},{status:400});
  const lines=b.lines.map((line:any)=>({
   item_id:line.itemId||null,
   description:String(line.description||"").trim(),
   quantity:Number(line.quantity),
   unit:String(line.unit||"UN").trim(),
   unit_price:Number(line.unitPrice),
   discount_amount:Number(line.discount||0),
   tax_code:line.taxCode||null,
   tax_eligibility_reference:line.taxEligibilityReference||null,
   tax_eligibility_category:line.taxEligibilityCategory||null
  }));
  if(lines.some((line:any)=>!line.description||!Number.isFinite(line.quantity)||line.quantity<=0||!Number.isFinite(line.unit_price)||line.unit_price<0||!Number.isFinite(line.discount_amount)||line.discount_amount<0))return NextResponse.json({error:"Existem linhas com descrição, quantidade, preço ou desconto inválidos."},{status:400});
  const db=await createClient();
  const {data:taxProfile,error:taxProfileError}=await db.from("tenant_tax_profiles").select("regime_code,confirmation_status,ispc_opt_in,ispc_primary_activity_code,ispc_annual_reference_turnover,ispc_reference_confirmed,at_activity_confirmation_reference").eq("tenant_id",user.tenantId).maybeSingle();
  if(taxProfileError)return NextResponse.json({error:"Não foi possível validar o perfil fiscal."},{status:500});
  if(!taxProfile||taxProfile.confirmation_status!=="confirmed")return NextResponse.json({error:"Configure e confirme o perfil fiscal da empresa antes de preparar documentos."},{status:409});
  if(!["IVA_REGULAR","ISPC"].includes(taxProfile.regime_code))return NextResponse.json({error:"O regime fiscal desta empresa ainda não está habilitado para facturação no FacturaExpress."},{status:409});
  if(taxProfile.regime_code==="ISPC"&&(!taxProfile.ispc_opt_in||!taxProfile.ispc_primary_activity_code||!taxProfile.ispc_reference_confirmed||!taxProfile.ispc_annual_reference_turnover||!taxProfile.at_activity_confirmation_reference))return NextResponse.json({error:"O enquadramento ISPC está incompleto. Confirme a actividade principal e os dados de referência antes de facturar."},{status:409});
  const {data:id,error}=await db.rpc("create_fiscal_document_draft",{
   p_customer_id:b.customerId||null,
   p_document_type:documentType,
   p_due_date:b.dueDate||null,
   p_notes:String(b.notes||"").slice(0,2000),
   p_lines:lines,
   p_client_operation_id:operationId
  });
  if(error){console.error("Draft creation RPC failed",error.message);return NextResponse.json({error:error.message||"Não foi possível criar o rascunho."},{status:400});}
  if(b.templateId){
   const {data:template,error:templateError}=await db.from("invoice_templates").select("id").eq("id",b.templateId).eq("tenant_id",user.tenantId).eq("is_active",true).maybeSingle();
   if(templateError||!template)return NextResponse.json({id,status:"draft",warning:"Rascunho criado, mas o modelo seleccionado não foi encontrado. Será usado o modelo padrão."},{status:201});
   const {error:updateError}=await db.from("fiscal_documents").update({invoice_template_id:template.id}).eq("id",id).eq("tenant_id",user.tenantId).eq("status","draft");
   if(updateError)console.error("Draft template assignment failed",updateError.message);
  }
  await writeAudit(user,"document.draft_requested","fiscal_document",id,{document_type:documentType,line_count:lines.length});
  return NextResponse.json({id,status:"draft",message:"Rascunho criado. Os impostos e totais foram calculados pelo motor fiscal no Supabase."},{status:201});
 }catch(e){console.error("Draft creation failed",e);return NextResponse.json({error:"Não foi possível preparar o documento."},{status:400});}
}


export async function PATCH(req:NextRequest){
 const user=await getSession();
 if(!user)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin","issuer","accountant"].includes(user.role))return NextResponse.json({error:"Sem permissão para alterar documentos."},{status:403});
 try{
  const b=await req.json();
  const documentId=String(b.id||"");
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(documentId))
   return NextResponse.json({error:"Identificador do documento inválido."},{status:400});
  if(!Array.isArray(b.lines)||b.lines.length<1||b.lines.length>100)
   return NextResponse.json({error:"O documento deve conter entre 1 e 100 linhas."},{status:400});
  const dueDate=b.dueDate===null||b.dueDate===""?null:String(b.dueDate);
  if(dueDate&&(!/^\d{4}-\d{2}-\d{2}$/.test(dueDate)||Number.isNaN(Date.parse(dueDate+"T00:00:00Z"))))
   return NextResponse.json({error:"Data de vencimento inválida."},{status:400});
  const notes=String(b.notes||"");
  if(notes.length>2000)return NextResponse.json({error:"As observações não podem exceder 2.000 caracteres."},{status:400});
  const lines=b.lines.map((line:any)=>({
   item_id:line.itemId||null,
   description:String(line.description||"").trim(),
   quantity:Number(line.quantity),
   unit:String(line.unit||"UN").trim(),
   unit_price:Number(line.unitPrice),
   discount_amount:Number(line.discount||0),
   tax_code:line.taxCode||null,
   tax_eligibility_reference:line.taxEligibilityReference||null,
   tax_eligibility_category:line.taxEligibilityCategory||null
  }));
  if(lines.some((line:any)=>!line.description||line.description.length>500||!Number.isFinite(line.quantity)||line.quantity<=0||line.quantity>100000000||!Number.isFinite(line.unit_price)||line.unit_price<0||line.unit_price>1000000000000||!Number.isFinite(line.discount_amount)||line.discount_amount<0||line.discount_amount>1000000000000||!line.unit||line.unit.length>20))
   return NextResponse.json({error:"Existem linhas com descrição, quantidade, unidade, preço ou desconto inválidos."},{status:400});
  const db=await createClient();
  const {data:document,error:documentError}=await db.from("fiscal_documents").select("id,status,document_type").eq("id",documentId).eq("tenant_id",user.tenantId).maybeSingle();
  if(documentError)return NextResponse.json({error:"Não foi possível validar o documento."},{status:500});
  if(!document)return NextResponse.json({error:"Documento não encontrado."},{status:404});
  if(document.status!=="draft")return NextResponse.json({error:"Apenas rascunhos podem ser alterados."},{status:409});
  if(b.templateId){
   const {data:template,error:templateError}=await db.from("invoice_templates").select("id").eq("id",b.templateId).eq("tenant_id",user.tenantId).eq("is_active",true).maybeSingle();
   if(templateError)return NextResponse.json({error:"Não foi possível validar o modelo visual."},{status:500});
   if(!template)return NextResponse.json({error:"O modelo visual seleccionado não está disponível nesta empresa."},{status:400});
  }
  const {data:id,error}=await db.rpc("update_fiscal_document_draft",{
   p_document_id:documentId,
   p_customer_id:b.customerId||null,
   p_due_date:dueDate,
   p_notes:notes,
   p_lines:lines
  });
  if(error){
   console.error("Draft update RPC failed",error.message);
   return NextResponse.json({error:error.message||"Não foi possível actualizar o rascunho."},{status:400});
  }
  let warning:string|undefined;
  if(b.templateId!==undefined){
   const {error:templateUpdateError}=await db.from("fiscal_documents").update({invoice_template_id:b.templateId||null}).eq("id",documentId).eq("tenant_id",user.tenantId).eq("status","draft");
   if(templateUpdateError){
    console.error("Draft template update failed",templateUpdateError.message);
    warning="Os dados e os valores fiscais foram actualizados, mas não foi possível guardar o modelo visual seleccionado.";
   }
  }
  return NextResponse.json({id:id||documentId,status:"draft",message:"Rascunho actualizado. Os impostos e totais foram recalculados no Supabase.",...(warning?{warning}:{})});
 }catch(e){
  console.error("Draft update failed",e);
  return NextResponse.json({error:"Não foi possível actualizar o rascunho."},{status:400});
 }
}
