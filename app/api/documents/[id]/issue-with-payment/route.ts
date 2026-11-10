import {NextRequest,NextResponse} from "next/server";
import {getSession,writeAudit} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
const methods=["cash","bank_transfer","mobile_money","pos","cheque","other"];
export async function POST(req:NextRequest,{params}:{params:Promise<{id:string}>}){
 const user=await getSession();
 if(!user)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin","issuer","accountant"].includes(user.role))return NextResponse.json({error:"Sem permissões para emitir documentos."},{status:403});
 try{
  const {id}=await params;const body=await req.json();const amount=Number(body.amount);
  if(!Number.isFinite(amount)||amount<=0||Math.round(amount*100)!==amount*100||!methods.includes(body.paymentMethod))return NextResponse.json({error:"Indique o valor integral e um meio de pagamento válido."},{status:400});
  const operationId=String(body.operationId||crypto.randomUUID());
  const db=await createClient();
  const {data,error}=await db.rpc("issue_fiscal_document_with_payment",{
   p_document_id:id,p_software_version:"0.1.0",p_amount:amount,p_payment_method:body.paymentMethod,
   p_payment_reference:String(body.reference||""),p_notes:String(body.notes||""),
   p_received_at:body.receivedAt||new Date().toISOString(),p_client_operation_id:operationId
  });
  if(error){const message=error.message||"Não foi possível emitir a Factura-Recibo.";const status=/EMISSÃO BLOQUEADA|autorização|certificação|permissão|adquirente|série activa|Complete|Classifique|Estado|NUIT|domicílio|Meticais|liquidação integral|Factura-Recibo/i.test(message)?409:400;return NextResponse.json({error:message},{status});}
  await writeAudit(user,"document.factura_recibo_issued_with_payment","fiscal_document",id,{payment_id:data.payment_id,internal_receipt_code:data.internal_receipt_code,document:data.document});
  return NextResponse.json({result:data},{status:201});
 }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"Não foi possível processar a Factura-Recibo."},{status:400});}
}