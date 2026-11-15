# Auditoria de integração funcional — FacturaExpress

Data da auditoria: 15 de Novembro de 2026  
Repositório: `acjl-mz/facturaexpress`  
Branch: `main`  
Backend: Supabase (`krxdsribwxjouqmoerws`)

## Conclusão executiva

O produto tem um núcleo real de preparação documental, regras fiscais no Supabase, gestão de clientes/artigos, pagamentos, correcções e controlo de séries. Contudo, ainda não está fechado como produto de facturação pronto para produção. Existem funcionalidades auxiliares que estão apenas parcialmente ligadas ao ciclo documental, e faltam testes integrados, arquivo PDF, integração dos recebimentos com tesouraria e validação formal dos requisitos da AT.

A auditoria distinguiu presença de páginas/APIs de integração funcional. Um módulo só é considerado integrado quando consome ou produz dados coerentes com o documento, respeita o tenant e tem transições verificáveis.

## Matriz de integração

| Funcionalidade | Ligação ao ciclo de facturação | Estado observado |
|---|---|---|
| Clientes | Cliente seleccionado no formulário; ficha e NUIT persistidos; histórico e extracto consultáveis | Integrado no núcleo |
| Produtos e serviços | Artigos seleccionados nas linhas; descrição, unidade, preço e classificação copiados para o snapshot da linha | Integrado no núcleo |
| Documentos e rascunhos | Criação transaccional no Supabase; cálculos e linhas gravados pelo RPC; consulta, edição e duplicação de rascunhos | Integrado, requer testes E2E |
| Séries documentais | A função de emissão bloqueia sem autorização, selecciona série activa e reserva número transaccionalmente | Integrado, condicionado à autorização |
| Templates | Template seleccionado no rascunho e carregado no detalhe documental para apresentação | Integrado na apresentação; editor e layouts precisam de testes de impressão |
| IVA | Linhas usam regras aprovadas e vigentes; apuramento IVA consulta documentos emitidos | Parcialmente integrado; créditos suportados são introduzidos pelo utilizador e carecem de prova |
| ISPC | Perfil, catálogo de actividades e prévias trimestrais existem; cálculo SQL consulta o perfil e tabela de taxas | Parcial; volume de negócios da prévia ainda é fornecido pelo utilizador, não reconciliado automaticamente com documentos |
| Notas de crédito/débito e anulação | Fluxos próprios com ligação ao original, razão e actualização do saldo | Integrado no ciclo, requer testes de cenários e sequência |
| Pagamentos | Apenas documentos emitidos; pagamento parcial/total, idempotência e actualização de estado | Integrado ao documento |
| Factura-Recibo | Emissão e pagamento integral numa transacção única | Integrado, condicionado à autorização |
| Tesouraria | Contas e movimentos têm registo separado; recebimentos de clientes não criam automaticamente movimento de tesouraria nem associam conta de destino | **Não integrado suficientemente** |
| Reconciliação bancária | Linhas importadas são reconciliadas com movimentos de tesouraria | Parcial; não existe associação automática do recebimento ao movimento bancário |
| Fornecedores e facturas de compra | Registo independente para informação de compras/IVA suportado | Módulo auxiliar; não participa na emissão de vendas |
| Relatórios | Agregam documentos emitidos, pagamentos, tesouraria e saldos | Parcial; requer reconciliação das fontes e testes de totais |
| Calendário e obrigações fiscais | Registos de obrigações por empresa e período | Auxiliar; não bloqueia nem valida a emissão |
| Arquivo PDF | Impressão/exportação usa a caixa de diálogo do navegador; não existe confirmação de PDF final arquivado em Storage | **Em falta** |
| Envio por e-mail | Abre cliente de e-mail via `mailto:`; não anexa o PDF automaticamente | Parcial; texto corrigido para informar que o anexo tem de ser adicionado manualmente |
| Auditoria | Eventos documentais e eventos de auditoria são gravados em operações críticas | Parcial; falhas de gravação de auditoria não devem ser silenciosas em operações críticas |
| Offline/sincronização | Tabelas de operações de sincronização e estado pendente existem; fluxo local/offline não está concluído | Fase posterior |

## Constatações técnicas

