# Mapeamento do FacturaExpress e preparação para validação pela AT
**Data de referência:** 15 de Novembro de 2026  
**Repositório:** `acjl-mz/facturaexpress` — branch `main`  
**Backend:** Supabase (PostgreSQL, Auth, Data API, RLS e Storage)  
**Alojamento:** Vercel  
**Âmbito:** facturação, documentos fiscais, apoio à fiscalidade e evidência de cumprimento em Moçambique.

> Este documento é uma auditoria técnico-funcional e uma matriz de preparação. Não é parecer jurídico, certificação, homologação ou confirmação de aceitação pela Autoridade Tributária (AT). Qualquer regra fiscal deve ser confirmada no diploma integral vigente e, quando aplicável, por instrução escrita da AT.

## 1. Conclusão executiva

O FacturaExpress já tem uma base funcional relevante: organizações multiempresa, perfis fiscais, clientes e artigos, rascunhos documentais, séries, motor de cálculo no Supabase, fluxos de emissão condicionados, pagamentos, correcções, modelos de impressão, módulos de apoio IVA/ISPC, retenções e controlo documental das obrigações.

**Não está, contudo, pronto para emissão fiscal comercial nem para ser apresentado como software certificado/autorizado pela AT.** A própria função transaccional de emissão bloqueia a emissão quando não existe autorização aplicável para a versão exacta do software. Na consulta efectuada em 15/11/2026, a tabela `tenant_fiscal_authorizations` não tinha registos. O bloqueio é correcto e deve permanecer até existir evidência formal.

Também não foi encontrada no repositório implementação de exportação SAF-T (Moz), pacote de comunicação mensal de dados de facturação conforme esquema AT, integração de submissão no Portal do Contribuinte, assinatura/selagem fiscal reconhecida, nem arquivo final de PDF imutável em Storage ligado ao documento emitido.

**Resultado:** ambiente de preparação e protótipo funcional; não declarar “certificado”, “homologado”, “autorizado” ou “pronto para uso fiscal” sem decisão formal da AT e testes de aceitação.

## 2. Mapa funcional actual

### 2.1 Acesso, organização e segurança
- Autenticação através de Supabase Auth, com sessões geridas no servidor.
- Multiempresa por `tenant_id`; utilizadores associados a empresas e papéis.
- Papéis usados na aplicação: `owner`, `admin`, `issuer`, `accountant`, `manager` e `viewer` (a matriz exacta de cada operação deve ser uniformizada).
- Perfil da empresa: denominação, nome comercial, NUIT, endereço e regime fiscal.
- Perfil fiscal confirmado antes de permitir certas páginas/actuações.
- RLS activa nas 30 tabelas públicas consultadas; políticas aplicam pertença ao tenant em grande parte das tabelas.
- Storage tem buckets privados `fiscal-documents` e `tax-obligation-evidence`.

**Estado:** fundação existente. Requer testes de isolamento entre empresas, matriz de papéis completa, revisão das funções SECURITY DEFINER e reforço de autenticação.

### 2.2 Navegação e páginas identificadas
Páginas presentes no repositório:
- Visão geral: `/`
- Empresa: `/company`
- Documentos: `/documents`, `/documents/new`, `/documents/[id]`, `/documents/[id]/edit`
- Séries: `/series`
- Clientes: `/customers`, `/customers/[id]`
- Produtos e serviços: `/items`
- Pagamentos: `/payments`, `/payments/receipt/[id]`
- Modelos de impressão: `/templates`
- Fiscalidade: `/tax`, `/tax-returns/iva`, `/ispc`, `/ispc/model-b`, `/tax-withholdings`, `/tax-obligations`, `/tax-obligations/[id]`, `/tax-archive`, `/tax-reports`
- Administração: `/users`
- Rotas auxiliares/legadas: `/treasury`, `/reconciliation`, `/suppliers`, `/reports`.

**Inconsistência de navegação a resolver:** o `AppShell` não envolve a página inicial `/`; a dashboard tem estrutura própria. As rotas `/treasury`, `/reconciliation`, `/suppliers` e `/reports` são redireccionadas para a página inicial. A navegação fiscal interna usa o shell, enquanto o dashboard não. Isto pode produzir experiências e acessos diferentes. Consolidar um único shell persistente e manter apenas as entradas funcionais aprovadas pelo produto.

### 2.3 Ciclo de facturação
- Criação e edição de rascunhos.
- Tipos identificados no formulário/listagem: FT, FR, PF, NC e ND.
- Linhas com descrição, quantidade, unidade, preço, desconto, código/taxa fiscal e fundamento de elegibilidade.
- Cálculo definitivo no servidor/Supabase; o cálculo no browser é apenas pré-visualização.
- RPC de emissão com transacção, reserva de número em série, snapshot do emitente/adquirente/linhas/regras, eventos e auditoria.
- A função de emissão actualmente só permite FT e FR; PF, NC e ND não estão habilitados para emissão fiscal geral pela mesma função.
- Factura-Recibo é condicionada ao registo de pagamento na mesma transacção.
- Documentos emitidos não devem ser editados; correcções são feitas por documento rectificativo e anulação justificada.

**Estado:** núcleo transaccional existente, mas emissão real bloqueada por autorização e carece de testes de aceitação e de confirmação dos modelos legais. A existência de tipos na interface não significa que todos estejam legalmente habilitados para emissão.

