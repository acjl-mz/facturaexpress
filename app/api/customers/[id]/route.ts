import {NextRequest,NextResponse} from "next/server";
import {getSession,writeAudit} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
export async function PATCH(req:NextRequest,{params}:{params:Promise<{id:string}>}){
 const user=await getSession();if(!user)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin","manager","accountant"].includes(user.role))return NextResponse.json({error:"Sem permissão para alterar clientes."},{status:403});
 const {id}=await params;
 try{
  const b=await req.json();const name=String(b.name??"").trim();
  if(!name)return NextResponse.json({error:"O nome do cliente é obrigatório."},{status:400});
  const s=await createClient();
  const {data,error}=await s.from("customers").update({
   name,nuit:String(b.nuit??"").trim()||null,address:String(b.address??"").trim()||null,
   email:String(b.email??"").trim()||null,phone:String(b.phone??"").trim()||null,
   tax_status:String(b.taxStatus??"").trim()||null
  }).eq("id",id).eq("tenant_id",user.tenantId).select("id,name,nuit,address,email,phone,tax_status").maybeSingle();
  if(error)throw error;if(!data)return NextResponse.json({error:"Cliente não encontrado nesta empresa."},{status:404});
  await writeAudit(user,"customer.updated","customer",id);
  return NextResponse.json({customer:data});
 }catch(e){console.error("Customer update failed",e);return NextResponse.json({error:"Não foi possível actualizar o cliente."},{status:400});}
}