UPDATE public.tax_rules
SET valid_from=DATE '2023-01-01',
    legal_reference='Lei n.º 22/2022, de 28 de Dezembro (redução da taxa geral para 16%), mantida após Lei n.º 10/2025, de 29 de Dezembro',
    source_document='Lei n.º 22/2022 e Lei n.º 10/2025',
    source_article='Artigo 17 do Código do IVA'
WHERE tenant_id IS NULL AND code='IVA_STD_16';