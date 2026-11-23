import {NextResponse} from "next/server";
import packageInfo from "../../../package.json";
import {getSession} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";

export async function GET(){
 const user=await getSession();
 if(!user)return NextResponse.json({error:"Não autenticado."},{status:401});
 if(!["owner","admin"].includes(user.role))return NextResponse.json({error:"Sem permissões."},{status:403});
 const db=await createClient();
 const [{data:company,error:companyError},{data:authorization,error:authorizationError}]=await Promise.all([
  db.from("tenants").select("legal_name,nuit,address,email,phone").eq("id",user.tenantId).single(),
  db.from("tenant_fiscal_authorizations").select("*").eq("tenant_id",user.tenantId).maybeSingle()
 ]);
 if(companyError||authorizationError)return NextResponse.json({error:"Não foi possível carregar a identificação do software."},{status:500});
 return NextResponse.json({
  software:{name:"FacturaExpress",version:packageInfo.version,build:process.env.VERCEL_GIT_COMMIT_SHA||process.env.GIT_COMMIT_SHA||"não disponibilizado",deployment:process.env.VERCEL_ENV||"ambiente não identificado",platform:"Web — Next.js / Vercel",database:"Supabase PostgreSQL"},
  producer:{legalName:null,nuit:null,address:null,contact:null,notice:"Os dados legais do produtor devem ser preenchidos e comprovados no dossier de certificação."},
  tenant:company,
  authorization:authorization?{...authorization,version_matches:authorization.approved_software_version===packageInfo.version,status:authorization.status==="approved"&&authorization.approved_software_version!==packageInfo.version?"version_mismatch":authorization.status}:{status:"not_authorized",authorization_reference:null,approved_software_version:null,version_matches:false,notice:"Não existe autorização da AT registada para esta empresa."}
 });
}