### 2.4 Séries, numeração e integridade
- Séries por tenant, tipo documental, código, exercício e contador.
- A função de emissão bloqueia sem série activa e reserva número com bloqueio transaccional.
- Existe restrição de série activa e registo de eventos.
- O número e snapshot são criados no momento de emissão.

**A validar com AT:** estrutura legal da série, sequência, reinício por exercício, estabelecimento, dispositivos, intervalos, inutilização de números, contingência e tratamento de falhas. A regra técnica actual não deve ser confundida com autorização legal da série.

### 2.5 Clientes, artigos e modelos
- Cadastro de clientes com nome, NUIT, morada e contactos.
- Catálogo de artigos/serviços com código, unidade, preço e código fiscal.
- A criação de artigo consulta regras IVA aprovadas e vigentes; no regime ISPC impede código IVA.
- Modelos de impressão por empresa com logótipo, cores, disposição, contactos e rodapé.

**A validar:** dados obrigatórios do adquirente e excepções legais (consumidor final, operações específicas, não residentes); menções legais não podem ser removidas pelo template; os snapshots têm de preservar o conteúdo fiscal mesmo se o modelo visual mudar.

### 2.6 Pagamentos e comprovativos
- Recebimentos associados a documentos emitidos.
- Pagamentos parciais e sucessivos, idempotência e actualização do saldo.
- Factura-Recibo com emissão e pagamento transaccionais.
- Comprovativo interno de recebimento identificado como não fiscal.

**Lacuna:** os recebimentos não criam automaticamente movimentos de tesouraria nem se conciliam automaticamente com movimentos bancários. O recibo interno não pode ser apresentado como recibo fiscal.

### 2.7 Fiscalidade
- Perfil fiscal: IVA/ISPC e confirmação do enquadramento.
- Motor `tax_rules` com vigência e estado de validação.
- IVA: mapa/declaração de apoio Modelo A e impressão/guardar PDF pelo browser.
- ISPC: catálogo de actividades, tabela de taxas, prévia trimestral e Modelo B – Geral.
- Retenções: registo de retenções IRPS/IRPC com categoria, taxa, base, montante, data, prazo, modelo e estado.
- Obrigações fiscais: calendário por imposto/período, prazo com precisão de data/mês/não confirmado.
- Dossier por obrigação: preparação, revisão, submissão, referência de pagamento, comprovativo e histórico.
- Arquivo fiscal: filtros por exercício, imposto, estado, datas e referências; exportação CSV.
- Mapa fiscal anual.

**Limites:** os mapas e modelos actuais são documentos auxiliares de preparação. Não são formulários oficiais confirmados, não submetem declarações à AT e não geram DUC/referências oficiais de pagamento. Os dados de apuramento devem ser reconciliados com documentos e compras; onde o utilizador introduz valores manualmente, devem ficar identificados como ajuste/manual e com evidência.

### 2.8 Compras, fornecedores e módulos auxiliares
- Existem tabelas e páginas para fornecedores, facturas de compra, tesouraria, reconciliação e relatórios.
- As rotas de tesouraria, reconciliação, fornecedores e relatórios estão actualmente redireccionadas pelo shell e não fazem parte da navegação activa.
- As facturas de compra permitem registar base, IVA, parcela dedutível/não dedutível e fornecedor, mas a ligação aos apuramentos IVA e ao dossier de reembolso não está demonstrada como fluxo completo.

**Decisão de produto:** manter o centro do sistema na facturação e fiscalidade integrada. Não reactivar módulos de gestão financeira independentes sem decisão explícita; usar dados de compras apenas quando necessários para apuramento fiscal e prova documental.

## 3. Estado observado na base de dados em 15/11/2026

### 3.1 Estruturas principais
Foram encontradas, entre outras, as tabelas:
`tenants`, `tenant_users`, `app_users`, `tenant_tax_profiles`, `tenant_fiscal_authorizations`, `fiscal_documents`, `fiscal_document_lines`, `document_series`, `document_events`, `audit_events`, `customers`, `items`, `customer_payments`, `tax_rules`, `ispc_activity_catalog`, `ispc_rate_schedule`, `ispc_quarterly_assessments`, `ispc_model_b_drafts`, `tax_return_periods`, `tax_withholdings`, `tax_obligations`, `tax_obligation_events`, `purchase_invoices`, `suppliers`, `invoice_templates` e tabelas auxiliares de tesouraria/sincronização.

### 3.2 Regras fiscais encontradas
- `tax_rules`: apenas dois códigos IVA activos e aprovados na consulta — taxa normal 16% e taxa reduzida 5%.
- `ispc_rate_schedule`: taxas de 3%, 4%, 5%, 12%, 15% e 20% sobre a parte excedente, com início de vigência em 01/01/2026.
- `tenant_fiscal_authorizations`: sem registos na consulta. Logo, não existe autorização/certificação registada para desbloquear emissão.
- RLS estava activa em todas as 30 tabelas públicas consultadas.
- Os buckets de documentos e evidências fiscais são privados.

**Risco fiscal alto:** a tabela IVA observada não demonstra catálogo completo de isenções, não sujeição, autoliquidação, exportações, operações digitais, localização da operação, pró-rata/limitação de dedução e restantes classificações. Não usar apenas 16%/5% como cobertura integral do CIVA.

