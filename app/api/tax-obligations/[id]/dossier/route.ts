import {NextRequest,NextResponse} from "next/server";
import {getSession,writeAudit} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";

const canWrite=(role:string)=>["owner","admin","accountant"].includes(role);
export async function GET(_req:NextRequest,{params}:{params:Promise<{id:string}>}){
 const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});
 const {id}=await params;const s=await createClient();
 const {data:obligation,error}=await s.from("tax_obligations").select("*").eq("id",id).eq("tenant_id",u.tenantId).single();
 if(error||!obligation)return NextResponse.json({error:"Obrigação não encontrada."},{status:404});
 const {data:events,error:ee}=await s.from("tax_obligation_events").select("*").eq("obligation_id",id).eq("tenant_id",u.tenantId).order("event_date",{ascending:false});
 if(ee)return NextResponse.json({error:ee.message},{status:500});
 let evidenceUrl:string|null=null;
 if(obligation.payment_proof_path){const {data}=await s.storage.from("tax-obligation-evidence").createSignedUrl(obligation.payment_proof_path,300);evidenceUrl=data?.signedUrl||null;}
 let sourceRecord:any=null;
 if(obligation.tax_type==="IVA"&&/^\d{4}-\d{2}$/.test(obligation.reference_period)){
  const [y,m]=obligation.reference_period.split("-").map(Number);
  const {data}=await s.from("tax_return_periods").select("*").eq("tenant_id",u.tenantId).eq("tax_type","IVA").eq("tax_year",y).eq("tax_period",m).maybeSingle();sourceRecord=data;
 }else if(obligation.tax_type==="ISPC"&&/^\d{4}-T[1-4]$/.test(obligation.reference_period)){
  const y=Number(obligation.reference_period.slice(0,4)),q=Number(obligation.reference_period.slice(-1));
  const {data}=await s.from("ispc_quarterly_assessments").select("*").eq("tenant_id",u.tenantId).eq("tax_year",y).eq("quarter",q).maybeSingle();sourceRecord=data;
 }
 return NextResponse.json({obligation,events:events||[],evidenceUrl,sourceRecord});
}
export async function POST(req:NextRequest,{params}:{params:Promise<{id:string}>}){
 const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!canWrite(u.role))return NextResponse.json({error:"Sem permissões para actualizar o dossier fiscal."},{status:403});
 const {id}=await params;const s=await createClient();
 const {data:obligation,error:oe}=await s.from("tax_obligations").select("id,tax_type,reference_period,status,prepared_at,reviewed_at,submission_reference").eq("id",id).eq("tenant_id",u.tenantId).single();
 if(oe||!obligation)return NextResponse.json({error:"Obrigação não encontrada."},{status:404});
 try{
  const isMultipart=req.headers.get("content-type")?.includes("multipart/form-data");
  if(isMultipart){
   const fd=await req.formData();const file=fd.get("file");
   if(!(file instanceof File)||file.size===0)return NextResponse.json({error:"Seleccione um comprovativo."},{status:400});
   if(file.size>10*1024*1024)return NextResponse.json({error:"O ficheiro excede 10 MB."},{status:400});
   if(!["application/pdf","image/jpeg","image/png"].includes(file.type))return NextResponse.json({error:"Formato não permitido. Use PDF, JPG ou PNG."},{status:400});
   const ext=file.type==="application/pdf"?"pdf":file.type==="image/png"?"png":"jpg";
   const path=u.tenantId+"/"+id+"/"+Date.now()+"."+ext;
   const {error:up}=await s.storage.from("tax-obligation-evidence").upload(path,file,{contentType:file.type,upsert:false});
   if(up)throw up;
   const {error:upd}=await s.from("tax_obligations").update({payment_proof_path:path,updated_at:new Date().toISOString()}).eq("id",id).eq("tenant_id",u.tenantId);
   if(upd)throw upd;
   const {error:ev}=await s.from("tax_obligation_events").insert({tenant_id:u.tenantId,obligation_id:id,event_type:"evidence_uploaded",actor_user_id:u.id,reference:path,notes:"Comprovativo de pagamento carregado."});
   if(ev)throw ev;
   await writeAudit(u,"tax_obligation.evidence_uploaded","tax_obligation",id);
   return NextResponse.json({path,message:"Comprovativo guardado."},{status:201});
  }
  const b=await req.json();const now=new Date().toISOString();const patch:any={updated_at:now},event:any={tenant_id:u.tenantId,obligation_id:id,actor_user_id:u.id,event_date:now,metadata:{}};
  if(b.action==="prepare"){
   let sourceExists=false;
   if(obligation.tax_type==="IVA"&&/^\d{4}-\d{2}$/.test(obligation.reference_period)){
    const [y,m]=obligation.reference_period.split("-").map(Number);
    const {data}=await s.from("tax_return_periods").select("id").eq("tenant_id",u.tenantId).eq("tax_type","IVA").eq("tax_year",y).eq("tax_period",m).maybeSingle();sourceExists=!!data;
   }else if(obligation.tax_type==="ISPC"&&/^\d{4}-T[1-4]$/.test(obligation.reference_period)){
    const y=Number(obligation.reference_period.slice(0,4)),q=Number(obligation.reference_period.slice(-1));
    const {data}=await s.from("ispc_quarterly_assessments").select("id").eq("tenant_id",u.tenantId).eq("tax_year",y).eq("quarter",q).maybeSingle();sourceExists=!!data;
   }
   if(!sourceExists)return NextResponse.json({error:"Prepare primeiro o apuramento no módulo fiscal correspondente a este período."},{status:409});
   patch.status="in_progress";patch.prepared_at=now;event.event_type="prepared";event.notes=String(b.notes||"Apuramento preparado.");
  }else if(b.action==="review"){
   if(!obligation.prepared_at)return NextResponse.json({error:"Registe primeiro o apuramento preparado."},{status:409});
   if(!String(b.notes||"").trim())return NextResponse.json({error:"Registe uma nota de revisão ou validação."},{status:400});
   patch.reviewed_at=now;patch.reviewed_by=u.id;event.event_type="reviewed";event.notes=String(b.notes).trim();
  }else if(b.action==="submit"){
   if(!obligation.reviewed_at)return NextResponse.json({error:"A declaração deve ser revista e validada antes de registar a submissão."},{status:409});
   const ref=String(b.reference||"").trim(),date=String(b.date||"");
   if(!ref||!/^\d{4}-\d{2}-\d{2}$/.test(date))return NextResponse.json({error:"Indique a referência e a data efectiva de submissão."},{status:400});
   patch.status="filed";patch.filed_at=new Date(date+"T12:00:00").toISOString();patch.submitted_at=patch.filed_at;patch.submission_reference=ref;
   event.event_type="submission_recorded";event.reference=ref;event.notes=String(b.notes||"Submissão registada pelo utilizador.");
  }else if(b.action==="payment"){
   if(obligation.status!=="filed"||!obligation.submission_reference)return NextResponse.json({error:"Registe a submissão da declaração antes do pagamento."},{status:409});
   const ref=String(b.reference||"").trim(),date=String(b.date||""),amount=Number(b.amount);
   if(!ref||!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isFinite(amount)||amount<=0)return NextResponse.json({error:"Indique referência oficial, data e valor pago."},{status:400});
   const {data:current}=await s.from("tax_obligations").select("payment_proof_path").eq("id",id).eq("tenant_id",u.tenantId).single();
   if(!current?.payment_proof_path)return NextResponse.json({error:"Carregue primeiro o comprovativo de pagamento."},{status:409});
   patch.status="paid";patch.paid_at=new Date(date+"T12:00:00").toISOString();patch.payment_recorded_at=now;patch.payment_reference=ref;patch.payment_date=date;patch.payment_amount=amount;
   event.event_type="payment_recorded";event.reference=ref;event.notes=String(b.notes||"Pagamento registado com comprovativo.");
   event.metadata={amount,date,currency:"MZN"};
  }else if(b.action==="note"){
   const note=String(b.notes||"").trim();if(!note)return NextResponse.json({error:"Escreva a nota a guardar."},{status:400});
   event.event_type="note";event.notes=note;
  }else return NextResponse.json({error:"Acção desconhecida."},{status:400});
  if(Object.keys(patch).length>1){const {error}=await s.from("tax_obligations").update(patch).eq("id",id).eq("tenant_id",u.tenantId);if(error)throw error;}
  const {error:ee}=await s.from("tax_obligation_events").insert(event);if(ee)throw ee;
  await writeAudit(u,"tax_obligation."+b.action,"tax_obligation",id,{reference:event.reference||null});
  return NextResponse.json({message:"Dossier fiscal actualizado."});
 }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"Não foi possível actualizar o dossier."},{status:400});}
}
