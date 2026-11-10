-- Lote 30: correcções de notas de débito e preparação para impressão.
-- Nota de débito começa com linha de ajustamento vazia: nunca replica automaticamente
-- o valor integral da factura original.
create or replace function public.create_fiscal_correction_draft(
 p_original_document_id uuid,p_correction_type text,p_reason text
) returns uuid language plpgsql set search_path=public,private as $$
declare
 v_user uuid:=auth.uid();v_tenant uuid;v_role text;v_original public.fiscal_documents%rowtype;v_new_id uuid;v_reason text:=nullif(trim(p_reason),'');v_count integer;
begin
 if v_user is null then raise exception 'Sessão inválida.';end if;
 if p_correction_type not in ('NC','ND') then raise exception 'Tipo de documento rectificativo inválido.';end if;
 if v_reason is null or length(v_reason)<8 or length(v_reason)>1000 then raise exception 'Indique um fundamento com pelo menos 8 caracteres e até 1000 caracteres.';end if;
 select tenant_id,role into v_tenant,v_role from public.tenant_users where user_id=v_user order by created_at limit 1;
 if v_tenant is null or not private.is_tenant_member(v_tenant) then raise exception 'Utilizador sem empresa activa.';end if;
 if v_role not in ('owner','admin','issuer','accountant') then raise exception 'Sem permissão para preparar documentos rectificativos.';end if;
 select * into v_original from public.fiscal_documents where id=p_original_document_id and tenant_id=v_tenant for update;
 if not found then raise exception 'Documento original não encontrado nesta empresa.';end if;
 if v_original.status not in ('issued','paid','partially_paid') or v_original.document_type<>'FT' then raise exception 'Só é possível preparar rectificação de factura emitida. Facturas-recibo, rascunhos e documentos anulados não são aceites neste fluxo.';end if;
 select count(*) into v_count from public.fiscal_document_lines where document_id=v_original.id;
 if v_count=0 then raise exception 'O documento original não contém linhas.';end if;
 insert into public.fiscal_documents(tenant_id,customer_id,document_type,status,due_date,currency,notes,correction_reason,corrects_document_id,invoice_template_id,created_by)
 values(v_tenant,v_original.customer_id,p_correction_type,'draft',null,v_original.currency,'Documento rectificativo de '||coalesce(v_original.document_number,'documento sem número')||'. '||v_reason,v_reason,v_original.id,v_original.invoice_template_id,v_user) returning id into v_new_id;
 if p_correction_type='NC' then
  insert into public.fiscal_document_lines(document_id,item_id,description,quantity,unit,unit_price,discount_amount,tax_code,tax_rate,tax_eligibility_reference,tax_eligibility_category,taxable_amount,tax_amount,line_total)
  select v_new_id,item_id,description,quantity,unit,unit_price,discount_amount,tax_code,tax_rate,tax_eligibility_reference,tax_eligibility_category,taxable_amount,tax_amount,line_total from public.fiscal_document_lines where document_id=v_original.id order by id;
  update public.fiscal_documents set subtotal=v_original.subtotal,discount_total=v_original.discount_total,tax_total=v_original.tax_total,withholding_total=v_original.withholding_total,grand_total=v_original.grand_total,updated_at=now() where id=v_new_id and tenant_id=v_tenant;
 else
  insert into public.fiscal_document_lines(document_id,description,quantity,unit,unit_price,discount_amount)
  values(v_new_id,'Ajustamento adicional — completar descrição e enquadramento',1,'UN',0,0);
 end if;
 insert into public.document_events(tenant_id,document_id,event_type,actor_id,payload) values
 (v_tenant,v_original.id,'correction_draft_created',v_user,jsonb_build_object('correction_document_id',v_new_id,'correction_type',p_correction_type,'reason',v_reason)),
 (v_tenant,v_new_id,'correction_draft_created',v_user,jsonb_build_object('original_document_id',v_original.id,'original_document_number',v_original.document_number,'correction_type',p_correction_type,'reason',v_reason));
 insert into public.audit_events(tenant_id,actor_user_id,event_type,target_type,target_id,details) values(v_tenant,v_user,'document.correction_draft_created','fiscal_document',v_new_id,jsonb_build_object('original_document_id',v_original.id,'correction_type',p_correction_type,'reason',v_reason));
 return v_new_id;
end;$$;
revoke all on function public.create_fiscal_correction_draft(uuid,text,text) from public,anon;
grant execute on function public.create_fiscal_correction_draft(uuid,text,text) to authenticated;