### 3.3 Alertas Supabase
O Supabase Advisor assinalou:
- 5 funções `SECURITY DEFINER` acessíveis a utilizadores autenticados: emissão, emissão com pagamento, anulação, registo de recebimento e reconciliação.
- Protecção contra palavras-passe comprometidas desactivada.
- Índice em falta para a FK `tax_obligation_events.obligation_id`.

As funções privilegiadas podem ser legítimas para operações transaccionais, mas precisam de revisão do corpo, validação interna de utilizador/tenant/papel, privilégios EXECUTE mínimos e testes negativos. A função `issue_fiscal_document` escolhe o tenant do utilizador pela primeira associação ordenada por criação; se o mesmo utilizador pertencer a mais de uma empresa, esta selecção deve ser substituída por contexto explícito e validado do tenant activo.

## 4. Enquadramento legislativo e impacto no produto

### 4.1 Pacote legislativo publicado em 29/12/2025
O Suplemento n.º 1 do Boletim da República n.º 248 identifica as Leis n.º 7/2025 a 12/2025, incluindo:
- Lei n.º 9/2025 — ISPC;
- Lei n.º 10/2025 — IVA;
- Lei n.º 11/2025 — IRPS;
- Lei n.º 12/2025 — IRPC.

As alterações principais produzem efeitos a partir de 01/01/2026, conforme os diplomas. A implementação deve usar regras versionadas por data de vigência, e não constantes fixas no código.

### 4.2 IVA — Lei n.º 10/2025
Impactos que o produto tem de contemplar e validar:
- Bens e serviços digitais, incluindo operações com não residentes e regras de localização.
- Declarações mensais com prazos diferenciados: dia 15 do mês seguinte para declarações com crédito ou sem operações; último dia do mês seguinte para declarações com imposto a pagar; dia 10 para determinadas operações digitais de não residentes, conforme a lei.
- Reporte por estabelecimento.
- Regras de dedução proporcional/limitações e operações sujeitas à taxa reduzida de 5%.
- Regras para operações ocasionais e autoliquidação quando aplicável.
- Reembolso: Decreto n.º 52/2025 alterou o regulamento; prazo de processamento indicado de 150 dias e prescrição do direito nos termos do CIVA, com requisitos documentais reforçados.
- Fontes de análise consultadas referem revogação dos regimes especiais de isenção e tributação simplificada. O código ainda contempla `IVA_EXEMPT`; este regime deve ser revisto juridicamente antes de ser apresentado como opção válida em 2026.

**Gap actual:** calendário de obrigações e mapa IVA não demonstram motor completo para distinguir crédito/sem operações/imposto a pagar, operações digitais, não residentes e estabelecimentos. O apuramento de crédito suportado manualmente carece de ligação a documentos de compra e prova de dedutibilidade.

### 4.3 ISPC — Lei n.º 9/2025 e Comunicado AT n.º 9/2026
- Limite de enquadramento anual indicado: 4.000.000 MT.
- Venda de bens/actividades abrangidas: 3%, 4% e 5% por escalões anuais.
- Serviços: 12%; profissões liberais: 15%.
- Parte do volume de negócios que excede o limite: 20%.
- Cumulação de actividades pode exigir aplicação da taxa mais alta.
- Declaração periódica trimestral; obrigação de emitir e registar factura/documento equivalente por cada operação.
- Se o imposto calculado for inferior a 500 MT, não há pagamento da prestação, mas mantém-se a obrigação declarativa.
- Comunicado AT n.º 9/2026: até a AT adaptar o sistema, declaração e pagamento são efectuados no Modelo B – Geral. A informação consultada indica pagamentos por trimestre em Abril, Julho, Outubro e Janeiro do ano seguinte.

**Gap actual:** a prévia ISPC aceita volume de negócios informado pelo utilizador e não o reconcilia integralmente com documentos emitidos, facturas manuais, notas rectificativas e operações excluídas. O sistema deve preservar a origem de cada valor e apresentar diferença de reconciliação. Deve validar período máximo de permanência das profissões liberais e as condições/exclusões do regime, com base no diploma integral.

### 4.4 IRPS — Lei n.º 11/2025
Impactos relevantes para o módulo de retenções e para o cadastro:
- Critérios de residência fiscal alterados.
- Obrigação declarativa anual (Modelo 10) restabelecida para titulares de rendimentos do trabalho dependente, conforme as condições legais.
- Regras para comissões de agentes de moeda electrónica e rendimentos digitais, incluindo taxa liberatória de 10% nos casos previstos.
- Mais-valias com tributação autónoma e escalões próprios.
- Rendimentos prediais: deduções de conservação/manutenção dependem de encargos documentalmente suportados, nos limites legais.

**Gap actual:** o módulo de retenções é um registo manual de taxa/valor/categoria. Não constitui motor completo de processamento salarial, retenção por categoria, declaração anual ou geração de modelos oficiais. Deve ser ampliado apenas após matriz legal e modelos AT confirmados.