1. O dashboard é uma implementação própria e não usa o mesmo shell das páginas internas. A navegação fiscal tem de permanecer consistente nos dois contextos.
2. O formulário de novo documento calcula uma prévia no cliente, mas o valor persistido é recalculado pelo RPC `create_fiscal_document_draft` no Supabase. O cálculo do servidor é a fonte de verdade.
3. A emissão definitiva está bloqueada pela ausência de autorização/certificação registada para a versão exacta do software. Esta protecção deve permanecer.
4. O endpoint genérico `/api/tax/calculate` aceita taxas fornecidas no pedido e devolve apenas uma simulação; não é usado como fonte de verdade do documento. A emissão usa as regras fiscais aprovadas no Supabase.
5. O RPC `register_customer_payment` era SECURITY DEFINER e não validava o papel do membro, embora a API validasse. Foi corrigido no Supabase e registado em `database/migrations/037_payment_rpc_role_guard.sql`.
6. O Supabase Advisor continua a assinalar funções SECURITY DEFINER expostas a utilizadores autenticados. Essas funções são intencionais em operações transaccionais, mas devem manter validação interna de utilizador, tenant e papel. A revisão de cada função é obrigatória.
7. O Advisor também indica protecção contra palavras-passe comprometidas desactivada e um índice em falta em `treasury_transactions.created_by`.
8. A ligação de e-mail não anexava ficheiro apesar do texto afirmar que existia um anexo. O texto foi corrigido; envio com anexo automático continua pendente.

## Próxima sequência para fechar o produto

### Bulk A — Fechar documento e impressão
- Gerar PDF de forma determinística e associá-lo ao documento.
- Guardar PDF final em Supabase Storage privado, com caminho por tenant/documento e política RLS/Storage.
- Criar versão/sha256, data de geração e estado de arquivo.
- Reimprimir sempre a partir do snapshot emitido, sem recalcular valores nem alterar o original.
- Corrigir e testar A4 e térmico 80 mm, múltiplas páginas, rodapé, totais e linhas longas.
- Só disponibilizar arquivo fiscal final para documentos cujo estado e autorização permitam.

### Bulk B — Ligar pagamentos à tesouraria
- No registo de pagamento, exigir conta/caixa de destino quando aplicável.
- Criar o movimento de entrada na mesma transacção do pagamento, com referência cruzada.
- Evitar duplicação por chave idempotente.
- Fazer com que a reconciliação bancária encontre os recebimentos associados.
- Tratar pagamentos em numerário, banco, POS e carteira móvel sem inventar uma conta quando não foi configurada.

### Bulk C — Fechar apuramentos derivados dos documentos
- Ligar prévias ISPC ao volume de negócios documental, respeitando a definição legal de volume de negócios e eventuais operações não documentadas.
- Manter ajustes manuais identificados, justificados e auditados, sem substituir a origem documental.
- Recalcular mapas IVA a partir dos documentos emitidos e registos de compras, com rastreio por documento/linha.
- Distinguir cálculos de apoio de declarações submetidas à AT.

### Bulk D — Qualidade e segurança
- Testes E2E: rascunho → edição → validação → emissão autorizada → PDF/ impressão → pagamento parcial → pagamento total → nota de crédito/débito → anulação.
- Testes multiempresa e por papel (owner/admin/issuer/accountant/viewer).
- Testes de concorrência e idempotência para séries e pagamentos.
- Verificação de todas as políticas RLS e funções SECURITY DEFINER.
- Activar protecção contra palavras-passe comprometidas no Supabase Auth.
- Corrigir índice de chave estrangeira em falta e rever índices após dados reais.
- Build, lint, typecheck e testes automatizados antes de cada release.

### Bulk E — Conformidade e lançamento
- Obter da AT a especificação aplicável de facturação electrónica, SAF-T (Moz), comunicação de dados e certificação/autorização.
- Validar formalmente modelos, menções, séries, numeração, arquivo, assinatura e procedimento de rectificação/anulação.
- Não desbloquear emissão comercial antes de existir autorização aplicável documentada.

## Regra de conclusão

O FacturaExpress só deve ser considerado fechado quando o fluxo de ponta a ponta estiver ligado, os documentos finais forem arquiváveis e reimprimíveis, os recebimentos estiverem conciliados com tesouraria, os relatórios forem derivados de fontes rastreáveis, os testes passarem e os bloqueios legais estiverem formalmente resolvidos.
