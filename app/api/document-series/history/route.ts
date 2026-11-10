import {NextResponse} from "next/server";
import {getSession} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";

export async function GET(){
 const u=await getSession();
 if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin","accountant","issuer"].includes(u.role))
  return NextResponse.json({error:"Sem permissão para consultar o histórico."},{status:403});
 const s=await createClient();
 const {data,error}=await s.from("audit_events")
  .select("id,event_type,target_id,details,created_at")
  .eq("tenant_id",u.tenantId)
  .eq("target_type","document_series")
  .order("created_at",{ascending:false})
  .limit(100);
 if(error){console.error("Document series history",error);return NextResponse.json({error:"Não foi possível carregar o histórico das séries."},{status:500});}
 return NextResponse.json({events:data??[]});
}