### 4.5 IRPC — Lei n.º 12/2025
Impactos relevantes:
- Estabelecimento estável em obras/instalações e prestação de serviços com limiares temporais alterados (incluindo referência a 90 dias para serviços em qualquer período de 12 meses, conforme as condições legais).
- Retenção na fonte sobre rendimentos digitais e comissões de moeda electrónica a 10% nos casos previstos.
- Mais-valias com tributação autónoma a 32%.
- Momento do reconhecimento do custo pode ser relevante para o facto gerador de retenção.
- Eliminação dos regimes simplificados de escrituração/determinação do rendimento colectável e exigência de contabilidade organizada/sistemas contabilísticos informatizados para os contribuintes abrangidos.

**Gap actual:** o FacturaExpress não é um sistema de contabilidade geral. O módulo IRPC não calcula lucro tributável, depreciações, ajustamentos fiscais, pagamentos por conta ou declaração anual. O módulo de retenções não cobre todas as regras de IRPC.

### 4.6 Regulamentos aprovados em 29/09/2026
A comunicação do Governo informa que o Conselho de Ministros aprovou alterações aos regulamentos de IVA, IRPS e IRPC e o novo Regulamento do ISPC, revogando o Decreto n.º 14/2009. A pesquisa nas fontes oficiais consultadas não permitiu localizar, para todos esses instrumentos, o texto integral publicado no Boletim da República, os números dos decretos e as respectivas datas de entrada em vigor.

**Acção obrigatória:** obter os textos integrais publicados e comparar artigo a artigo com as regras existentes antes de alterar prazos, taxas ou modelos. A notícia de aprovação pelo Conselho de Ministros, isoladamente, não substitui a publicação oficial nem permite parametrizar todas as disposições.

### 4.7 Comunicação de facturas, SAF-T (Moz) e autorização do software
- Aviso n.º 40/AT/DGI/2025: comunicação dos dados de facturação à AT e preparação do SAF-T (Moz); os produtores devem obter da AT as estruturas e procedimentos aplicáveis.
- A AT publicou em 30/07/2026 uma lista provisória de softwares de facturação. Uma lista provisória/inquérito não é prova de certificação do FacturaExpress.
- A OCAM publicou FAQ sobre comunicação electrónica e certificação, referindo que os formatos e procedimentos devem seguir a estrutura disponibilizada pela AT.
- O Portal do Contribuinte/e-Declaração é o canal oficial consultado para obrigações IVA/ISPC, referência de pagamento e monitoria. Não presumir que existe API pública de integração.

**Gap crítico:** não foi encontrada implementação do formato SAF-T (Moz), validação XSD/estrutura AT, exportação comprimida de dados de facturação, assinatura, lote, recibo técnico de submissão ou reconciliação de rejeições. Não automatizar acesso ao portal nem simular confirmação da AT sem especificação e autorização formal.

## 5. Matriz de prontidão para validação AT

| Área | Estado actual | Prioridade | Condição para fechar |
|---|---|---:|---|
| Identificação do produtor e software | Dados de versão existem; autorização sem registo | Crítica | Registo e processo formal AT |
| Certificação/autorização | Emissão bloqueada, correctamente | Crítica | Decisão/documento oficial para versão exacta |
| Facturas FT/FR | Rascunhos e emissão técnica condicionada | Crítica | Modelos, campos, menções, série e testes aprovados |
| PF/NC/ND | Tipos presentes, emissão geral não habilitada | Alta | Regras legais e fluxos específicos aprovados |
| Numeração/séries | Reserva transaccional existente | Crítica | Regras oficiais de séries, contingência e auditoria |
| Imutabilidade e correcções | Snapshot/eventos e fluxos de rectificação existentes | Alta | Testes de não alteração, anulação e cadeia documental |
| PDF/arquivo final | Impressão do browser; arquivo imutável não comprovado | Alta | PDF determinístico, hash, Storage privado, reimpressão do snapshot |
| Comunicação mensal de facturas | Não implementada | Crítica | Esquema/canal/prazos AT, exportação e validação |
| SAF-T (Moz) | Não implementado | Crítica | Especificação oficial, XSD, regras e ficheiros de teste |
| IVA 2026 | Parcial; apenas 16% e 5% encontrados em tax_rules | Crítica | Matriz integral de operações e regras com vigência |
| ISPC 2026 | Prévia e Modelo B existem; conciliação parcial | Alta | Reconciliação do volume, prazos e modelo transitório AT |
| IRPS/IRPC | Retenções manuais | Alta | Matriz legal, categorias, modelos e validação |
| Compras e IVA dedutível | Registo parcial | Alta | Elegibilidade, prova, reconciliação e limites |
| Segurança multiempresa | RLS activa; alertas em funções privilegiadas | Crítica | Auditoria de funções, tenant explícito, papéis e testes |
| Continuidade/offline | Sincronização ainda não concluída | Média | Protocolo autorizado para numeração e contingência |

## 6. Plano de preparação — ordem de execução

### Gate 0 — Legal e contacto formal AT
1. Solicitar à AT/DGI a lista vigente de requisitos e o processo de certificação/autorização para software de facturação.
2. Solicitar especificações oficiais para comunicação de dados de facturação, SAF-T (Moz), facturação/aquisições/autofacturação, estrutura, versão, exemplos e regras de validação.
3. Obter os regulamentos integrais aprovados em 29/09/2026 e todos os avisos/comunicados posteriores.
4. Confirmar os modelos oficiais FT, FR, PF, recibo, NC, ND e Modelo B, bem como as regras de séries e arquivo.
5. Registar respostas, versões, responsáveis, datas e documentos oficiais numa matriz de requisitos.

