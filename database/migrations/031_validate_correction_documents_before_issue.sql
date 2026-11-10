create or replace function private.validate_fiscal_correction_before_issue()
returns trigger language plpgsql set search_path=public,private,pg_temp as $$
declare v_original public.fiscal_documents%rowtype; v_original_number text;
begin
 if new.status='issued' and old.status='draft' and new.document_type in ('NC','ND') then
  if new.corrects_document_id is null or nullif(trim(new.correction_reason),'') is null then
   raise exception 'Emissão bloqueada: nota de crédito/débito exige factura original e fundamento.';
  end if;
  select * into v_original from public.fiscal_documents
   where id=new.corrects_document_id and tenant_id=new.tenant_id for update;
  if not found or v_original.document_type<>'FT' or v_original.status not in ('issued','paid','partially_paid') then
   raise exception 'Emissão bloqueada: factura original inválida ou não emitida.';
  end if;
  if new.document_type='NC' and new.grand_total>v_original.grand_total then
   raise exception 'Emissão bloqueada: o valor da nota de crédito não pode exceder o valor total da factura original.';
  end if;
  if new.document_type='ND' and new.grand_total<=0 then
   raise exception 'Emissão bloqueada: a nota de débito deve conter um valor positivo.';
  end if;
  v_original_number:=v_original.document_number;
  new.issued_snapshot:=coalesce(new.issued_snapshot,'{}'::jsonb)||jsonb_build_object(
   'correction',jsonb_build_object('original_document_id',v_original.id,'original_document_number',v_original_number,'original_issue_date',v_original.issue_date,'correction_reason',new.correction_reason,'correction_type',new.document_type)
  );
 end if;
 return new;
end;$$;
drop trigger if exists fiscal_correction_issue_guard on public.fiscal_documents;
create trigger fiscal_correction_issue_guard before update of status on public.fiscal_documents
for each row execute function private.validate_fiscal_correction_before_issue();