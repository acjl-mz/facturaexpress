import {NextRequest,NextResponse} from "next/server";
import {getSession,writeAudit} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
export async function GET(req:NextRequest){const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});const s=await createClient();const {data,error}=await s.from("tax_obligations").select("*").eq("tenant_id",u.tenantId).order("due_date").limit(500);if(error)return NextResponse.json({error:error.message},{status:500});return NextResponse.json({obligations:data||[]});}
import {NextRequest,NextResponse} from "next/server";
import {getSession,writeAudit} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
const allowed=["IVA","IRPS","IRPC","ISPC","IS","OTHER"];
export async function POST(req:NextRequest){
 const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin","accountant"].includes(u.role))return NextResponse.json({error:"Sem permissões."},{status:403});
 try{
  const b=await req.json();const precision=b.deadlinePrecision||"date";const dueDate=b.dueDate||null;const dueMonth=b.dueMonth?Number(b.dueMonth):null;
  if(!allowed.includes(b.taxType)||!String(b.title||"").trim()||!String(b.referencePeriod||"").trim()||!String(b.description||"").trim())return NextResponse.json({error:"Indique imposto, obrigação, período e fonte oficial."},{status:400});
  if(!/^\d{4}-(0[1-9]|1[0-2]|T[1-4])$/.test(String(b.referencePeriod))&&!/^\d{4}$/.test(String(b.referencePeriod)))return NextResponse.json({error:"Período inválido. Use AAAA-MM, AAAA-T1…T4 ou AAAA."},{status:400});
  if(!["date","month","unconfirmed"].includes(precision))return NextResponse.json({error:"Precisão de prazo inválida."},{status:400});
  if(precision==="date"&&(!dueDate||!/^\d{4}-\d{2}-\d{2}$/.test(String(dueDate))||Number.isNaN(Date.parse(dueDate))))return NextResponse.json({error:"Indique uma data confirmada."},{status:400});
  if(precision==="month"&&(!Number.isInteger(dueMonth)||dueMonth<1||dueMonth>12))return NextResponse.json({error:"Indique o mês confirmado pela AT."},{status:400});
  if(precision==="unconfirmed"&&(dueDate||dueMonth))return NextResponse.json({error:"Não indique uma data ou mês quando o prazo ainda não foi confirmado."},{status:400});
  if(b.officialSourceUrl&&!/^https:\/\//i.test(b.officialSourceUrl))return NextResponse.json({error:"A ligação da fonte oficial deve usar HTTPS."},{status:400});
  const amount=b.estimatedAmount===""||b.estimatedAmount==null?null:Number(b.estimatedAmount);if(amount!==null&&(!Number.isFinite(amount)||amount<0))return NextResponse.json({error:"Valor estimado inválido."},{status:400});
  const s=await createClient();const {data,error}=await s.from("tax_obligations").insert({tenant_id:u.tenantId,tax_type:b.taxType,obligation_code:String(b.code||b.taxType+"-"+b.referencePeriod).trim(),title:String(b.title).trim(),description:String(b.description).trim(),reference_period:String(b.referencePeriod),due_date:dueDate,due_month:dueMonth,deadline_precision:precision,official_source_url:b.officialSourceUrl||null,source_published_at:b.sourcePublishedAt||null,status:"pending",estimated_amount:amount,source:"manual",notes:String(b.notes||"").trim()||null,created_by:u.id}).select().single();
  if(error)throw error;await writeAudit(u,"tax_obligation.created","tax_obligation",data.id,{deadline_precision:precision});return NextResponse.json({obligation:data},{status:201});
 }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"Falha ao criar obrigação."},{status:400});}
}
export async function PATCH(req:NextRequest){const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});if(!["owner","admin"].includes(u.role))return NextResponse.json({error:"Sem permissões."},{status:403});const b=await req.json();if(!b.id||!["pending","in_progress","filed","paid","not_applicable","overdue"].includes(b.status))return NextResponse.json({error:"Estado inválido."},{status:400});const s=await createClient();const update:any={status:b.status,updated_at:new Date().toISOString()};if(b.status==="filed")update.filed_at=new Date().toISOString();if(b.status==="paid")update.paid_at=new Date().toISOString();const {data,error}=await s.from("tax_obligations").update(update).eq("id",b.id).eq("tenant_id",u.tenantId).select().single();if(error)return NextResponse.json({error:error.message},{status:400});await writeAudit(u,"tax_obligation.status_changed","tax_obligation",data.id,{status:b.status});return NextResponse.json({obligation:data});}