### Gate 1 — Motor fiscal versionado
1. Criar catálogo fiscal por imposto, operação, categoria, localização, regime, estabelecimento e data de vigência.
2. Cobrir IVA normal/reduzido, isenção, não sujeição, autoliquidação, exportações, operações digitais/não residentes, pró-rata e limitações de dedução, após confirmação legal.
3. Rever a opção `IVA_EXEMPT` face à reforma de 2026.
4. Validar taxas ISPC, escalões, excesso, cumulação, profissões liberais, permanência e limiar de 500 MT.
5. Criar regras de retenção IRPS/IRPC para cada categoria e momento de retenção.
6. Fazer os prazos nascerem das regras legais por período e situação declarativa, mantendo fonte e versão; não depender apenas de datas manuais.

### Gate 2 — Integridade do ciclo documental
1. Fechar os campos obrigatórios do emitente/adquirente e excepções legais.
2. Aprovar tipos documentais, menções, série, numeração e estados.
3. Implementar snapshot fiscal imutável, hash e PDF final em Storage privado.
4. Assegurar que reimpressão usa o snapshot original, sem recalcular valores.
5. Fechar rectificações/anulações com motivo, ligação ao original, trilho de auditoria e proibição de eliminação silenciosa.

### Gate 3 — SAF-T e comunicação AT
1. Implementar exportadores separados para dados de facturação e SAF-T (Moz), segundo os esquemas oficiais.
2. Validar ficheiros localmente contra XSD/especificações e regras semânticas oficiais.
3. Criar lote mensal com controlo de período, totais, hash, versão, exportação e histórico.
4. Registar submissão, protocolo, data, resposta, rejeições e reenvio sem duplicar.
5. Só criar integração automática se a AT disponibilizar API/canal autorizado; caso contrário, produzir pacote pronto para submissão manual no portal.

### Gate 4 — Segurança e testes
1. Rever as 5 funções SECURITY DEFINER e reduzir EXECUTE aos papéis necessários.
2. Corrigir a selecção de tenant activo nas funções transaccionais.
3. Activar protecção contra palavras-passe comprometidas.
4. Criar índice em falta para `tax_obligation_events.obligation_id`.
5. Testar papéis, isolamento multiempresa, concorrência, idempotência, numeração, rectificações, pagamentos e exportações.
6. Testar com dados e ficheiros de teste fornecidos/aceites pela AT.
7. Build, lint, typecheck e testes E2E em cada release.

### Gate 5 — Homologação e entrada em produção
1. Entregar versão identificada, documentação técnica, manual, arquitectura, política de actualizações e evidências de testes.
2. Submeter o software e produtor ao processo formal definido pela AT.
3. Corrigir não conformidades e repetir os testes.
4. Guardar certificado/despacho/termo de autorização, âmbito, versão, validade e condições.
5. Desbloquear emissão fiscal apenas para a versão e condições expressamente autorizadas.
6. Manter processo de controlo de versões: qualquer alteração que afecte cálculo, numeração, integridade ou exportação deve passar pela avaliação exigida pela AT.

## 7. Critério de declaração de conformidade

O FacturaExpress só poderá ser descrito como autorizado/certificado/homologado quando existir evidência documental da AT que identifique o software, produtor, versão e âmbito da autorização. Até lá, usar apenas a descrição: **“sistema em desenvolvimento e preparação técnica para avaliação pela AT”**.


## 9. Evidência comparativa: lista provisória de softwares e o que pode ser inferido

Foi consultada a publicação da AT intitulada **“Lista Provisória de Softwares de Facturação AT DGI-PMF”**, datada de 30/07/2026. A cópia indexada do documento apresenta campos de controlo como:
- Nome do programa;
- Nome do produtor/provedor;
- Versão;
- NUIT do produtor;
- Estado do certificado (activo/inactivo).

A própria nota da lista esclarece que os produtores/utilizadores podem solicitar a divulgação dos seus softwares desde que estes estejam em conformidade com os requisitos estabelecidos no **Despacho Ministerial de 29 de Fevereiro de 2012**, relativo à impressão de facturas e ao processamento por mecanismos de saída por computador.

**O que a lista permite concluir:** a AT acompanha a identidade do produtor, identidade do produto, versão concreta e situação de certificação/estado. A versão é material: a autorização não deve ser presumida extensível a qualquer versão futura.

**O que a lista NÃO permite concluir:** não publica uma checklist técnica por produto, não descreve funcionalidades internas dos concorrentes e não demonstra que todos os nomes listados tenham certificado activo. É uma lista provisória/inquérito e não uma especificação técnica. Não é legítimo copiar funcionalidades de concorrentes ou afirmar que um produto está certificado apenas por constar da lista.

### 9.1 Requisitos observáveis que o FacturaExpress deve preparar

