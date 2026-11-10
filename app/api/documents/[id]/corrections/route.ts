import {NextRequest,NextResponse} from "next/server";
import {getSession,writeAudit} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
export async function POST(req:NextRequest,{params}:{params:Promise<{id:string}>}){
 const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin","issuer","accountant"].includes(u.role))return NextResponse.json({error:"Sem permissão para preparar rectificações."},{status:403});
 const {id}=await params;
 try{
  const body=await req.json();const correctionType=String(body.type||"");const reason=String(body.reason||"").trim();
  if(!["NC","ND"].includes(correctionType))return NextResponse.json({error:"Seleccione nota de crédito ou nota de débito."},{status:400});
  if(reason.length<8||reason.length>1000)return NextResponse.json({error:"O fundamento deve ter entre 8 e 1000 caracteres."},{status:400});
  const db=await createClient();
  const {data,error}=await db.rpc("create_fiscal_correction_draft",{p_original_document_id:id,p_correction_type:correctionType,p_reason:reason});
  if(error){console.error("Correction draft RPC failed",error.message);return NextResponse.json({error:error.message},{status:400});}
  await writeAudit(u,"document.correction_draft_created","fiscal_document",data,{original_document_id:id,type:correctionType});
  return NextResponse.json({id:data,status:"draft",type:correctionType,message:"Rascunho rectificativo criado. A emissão fiscal deste tipo documental continua bloqueada até validação."},{status:201});
 }catch(e){console.error(e);return NextResponse.json({error:"Não foi possível preparar o documento rectificativo."},{status:400});}
}
