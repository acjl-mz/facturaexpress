alter table public.fiscal_documents
  add column if not exists converted_from_document_id uuid
  references public.fiscal_documents(id);

create unique index if not exists fiscal_documents_one_conversion_per_proforma
  on public.fiscal_documents (tenant_id, converted_from_document_id)
  where converted_from_document_id is not null;

create or replace function public.convert_proforma_to_invoice(
  p_source_document_id uuid,
  p_client_operation_id uuid default null
)
returns uuid
language plpgsql
set search_path = public, private
as $function$
declare
  v_tenant_id uuid;
  v_source public.fiscal_documents%rowtype;
  v_existing_id uuid;
  v_new_id uuid;
  v_lines jsonb;
  v_notes text;
begin
  if auth.uid() is null then
    raise exception 'Sessão inválida.';
  end if;

  select tenant_id into v_tenant_id
  from public.tenant_users
  where user_id = auth.uid()
  order by created_at
  limit 1;

  if v_tenant_id is null or not private.is_tenant_member(v_tenant_id) then
    raise exception 'Utilizador sem empresa activa.';
  end if;

  select * into v_source
  from public.fiscal_documents
  where id = p_source_document_id and tenant_id = v_tenant_id
  for update;

  if not found then
    raise exception 'Proforma não encontrada nesta empresa.';
  end if;
  if v_source.document_type <> 'PF' then
    raise exception 'A conversão está disponível apenas para proformas.';
  end if;
  if v_source.status not in ('draft','issued','paid','partially_paid') then
    raise exception 'O estado actual da proforma não permite conversão.';
  end if;

  select id into v_existing_id
  from public.fiscal_documents
  where tenant_id = v_tenant_id
    and converted_from_document_id = p_source_document_id
  limit 1;

  if v_existing_id is not null then
    return v_existing_id;
  end if;

  select jsonb_agg(jsonb_build_object(
    'item_id', item_id,
    'description', description,
    'quantity', quantity,
    'unit', unit,
    'unit_price', unit_price,
    'discount_amount', discount_amount,
    'tax_code', tax_code,
    'tax_eligibility_reference', tax_eligibility_reference,
    'tax_eligibility_category', tax_eligibility_category
  ) order by id)
  into v_lines
  from public.fiscal_document_lines
  where document_id = p_source_document_id;

  if v_lines is null or jsonb_array_length(v_lines) = 0 then
    raise exception 'A proforma não contém linhas para converter.';
  end if;

  v_notes := concat_ws(E'\n',
    nullif(trim(v_source.notes), ''),
    'Factura preparada a partir da proforma ' ||
      coalesce(v_source.document_number, v_source.id::text) ||
      ' (referência interna: ' || v_source.id::text || ').'
  );

  v_new_id := public.create_fiscal_document_draft(
    v_source.customer_id,
    'FT',
    v_source.due_date,
    v_notes,
    v_lines,
    coalesce(p_client_operation_id, gen_random_uuid())
  );

  update public.fiscal_documents
  set converted_from_document_id = p_source_document_id,
      invoice_template_id = v_source.invoice_template_id,
      updated_at = now()
  where id = v_new_id and tenant_id = v_tenant_id and status = 'draft';

  insert into public.document_events(tenant_id, document_id, event_type, actor_id, payload)
  values (v_tenant_id, v_new_id, 'proforma_converted', auth.uid(),
    jsonb_build_object('source_document_id', p_source_document_id));

  insert into public.audit_events(tenant_id, actor_user_id, event_type, target_type, target_id, details)
  values (v_tenant_id, auth.uid(), 'document.proforma_converted',
    'fiscal_document', v_new_id,
    jsonb_build_object('source_document_id', p_source_document_id));

  return v_new_id;
end;
$function$;

revoke all on function public.convert_proforma_to_invoice(uuid, uuid) from public;
grant execute on function public.convert_proforma_to_invoice(uuid, uuid) to authenticated;