1. **Identidade do produtor:** denominação legal, NUIT, endereço, contactos e responsável técnico.
2. **Identidade do produto:** FacturaExpress, versão/build exacto, edição e ambiente.
3. **Gestão de versões:** histórico de releases, hash do artefacto, notas de versão e mecanismo de identificar a versão que emitiu cada documento.
4. **Evidência de conformidade do Despacho de 29/02/2012:** modelos de impressão, campos obrigatórios, legibilidade, numeração, conservação e reprodução fiel.
5. **Integridade documental:** documentos emitidos imutáveis, sequência controlada, registo de eventos, correcções/anulações justificadas e arquivo recuperável.
6. **Exportação e comunicação:** ficheiro mensal conforme estrutura fornecida pela AT, dados de intervenientes, descrição, valores unitários/globais e IVA, submissão no e-Declaração e controlo de comprovativo.
7. **SAF-T (Moz):** manter como trilho distinto, aguardando o XSD/estrutura e regras oficiais de facturação, aquisição e autofacturação.
8. **Dossier de certificação:** pedido formal, correspondência com a AT, versão submetida, casos de teste, amostras, resultados, não conformidades e decisão.

### 9.2 Comunicação mensal de dados de facturação — distinção essencial

O Aviso n.º 40/AT/DGI/2025 refere a submissão mensal de dados de facturas e, separadamente, determina que os produtores contactem a AT para obter requisitos do SAF-T (Moz) e procedimentos de certificação. A orientação publicada pela OCAM descreve ficheiro de dados de facturação a submeter no e-Declaração em CSV/XLSX/XML, tamanho máximo de 2 MB e possibilidade de fraccionar períodos quando o volume o exigir. A FAQ da OCAM diz que o modelo foi partilhado com produtores e que o ficheiro deve seguir a estrutura fornecida pela AT. A EY reportou uma excepção para contribuintes registados no ISPC na orientação inicial de 2025.

Por isso, o CSV preliminar agora acrescentado ao FacturaExpress é **apenas ferramenta de reconciliação e conferência**, não é o ficheiro oficial de comunicação. Não inclui ainda o layout exacto fornecido pela AT, compressão, validação de tamanho do pacote comprimido, fraccionamento por períodos, nem prova de submissão. A rota bloqueia o uso automático por perfil ISPC até confirmação das regras específicas actualmente vigentes.

**Acção obrigatória com a AT:** contactar `efacturacao@at.gov.mz` (endereço referido pela FAQ OCAM) e/ou o sector de Máquinas Fiscais através do contacto indicado na lista, solicitando por escrito: modelo exacto do ficheiro mensal actualmente aceite; layout e dicionário de campos; limite de tamanho e compressão; regra aplicável ao ISPC em 2026; prazo actual; procedimentos e evidências de certificação; XSD/estrutura SAF-T (Moz) e ambiente/casos de teste.

### 9.3 Funcionalidade preliminar adicionada nesta fase

Foi acrescentada na listagem de documentos uma opção de exportação CSV por mês, com dados do emitente, adquirente, documentos e linhas. A exportação:
- Está limitada ao tenant autenticado;
- Inclui documentos emitidos, pagos, parcialmente pagos e anulados;
- É identificada internamente como preliminar e não oficial;
- Rejeita o regime ISPC enquanto a aplicabilidade não for confirmada;
- Não submete dados à AT nem gera protocolo.

### 9.4 Ficha técnica do software

Foi criada a página administrativa `/system-info`, com rota de leitura autenticada, para apresentar nome do produto, versão declarada no `package.json`, hash de commit/ambiente Vercel quando disponíveis, arquitectura e estado da autorização consultada. A página está ligada à navegação de administração. Os dados legais do produtor permanecem explicitamente por preencher, porque não devem ser inferidos dos dados da empresa cliente. Esta ficha é interna e não substitui o dossier formal nem o formulário da AT.

Não apresentar esta função como “comunicação AT concluída”. A substituição pelo exportador oficial só pode ocorrer após obtenção do layout autorizado e testes com ficheiros de referência da AT.


## 8. Fontes consultadas
- AT — Legislação fiscal: https://www.at.gov.mz/legislacao/fiscal
- AT — Comunicados oficiais, incluindo Comunicado n.º 9/2026 e lista provisória de software: https://www.at.gov.mz/informacoes/comunicado-de-imprensa
- Imprensa Nacional — BR n.º 248, Suplemento n.º 1, 29/12/2025: https://inm.gov.mz/pt-br/content/sum%C3%A1rio-suplemento-n%C2%BA-1-de-291225-pag-2180-1-20-br-n%C2%BA-248-boletim-da-rep%C3%BAblica-i-serie-p%C3%A1g-1
- Portal do Contribuinte/e-Declaração: https://edeclaracao.at.gov.mz/
- OCAM — Aviso n.º 40/AT/DGI/2025 e comunicação electrónica de dados de facturação: https://ocam.org.mz/2025/06/ocam-e-at-debatem-implementacao-do-aviso-n-o-40-at-dgi-2025-sobre-comunicacao-eletronica-de-dados-de-faturacao/
- Cegid — Obrigatoriedade de comunicação de facturas e SAF-T (Moz): https://help.ila.cegid.com/primavera/docs/1744041274
- EY — Procedimento de comunicação das facturas à AT: https://www.ey.com/pt_mz/technical/tax-alerts/procedimento-de-comunicacao-das-facturas-emitidas-a-autoridade-tributaria-de-mocambique
- OCAM — FAQ Facturação electrónica: https://ocam.org.mz/2025/06/perguntas-frequentes-sobre-a-facturacao-electronica/
- PwC — Reforma fiscal moçambicana: https://www.pwc.com/mz/pt/servicos/tax/reforma-fiscal-mocambicana.html
- PwC — IVA: https://www.pwc.pt/pt/pwcinforfisco/flash/mocambique/mocambique-iva-alteracao-civa.html
- PwC — IRPS: https://www.pwc.pt/pt/pwcinforfisco/flash/mocambique/mocambique-irps-alteracoes-cirps.html
- PwC — IRPC: https://www.pwc.pt/pt/pwcinforfisco/flash/mocambique/mocambique-irpc-principais-alteracoes.html
- RSM — ISPC e Comunicado AT n.º 9/2026: https://www.rsm.global/mozambique/pt-pt/news/tax-alert-imposto-simplificado-para-pequenos-contribuintes-ispc
- Governo — aprovação de alterações aos regulamentos fiscais em Setembro de 2026: https://portaldogoverno.gov.mz/governo-introduz-alteracoes-aos-regulamentos-fiscais-para-reforcar-eficiencia-tributaria/

