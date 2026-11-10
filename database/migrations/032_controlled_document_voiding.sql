-- 032: anulação controlada de documentos emitidos sem apagar o original.
begin;
create or replace function private.prevent_issued_document_mutation()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $function$
declare v_reason text;v_role text;
begin
 if tg_table_name='fiscal_documents' then
  if tg_op='DELETE' then
   if old.status<>'draft' then raise exception 'Documentos fiscais emitidos não podem ser eliminados.';end if;
  elsif old.status in ('issued','partially_paid') then
   if new.status='voided' then
    v_reason:=nullif(trim(current_setting('app.fiscal_void_reason',true)),'');
    if v_reason is null or (to_jsonb(new)-'status'-'updated_at') is distinct from (to_jsonb(old)-'status'-'updated_at') then raise exception 'Anulação bloqueada: utilize o procedimento próprio com fundamento.';end if;
    select role into v_role from public.tenant_users where user_id=auth.uid() and tenant_id=old.tenant_id order by created_at limit 1;
    if auth.uid() is null or v_role not in ('owner','admin') then raise exception 'Apenas proprietário ou administrador pode anular documentos.';end if;
    if exists(select 1 from public.customer_payments p where p.tenant_id=old.tenant_id and p.document_id=old.id) then raise exception 'Documento com recebimentos: regularize os pagamentos através de rectificação e devolução antes da anulação.';end if;
   elsif (to_jsonb(new)-'status'-'updated_at') is distinct from (to_jsonb(old)-'status'-'updated_at') or not (old.status='issued' and new.status in ('issued','partially_paid','paid') or old.status='partially_paid' and new.status in ('partially_paid','paid')) then
    raise exception 'Os dados fiscais do documento são imutáveis. Apenas o estado de liquidação ou anulação autorizada pode ser actualizado.';
   end if;
  elsif old.status in ('paid','voided') then raise exception 'Documentos fiscais liquidados ou anulados são imutáveis.';
  end if;
 else
  if exists(select 1 from public.fiscal_documents d where d.id=old.document_id and d.status<>'draft') then raise exception 'As linhas de documentos emitidos são imutáveis.';end if;
 end if;
 if tg_op='DELETE' then return old;else return new;end if;
end;$function$;
create or replace function public.void_fiscal_document(p_document_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $function$
declare v_user uuid:=auth.uid();v_tenant uuid;v_role text;v_doc public.fiscal_documents%rowtype;v_reason text:=nullif(trim(p_reason),'');
begin
 if v_user is null then raise exception 'Sessão inválida.';end if;
 if v_reason is null or length(v_reason)<10 or length(v_reason)>1000 then raise exception 'O fundamento da anulação deve ter entre 10 e 1000 caracteres.';end if;
 select tu.tenant_id,tu.role into v_tenant,v_role from public.tenant_users tu join public.tenants t on t.id=tu.tenant_id where tu.user_id=v_user and t.status='active' order by tu.created_at limit 1;
 if v_tenant is null or not private.is_tenant_member(v_tenant) then raise exception 'Utilizador sem empresa activa.';end if;
 if v_role not in ('owner','admin') then raise exception 'Apenas proprietário ou administrador pode anular documentos.';end if;
 select * into v_doc from public.fiscal_documents where id=p_document_id and tenant_id=v_tenant for update;
 if not found then raise exception 'Documento não encontrado nesta empresa.';end if;
 if v_doc.status<>'issued' then raise exception 'Só é possível anular documentos emitidos sem recebimentos. Documentos pagos, parcialmente pagos ou já anulados exigem tratamento específico.';end if;
 if exists(select 1 from public.customer_payments where tenant_id=v_tenant and document_id=p_document_id) then raise exception 'O documento tem recebimentos associados. Não pode ser anulado por este procedimento.';end if;
 if exists(select 1 from public.fiscal_documents where tenant_id=v_tenant and corrects_document_id=p_document_id and status in ('issued','paid','partially_paid')) then raise exception 'O documento possui notas rectificativas emitidas. Resolva primeiro a cadeia documental.';end if;
 perform set_config('app.fiscal_void_reason',v_reason,true);
 update public.fiscal_documents set status='voided',updated_at=now() where id=p_document_id and tenant_id=v_tenant and status='issued';
 insert into public.document_events(tenant_id,document_id,event_type,actor_id,payload) values(v_tenant,p_document_id,'fiscal_document_voided',v_user,jsonb_build_object('reason',v_reason,'document_number',v_doc.document_number,'voided_at',now()));
 insert into public.audit_events(tenant_id,actor_user_id,event_type,target_type,target_id,details) values(v_tenant,v_user,'document.fiscal_voided','fiscal_document',p_document_id,jsonb_build_object('reason',v_reason,'document_number',v_doc.document_number));
 return jsonb_build_object('id',p_document_id,'status','voided','document_number',v_doc.document_number);
end;$function$;
revoke all on function public.void_fiscal_document(uuid,text) from public,anon;
grant execute on function public.void_fiscal_document(uuid,text) to authenticated;
commit;