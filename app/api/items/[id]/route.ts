import {NextRequest,NextResponse} from "next/server";
import {getSession,writeAudit} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
export async function PATCH(req:NextRequest,{params}:{params:Promise<{id:string}>}){
 const user=await getSession();if(!user)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin","manager","accountant"].includes(user.role))return NextResponse.json({error:"Sem permissão para alterar artigos."},{status:403});
 const {id}=await params;
 try{
  const b=await req.json();const s=await createClient();const patch:Record<string,unknown>={};
  if(typeof b.active==="boolean")patch.active=b.active;
  if(b.description!==undefined){const v=String(b.description).trim();if(!v)return NextResponse.json({error:"A descrição é obrigatória."},{status:400});patch.description=v;}
  if(b.code!==undefined)patch.code=String(b.code).trim()||null;
  if(b.unit!==undefined)patch.unit=String(b.unit).trim()||"UN";
  if(b.unitPrice!==undefined){const v=Number(b.unitPrice);if(!Number.isFinite(v)||v<0)return NextResponse.json({error:"O preço deve ser igual ou superior a zero."},{status:400});patch.unit_price=v;}
  if(b.taxCode!==undefined)patch.tax_code=String(b.taxCode).trim()||null;
  if(!Object.keys(patch).length)return NextResponse.json({error:"Não foram indicadas alterações."},{status:400});
  const {data,error}=await s.from("items").update(patch).eq("id",id).eq("tenant_id",user.tenantId).select("id,code,description,unit,unit_price,tax_code,active").maybeSingle();
  if(error)throw error;if(!data)return NextResponse.json({error:"Artigo não encontrado nesta empresa."},{status:404});
  await writeAudit(user,typeof b.active==="boolean"?"item.status_changed":"item.updated","item",id);
  return NextResponse.json({item:data});
 }catch(e){console.error("Item update failed",e);return NextResponse.json({error:"Não foi possível actualizar o artigo."},{status:400});}
}