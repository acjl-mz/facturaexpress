import {NextRequest,NextResponse} from "next/server";
import {getSession} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
const methods=["cash","bank_transfer","mobile_money","pos","cheque","other"];
export async function GET(){const u=await getSession();if(!u)return NextResponse.json({error:"Sessão inválida."},{status:401});const s=await createClient();
 const {data:documents,error:de}=await s.from("fiscal_documents").select("id,document_type,document_number,status,issue_date,due_date,currency,grand_total,withholding_total,customers(name,nuit)").eq("tenant_id",u.tenantId).in("document_type",["FT","FR"]).in("status",["issued","partially_paid","paid"]).not("document_number","is",null).order("issue_date",{ascending:false}).limit(300);
 if(de)return NextResponse.json({error:"Não foi possível consultar facturas."},{status:500});
 const ids=(documents??[]).map(d=>d.id);let payments:any[]=[];
 if(ids.length){const {data,error}=await s.from("customer_payments").select("id,document_id,internal_receipt_code,amount,payment_method,payment_reference,notes,received_at,created_by").eq("tenant_id",u.tenantId).in("document_id",ids).order("received_at",{ascending:false});if(error)return NextResponse.json({error:"Não foi possível consultar recebimentos."},{status:500});payments=data??[];}
 const totals=new Map<string,number>();for(const p of payments)totals.set(p.document_id,(totals.get(p.document_id)||0)+Number(p.amount));
 const adjustments=new Map<string,number>();
 if(ids.length){const {data:corrections,error:ce}=await s.from("fiscal_documents").select("corrects_document_id,document_type,grand_total").eq("tenant_id",u.tenantId).in("corrects_document_id",ids).in("status",["issued","paid","partially_paid"]);if(ce)return NextResponse.json({error:"Não foi possível calcular rectificações dos saldos."},{status:500});for(const c of corrections??[]){const delta=Number(c.grand_total||0)*(c.document_type==="NC"?-1:1);adjustments.set(c.corrects_document_id,(adjustments.get(c.corrects_document_id)||0)+delta);}}
 const rows=(documents??[]).map(d=>({...d,paid_total:totals.get(d.id)||0,correction_adjustment:adjustments.get(d.id)||0,balance:Math.max(0,Number(d.grand_total)-Number(d.withholding_total||0)+(adjustments.get(d.id)||0)-(totals.get(d.id)||0))}));
 return NextResponse.json({documents:rows,payments});
}
export async function POST(req:NextRequest){const u=await getSession();if(!u)return NextResponse.json({error:"Sessão inválida."},{status:401});if(!["owner","admin","issuer","accountant"].includes(u.role))return NextResponse.json({error:"Não tem permissão para registar recebimentos."},{status:403});
 try{const b=await req.json();const amount=Number(b.amount);if(typeof b.documentId!=="string"||!Number.isFinite(amount)||amount<=0||Math.round(amount*100)!==amount*100||!methods.includes(b.paymentMethod))return NextResponse.json({error:"Verifique a factura, o valor e o meio de pagamento."},{status:400});
 const operationId=String(b.operationId||crypto.randomUUID());const s=await createClient();const {data,error}=await s.rpc("register_customer_payment",{p_document_id:b.documentId,p_amount:amount,p_payment_method:b.paymentMethod,p_payment_reference:String(b.reference||""),p_notes:String(b.notes||""),p_received_at:b.receivedAt||new Date().toISOString(),p_client_operation_id:operationId});
 if(error)return NextResponse.json({error:error.message},{status:400});return NextResponse.json({id:data,message:"Recebimento registado. Foi criado um comprovativo interno, não fiscal."},{status:201});
 }catch{return NextResponse.json({error:"Não foi possível registar o recebimento."},{status:400});}}