**Nota de actualização:** fontes online podem ser actualizadas. Antes de cada release fiscal, confirmar novamente a publicação oficial e a vigência de cada diploma.


## 10. Reauditoria orientada à aprovação — 23/11/2026

Esta secção actualiza o estado observado no repositório e na base Supabase nesta data. Não substitui os textos legais integrais nem qualquer resposta formal da AT.

### 10.1 Evidência directa da autorização

Consulta directa à tabela `public.tenant_fiscal_authorizations` no projecto Supabase de produção:
- Colunas existentes: `tenant_id`, `status`, `authorization_reference`, `authorization_date`, `approved_software_version`, `evidence_note`, `updated_by`, `updated_at`.
- Registos encontrados: **0**.
- Consequência: nenhuma empresa tem autorização registada nesta tabela; não existe base para declarar o FacturaExpress autorizado.

A função `public.issue_fiscal_document(uuid,text)` foi inspeccionada directamente. Confirma:
- exige sessão Supabase autenticada;
- exige papel `owner`, `admin`, `issuer` ou `accountant`;
- exige documento em rascunho, tipo FT/FR, série activa e dados mínimos;
- verifica autorização `approved`, referência, data e igualdade exacta de `approved_software_version` com a versão recebida;
- guarda versão e referência de autorização no snapshot;
- reserva número de série sob bloqueio transaccional e grava eventos/auditoria.

**Bloqueio crítico detectado na mesma função:** a escolha de empresa é feita por `ORDER BY tu.created_at LIMIT 1`, e não pelo tenant activo usado pela sessão da aplicação. Um utilizador associado a mais de uma empresa pode ter o contexto errado seleccionado. A função tem `SECURITY DEFINER`. Não se deve habilitar emissão multiempresa nem tentar contornar o bloqueio antes de corrigir o contexto de tenant e testar chamadas directas/RPC. A correcção requer uma decisão técnica consistente sobre como o tenant activo é passado e validado dentro da transacção; não deve ser improvisada por uma alteração de SQL isolada.

### 10.2 Correcção aplicada nesta auditoria

- `GET /api/system-info` passou a consultar a autorização com filtro explícito `tenant_id = user.tenantId`, evitando apresentar à empresa activa o registo de outra empresa.
- A ficha técnica passou a distinguir autorização aprovada para a versão instalada, versão divergente e ausência de autorização.
- A alteração é apenas de leitura/diagnóstico. Não cria autorização, não altera dados de certificação e não desbloqueia emissão.

### 10.3 Matriz de fecho — critérios que têm de estar provados

| Bloco para AT | Estado após auditoria | Evidência / condição de fecho |
|---|---|---|
| Identificação do produtor | **Aberto** | Denominação legal, NUIT, endereço, contacto e responsável do produtor por confirmar e inserir como dados do produtor |
| Identificação do produto | Parcial | Nome e versão declarada existem; fixar build, hash de artefacto, release e manual |
| Autorização da AT | **Bloqueado** | 0 registos Supabase; pedido, avaliação e decisão formal ainda necessários |
| Correspondência versão-autorização | Parcial | RPC compara versão exacta; validar processo de actualização e reavaliação pela AT |
| Contexto multiempresa na emissão | **Bloqueador técnico crítico** | RPC escolhe primeira associação do utilizador; corrigir tenant activo, testar membro de várias empresas e chamadas directas |
| FT/FR | Parcial | Motor de emissão para FT/FR existe; modelos, campos, menções e cenários legais aguardam validação documental e testes |
| PF/NC/ND | **Aberto** | UI/tipos existem, mas emissão fiscal geral não habilitada; confirmar modelos e fluxos oficiais antes de habilitar |
| Séries e numeração | Parcial | Reserva transaccional existe; regras AT de série, exercício, estabelecimento, contingência e inutilização por confirmar |
| Imutabilidade e auditoria | Parcial | Snapshot/eventos/auditoria existem; falta provar por testes que não há edição/eliminação e que cadeia rectificativa é íntegra |
| PDF e arquivo fiscal | **Aberto** | Não foi demonstrado PDF final imutável com hash e Storage privado associado à emissão e reprodução do snapshot |
| Comunicação mensal | **Bloqueado por especificação** | CSV actual é preliminar e não oficial; falta layout/dicionário AT, limites, compressão, fraccionamento, validação e prova de submissão |
| SAF-T (Moz) | **Bloqueado por especificação** | Exportador/XSD/validador oficial e casos de teste não foram encontrados |
| IVA 2026 | **Parcial / risco elevado** | Base observada anteriormente só demonstrava regras 16% e 5%; matriz integral, excepções, operações digitais e dedutibilidade por validar |
| ISPC 2026 | Parcial | Catálogo e taxas existem; conciliação integral com documentos, regras transitórias e regulamento integral por validar |
| IRPS/IRPC | Parcial | Retenções manuais não equivalem a motor integral nem a modelos oficiais |
| Segurança Supabase | **Aberto** | Rever funções SECURITY DEFINER, privilégios EXECUTE, RLS e isolamento multiempresa; corrigir selecção de tenant |
| Testes de aceitação AT | **Não executados** | Ficheiros, cenários e ambiente de teste oficiais ainda não fornecidos |
| Dossier formal | Parcial | Mapa de sistema existe; faltam dados do produtor, manuais finais, artefactos, casos/resultados de teste e correspondência/decisão AT |

