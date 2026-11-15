import {NextRequest,NextResponse} from "next/server";
import {getSession,writeAudit} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
export async function GET(req:NextRequest){const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});const s=await createClient();const {data,error}=await s.from("tax_obligations").select("*").eq("tenant_id",u.tenantId).order("due_date").limit(500);if(error)return NextResponse.json({error:error.message},{status:500});return NextResponse.json({obligations:data||[]});}
const allowed=["IVA","IRPS","IRPC","ISPC","IS","OTHER"];
export async function POST(req:NextRequest){
 const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin","accountant"].includes(u.role))return NextResponse.json({error:"Sem permissões."},{status:403});
 try{
  const b=await req.json();
  if(b.action==="sync-periods"){
   const year=Number(b.year);if(!Number.isInteger(year)||year<2020||year>2100)return NextResponse.json({error:"Exercício inválido."},{status:400});
   const s=await createClient();const {data:profile,error:pe}=await s.from("tenant_tax_profiles").select("regime_code,confirmation_status,ispc_opt_in").eq("tenant_id",u.tenantId).maybeSingle();if(pe)throw pe;
   if(!profile||profile.confirmation_status!=="confirmed")return NextResponse.json({error:"Confirme o perfil fiscal antes de gerar o calendário."},{status:409});
   const items:any[]=[];
   if(profile.regime_code==="IVA_REGULAR"){for(let m=1;m<=12;m++){const period=String(m).padStart(2,"0");items.push({tenant_id:u.tenantId,tax_type:"IVA",obligation_code:"IVA-MODELO-A",title:"Declaração periódica de IVA — Modelo A",description:"Prazo ainda não validado. Confirmar no calendário fiscal e nos avisos oficiais da AT.",reference_period:year+"-"+period,due_date:null,due_month:null,deadline_precision:"unconfirmed",status:"pending",source:"profile_generated",created_by:u.id});}}
   else if(profile.regime_code==="ISPC"&&profile.ispc_opt_in){for(let q=1;q<=4;q++){items.push({tenant_id:u.tenantId,tax_type:"ISPC",obligation_code:"ISPC-MODELO-B",title:"Declaração trimestral de ISPC — Modelo B",description:"Prazo ainda não validado. Confirmar no calendário fiscal e nos avisos oficiais da AT.",reference_period:year+"-T"+q,due_date:null,due_month:null,deadline_precision:"unconfirmed",status:"pending",source:"profile_generated",created_by:u.id});}}
   else return NextResponse.json({error:"O regime fiscal confirmado não tem calendário automático configurado."},{status:409});
   const {data,error}=await s.from("tax_obligations").upsert(items,{onConflict:"tenant_id,obligation_code,reference_period",ignoreDuplicates:true}).select();if(error)throw error;
   await writeAudit(u,"tax_obligations.periods_generated","tax_obligation",u.tenantId,{year,created:data?.length||0,regime:profile.regime_code});
   return NextResponse.json({created:data?.length||0,periods:items.length,year,regime:profile.regime_code,message:"Períodos gerados sem datas presumidas. Confirme os prazos com a AT."});
  }
  const precision=b.deadlinePrecision||"date";const dueDate=b.dueDate||null;const dueMonth=b.dueMonth?Number(b.dueMonth):null;
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
