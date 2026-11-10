-- 034: fail closed when checking the role inside the immutability trigger.
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
    if auth.uid() is null or coalesce(v_role,'') not in ('owner','admin') then raise exception 'Apenas proprietário ou administrador pode anular documentos.';end if;
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