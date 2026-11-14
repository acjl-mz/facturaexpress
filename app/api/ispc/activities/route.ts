import {NextResponse} from "next/server";
import {getSession} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
export async function GET(){
 const u=await getSession();if(!u)return NextResponse.json({error:"Não autenticado."},{status:401});
 const s=await createClient();
 const {data,error}=await s.from("ispc_activity_catalog").select("activity_code,activity_name,activity_category,legal_examples,legal_reference,valid_from,valid_to").eq("active",true).order("activity_category").order("activity_name");
 if(error)return NextResponse.json({error:"Não foi possível consultar o catálogo de actividades ISPC."},{status:500});
 const {data:rates,error:re}=await s.from("ispc_rate_schedule").select("activity_category,code,rate,min_annual_turnover,max_annual_turnover,valid_from,valid_to").eq("active",true).order("rate");
 if(re)return NextResponse.json({error:"Não foi possível consultar as taxas ISPC."},{status:500});
 return NextResponse.json({activities:data||[],rates:rates||[]});
}