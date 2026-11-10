import {NextRequest,NextResponse} from "next/server";
import {getSession} from "@/lib/auth";
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
