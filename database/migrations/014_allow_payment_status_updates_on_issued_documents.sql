CREATE OR REPLACE FUNCTION private.prevent_issued_document_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,private,pg_temp AS $$
BEGIN
 IF TG_TABLE_NAME='fiscal_documents' THEN
  IF TG_OP='DELETE' THEN
   IF OLD.status<>'draft' THEN RAISE EXCEPTION 'Documentos fiscais emitidos não podem ser eliminados.'; END IF;
  ELSIF OLD.status IN ('issued','partially_paid') THEN
   IF (to_jsonb(NEW)-'status'-'updated_at') IS DISTINCT FROM (to_jsonb(OLD)-'status'-'updated_at')
      OR NOT ((OLD.status='issued' AND NEW.status IN ('issued','partially_paid','paid'))
          OR (OLD.status='partially_paid' AND NEW.status IN ('partially_paid','paid'))) THEN
    RAISE EXCEPTION 'Os dados fiscais do documento são imutáveis. Apenas o estado de liquidação pode ser actualizado.';
   END IF;
  ELSIF OLD.status IN ('paid','voided') THEN
   RAISE EXCEPTION 'Documentos fiscais liquidados ou anulados são imutáveis.';
  END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM public.fiscal_documents d WHERE d.id=OLD.document_id AND d.status<>'draft') THEN
   RAISE EXCEPTION 'As linhas de documentos emitidos são imutáveis.';
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;$$;