### 10.4 Requisitos documentais a solicitar formalmente à AT

Solicitar por escrito à AT/DGI, guardando pedido, resposta, anexos e datas:
1. Procedimento vigente de registo, certificação ou autorização de software de facturação e enquadramento do Despacho Ministerial de 29/02/2012.
2. Requisitos de impressão: modelos e campos obrigatórios, menções, formato, legibilidade, cópias, conservação e reprodução.
3. Regras oficiais de séries, numeração, exercícios, estabelecimentos, dispositivos, contingência, inutilização e recuperação.
4. Especificação actual do ficheiro mensal de dados de facturação: layout, dicionário, tipos, obrigatoriedade, encoding, delimitadores, tamanho, compressão, fraccionamento, prazo, canal, recibo e rejeições.
5. Especificação SAF-T (Moz): versão, XSD, taxonomias, códigos, ficheiros exemplo, validações, regras de assinatura/selagem se aplicáveis e ambiente de testes.
6. Regra actualmente aplicável ao ISPC e eventuais exclusões/dispensas de comunicação.
7. Modelos e fluxos oficiais de FT, FR, factura simplificada/pronto pagamento, notas de crédito/débito, recibos e demais documentos aplicáveis.
8. Procedimento de submissão de versão, testes de aceitação, correcção de não conformidades, renovação e efeitos de actualizações.
9. Textos integrais e vigência dos regulamentos fiscais publicados após a reforma de 2025, incluindo os aprovados/anunciados em 2026.

Não inventar XSD, estrutura, API, certificados, chaves, assinaturas, códigos fiscais ou respostas da AT. Se a AT só permitir submissão manual, o produto deve preparar o ficheiro e o respectivo controlo de lote sem simular uma integração automática.

### 10.5 Dossier de apresentação — índice mínimo

1. Requerimento e identificação legal do produtor.
2. Identificação do produto, edição, versão, build, hash e ambiente.
3. Arquitectura técnica, fluxos de dados, Supabase, controlo de acesso e isolamento de empresas.
4. Manual de instalação, configuração, operação, emissão, reimpressão, arquivo, cópia de segurança e recuperação.
5. Manual de utilizador e matriz de papéis/permissões.
6. Especificação dos documentos e modelos de impressão.
7. Regras de séries, numeração, estados, correcções, anulações e contingência.
8. Motor fiscal: matriz de regras, fontes legais, datas de vigência, parametrização e histórico.
9. Comunicação mensal e SAF-T (Moz), cada um com a especificação oficial correspondente.
10. Segurança: RLS, privilégios, funções privilegiadas, auditoria, gestão de credenciais e resposta a incidentes.
11. Plano de testes, dados de teste, casos, resultados, evidências e não conformidades corrigidas.
12. Correspondência com AT, submissão, actas de teste, decisão, âmbito e versão autorizada.

### 10.6 Gate de aprovação — sem atalhos

O bloco AT só pode ser marcado como concluído quando:
- todos os requisitos oficiais aplicáveis tiverem fonte, versão e interpretação registadas;
- a implementação corresponder às especificações oficiais;
- os testes técnicos e de aceitação estiverem executados e documentados;
- o produtor tiver submetido o dossier exigido;
- a AT tiver emitido decisão/documento formal que identifique produtor, produto, versão e âmbito;
- a autorização estiver registada para a empresa/instância aplicável e versão exacta;
- o sistema continuar a bloquear emissão quando a autorização faltar, expirar, for suspensa ou não corresponder à versão.

**Estado em 23/11/2026:** preparação técnica em curso; não autorizado/certificado. O bloco AT permanece aberto e não pode ser apresentado como finalizado.


### 10.7 Controlo de versão aplicado à chamada de emissão

A rota `POST /api/documents/[id]/issue` deixou de enviar a versão literal `0.1.0` e passou a importar `package.json`. Assim, a versão enviada à RPC acompanha a versão declarada no pacote, reduzindo o risco de o backend validar uma versão diferente da que a ficha técnica apresenta. A igualdade com a versão formalmente autorizada continua a ser obrigatória no Supabase.

**Validação pendente:** confirmar o build de produção deste commit e testar que uma versão diferente da autorizada é sempre rejeitada. Não foi alterada a autorização nem o bloqueio.
