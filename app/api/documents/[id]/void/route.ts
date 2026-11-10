import {NextRequest,NextResponse} from "next/server";
import {getSession,writeAudit} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";

export async function POST(req:NextRequest,{params}:{params:Promise<{id:string}>}) {
 const user=await getSession();
 if(!user)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin"].includes(user.role))return NextResponse.json({error:"Apenas proprietário ou administrador pode anular documentos."},{status:403});
 const {id}=await params;
 try {
  const body=await req.json();
  const reason=String(body.reason||"").trim();
  if(reason.length<10||reason.length>1000)return NextResponse.json({error:"O fundamento deve ter entre 10 e 1000 caracteres."},{status:400});
  const db=await createClient();
  const {data,error}=await db.rpc("void_fiscal_document",{p_document_id:id,p_reason:reason});
  if(error) {
   const message=error.message||"Não foi possível anular o documento.";
   const status=/não encontrado|apenas proprietário|recebimentos|estado|anul|rectificativas|fundamento/i.test(message)?409:400;
   return NextResponse.json({error:message},{status});
  }
  await writeAudit(user,"document.fiscal_voided","fiscal_document",id,{reason});
  return NextResponse.json({result:data,message:"Documento marcado como anulado. O registo original foi preservado."});
 } catch(e) {
  console.error("Document void failed",e);
  return NextResponse.json({error:"Não foi possível anular o documento."},{status:400});
 }
}
