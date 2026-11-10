import {NextRequest,NextResponse} from "next/server";import {getSession,writeAudit} from "@/lib/auth";import {createClient} from "@/lib/supabase/server";
export async function GET(req:NextRequest){
 const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});
 const params=req.nextUrl.searchParams;
 const q=(params.get("q")||"").trim().slice(0,80);
 const status=params.get("status")||"";
 const from=params.get("from")||"";
 const to=params.get("to")||"";
 const s=await createClient();
 let query=s.from("fiscal_documents").select("id,document_type,document_number,status,issue_date,due_date,subtotal,discount_total,tax_total,grand_total,created_at,customers(name,nuit)").eq("tenant_id",u.tenantId).order("created_at",{ascending:false}).limit(250);
 if(status)query=query.eq("status",status);
 if(from)query=query.gte("created_at",from+"T00:00:00");
 if(to)query=query.lt("created_at",new Date(new Date(to+"T00:00:00").getTime()+86400000).toISOString());
 if(q){
  const safe=q.replace(/[,%()]/g," ").replace(/\s+/g," ").trim();
  const [{data:customers,error:customerError},{data:direct,error:directError}]=await Promise.all([
   s.from("customers").select("id").eq("tenant_id",u.tenantId).or("name.ilike.%"+safe+"%,nuit.ilike.%"+safe+"%").limit(100),
   s.from("fiscal_documents").select("id").eq("tenant_id",u.tenantId).or("document_number.ilike.%"+safe+"%,document_type.ilike.%"+safe+"%").limit(250)
  ]);
  if(customerError||directError)return NextResponse.json({error:"Não foi possível pesquisar documentos."},{status:500});
  const ids=[...(direct||[]).map((x:any)=>x.id)];
  const customerIds=(customers||[]).map((x:any)=>x.id);
  if(customerIds.length){
   const {data:byCustomer,error:customerDocsError}=await s.from("fiscal_documents").select("id").eq("tenant_id",u.tenantId).in("customer_id",customerIds).limit(250);
   if(customerDocsError)return NextResponse.json({error:"Não foi possível pesquisar documentos por cliente."},{status:500});
   ids.push(...(byCustomer||[]).map((x:any)=>x.id));
  }
  const unique=[...new Set(ids)];
  if(!unique.length)return NextResponse.json({documents:[]});
  query=query.in("id",unique);
 }
 const {data,error}=await query;
 if(error)return NextResponse.json({error:"Não foi possível consultar documentos."},{status:500});
 return NextResponse.json({documents:data??[]});
}
export async function POST(req:NextRequest){const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});try{const b=await req.json();if(!["FT","FR"].includes(b.documentType))return NextResponse.json({error:"Tipo de documento inválido."},{status:400});if(!Array.isArray(b.lines)||!b.lines.length||b.lines.length>100)return NextResponse.json({error:"Adicione entre 1 e 100 linhas."},{status:400});const lines=b.lines.map((x:any)=>({item_id:x.itemId||null,description:String(x.description??"").trim(),quantity:Number(x.quantity),unit:String(x.unit||"UN"),unit_price:Number(x.unitPrice),discount_amount:Number(x.discount??0),tax_code:x.taxCode||null,tax_eligibility_reference:x.taxEligibilityReference||null,tax_eligibility_category:x.taxEligibilityCategory||null}));for(const l of lines){if(!l.description||!Number.isFinite(l.quantity)||l.quantity<=0||!Number.isFinite(l.unit_price)||l.unit_price<0||!Number.isFinite(l.discount_amount)||l.discount_amount<0)return NextResponse.json({error:"Verifique descrição, quantidade, preço e desconto das linhas."},{status:400});}const operationId=String(b.operationId||crypto.randomUUID());const s=await createClient();if(b.templateId){const {data:template,error:templateError}=await s.from("invoice_templates").select("id").eq("id",b.templateId).eq("tenant_id",u.tenantId).eq("is_active",true).maybeSingle();if(templateError||!template)return NextResponse.json({error:"Template inválido para esta empresa."},{status:400});}const {data,error}=await s.rpc("create_fiscal_document_draft",{p_customer_id:b.customerId||null,p_document_type:b.documentType,p_due_date:b.dueDate||null,p_notes:String(b.notes||""),p_lines:lines,p_client_operation_id:operationId});if(error){console.error("Draft RPC failed",error.message);return NextResponse.json({error:error.message},{status:400});}if(b.templateId){const {error:templateLinkError}=await s.from("fiscal_documents").update({invoice_template_id:b.templateId}).eq("id",data).eq("tenant_id",u.tenantId).eq("status","draft");if(templateLinkError){console.error("Draft template link failed",templateLinkError.message);return NextResponse.json({error:"O rascunho foi criado, mas não foi possível associar o template."},{status:500});}}return NextResponse.json({id:data,status:"draft",message:"Rascunho guardado. Não é documento fiscal emitido."},{status:201});}catch(e){console.error(e);return NextResponse.json({error:"Não foi possível guardar o rascunho."},{status:400});}}

export async function PATCH(req:NextRequest){
 const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin","issuer","accountant"].includes(u.role))return NextResponse.json({error:"Sem permissões para editar rascunhos."},{status:403});
 try{
  const b=await req.json();const id=String(b.id||"");
  if(!id||!Array.isArray(b.lines)||!b.lines.length||b.lines.length>100)return NextResponse.json({error:"Documento ou linhas inválidos."},{status:400});
  const lines=b.lines.map((x:any)=>({item_id:x.itemId||null,description:String(x.description??"").trim(),quantity:Number(x.quantity),unit:String(x.unit||"UN"),unit_price:Number(x.unitPrice),discount_amount:Number(x.discount??0),tax_code:x.taxCode||null,tax_eligibility_reference:x.taxEligibilityReference||null,tax_eligibility_category:x.taxEligibilityCategory||null}));
  for(const l of lines){if(!l.description||!Number.isFinite(l.quantity)||l.quantity<=0||!Number.isFinite(l.unit_price)||l.unit_price<0||!Number.isFinite(l.discount_amount)||l.discount_amount<0)return NextResponse.json({error:"Verifique descrição, quantidade, preço e desconto das linhas."},{status:400});}
  const s=await createClient();
  if(b.templateId){const {data:template,error:templateError}=await s.from("invoice_templates").select("id").eq("id",b.templateId).eq("tenant_id",u.tenantId).eq("is_active",true).maybeSingle();if(templateError||!template)return NextResponse.json({error:"Template inválido para esta empresa."},{status:400});}
  const {data,error}=await s.rpc("update_fiscal_document_draft",{p_document_id:id,p_customer_id:b.customerId||null,p_due_date:b.dueDate||null,p_notes:String(b.notes||""),p_lines:lines});
  if(error){console.error("Draft update RPC failed",error.message);return NextResponse.json({error:error.message},{status:400});}
  const {error:templateUpdateError}=await s.from("fiscal_documents").update({invoice_template_id:b.templateId||null}).eq("id",id).eq("tenant_id",u.tenantId).eq("status","draft");
  if(templateUpdateError){console.error("Draft template update failed",templateUpdateError.message);return NextResponse.json({error:"Rascunho actualizado, mas não foi possível guardar o modelo visual."},{status:500});}
  await writeAudit(u,"document.draft_updated","fiscal_document",id,{line_count:lines.length});
  return NextResponse.json({id:data,status:"draft",message:"Rascunho actualizado."});
 }catch(e){console.error(e);return NextResponse.json({error:"Não foi possível actualizar o rascunho."},{status:400});}
}
