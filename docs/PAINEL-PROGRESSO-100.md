# Painel permanente de progresso — FacturaExpress

**Baseline inicial:** 23 de Novembro de 2026  
**Repositório:** `acjl-mz/facturaexpress`  
**Branch de referência:** `main`  
**Commit avaliado:** `c8176276a2d3755cee61dbb434d76c16011f101c`  
**Versão declarada no package.json:** `0.1.0`  
**Estado Vercel observado:** Production / READY  
**Percentagem global de referência:** **47%**

> Este painel é a referência única para acompanhar o encerramento do projecto. A percentagem mede conclusão comprovada, não volume de código, número de páginas ou existência de um deployment. Não declarar 100% enquanto todos os critérios de aceitação, testes e dependências externas aplicáveis não estiverem fechados.

## 1. Regra de cálculo

A percentagem global é a soma de `peso da área × nível de conclusão da área`, dividida por 100.

Cada área recebe uma pontuação de maturidade:
- **0%** — não iniciado;
- **25%** — estrutura ou protótipo criado, sem fluxo integrado;
- **50%** — implementação parcial, com lacunas conhecidas;
- **75%** — fluxo integrado, mas ainda sem cobertura suficiente de testes/aceitação;
- **90%** — testes funcionais, segurança e documentação aprovados, com pendências externas menores;
- **100%** — todos os critérios da área verificados e aceites.

A pontuação só sobe com evidência verificável: código na branch principal, consultas/migrações confirmadas, testes executados, comportamento observado e/ou documentação oficial. Um build READY confirma apenas que a publicação foi construída; não prova que todos os fluxos funcionam.

## 2. Baseline por área

| Área | Peso | Maturidade actual | Contributo |
|---|---:|---:|---:|
| Núcleo de facturação e rascunhos | 15% | 70% | 10,50 |
| Ciclo documental, séries, rectificações e anulações | 12% | 55% | 6,60 |
| Pré-visualização, PDF, impressão e templates por empresa | 13% | 55% | 7,15 |
| Empresas, utilizadores, clientes e artigos | 8% | 65% | 5,20 |
| Pagamentos e conta corrente | 8% | 60% | 4,80 |
| Motor fiscal, regimes IVA/ISPC e obrigações | 15% | 35% | 5,25 |
| Compatibilidade AT, comunicação fiscal e autorização | 10% | 10% | 1,00 |
| Segurança, qualidade, testes e estabilidade | 10% | 35% | 3,50 |
| Publicação, documentação e operação web | 4% | 75% | 3,00 |
| Operação local/offline e sincronização | 5% | 0% | 0,00 |
| **Total** | **100%** |  | **47,00%** |

Os valores de maturidade são estimativas conservadoras de baseline, baseadas no código, documentação, estado observado da base de dados e deployment. Não equivalem a uma certificação de qualidade nem substituem os testes de aceitação.

## 3. Evidências consideradas no baseline

- O deployment de produção associado ao commit `c817627` estava em estado `READY`; o build terminou e gerou 59 páginas estáticas.
- O repositório contém páginas e APIs para documentos, séries, clientes, artigos, pagamentos, templates, IVA, ISPC, retenções, obrigações fiscais e arquivo.
- A base Supabase consultada contém 30 tabelas públicas; as 30 tinham RLS activa e existiam 83 políticas RLS.
- Foram identificadas 5 funções públicas `SECURITY DEFINER`, que exigem revisão de privilégios, contexto de tenant e testes negativos.
- A tabela `tenant_fiscal_authorizations` tinha zero registos na consulta. A emissão fiscal deve continuar bloqueada sem autorização aplicável.
- A exportação de facturação para AT existente é preliminar; não foi demonstrada conformidade com o layout oficial, submissão no Portal, SAF-T (Moz) ou protocolo de recepção.
- Existem modelos auxiliares IVA/ISPC, mas não devem ser tratados como formulários oficiais nem como comprovativos de submissão/pagamento.
- Os logs do deployment incluem avisos de lint/React Hooks; o histórico de build também registou erro de referência a `location` durante prerenderização. O build READY não elimina a necessidade de investigar e testar runtime.
- Não foi demonstrado um ciclo completo de testes funcionais autenticados, isolamento entre empresas, concorrência de numeração, pagamentos, PDF/arquivo ou testes de regressão.
- A arquitectura offline/local está documentada, mas não foi demonstrada como funcionalmente implementada.

## 4. Critérios obrigatórios para chegar a 100%

### A. Facturação
- Criar, editar, guardar, reabrir e validar rascunhos.
- Cálculo final no servidor, com arredondamento e validação de valores.
- Testes de linhas, descontos, impostos, retenções, estados e idempotência.
- Mensagens e bloqueios claros para operações não autorizadas.

### B. Ciclo documental
- Tipos documentais e transições legalmente confirmados.
- Séries, numeração, concorrência, reinício de exercício e contingência validados.
- Emissão, imutabilidade, rectificação e anulação com motivo e auditoria.
- Testes de concorrência e de tentativas não autorizadas.

### C. Impressão e arquivo
- Um modelo documental consistente no ecrã, PDF e papel.
- Templates por organização sem permitir remover menções obrigatórias.
- Testes A4, documentos longos, quebras de página, margens e impressão.
- PDF final arquivado no Supabase Storage privado, ligado ao documento, com política por tenant e integridade verificável.

### D. Cadastros e pagamentos
- Fluxos completos de empresa, utilizadores, papéis, clientes e artigos.
- Pesquisa, filtros, validação de duplicados e histórico.
- Pagamentos parciais/totais, idempotência, saldo e extracto por cliente.
- Distinguir comprovativo interno de recibo fiscal.

### E. Fiscalidade
- Matriz fiscal validada para os regimes aplicáveis em Moçambique.
- Regras versionadas por vigência, natureza de operação e enquadramento.
- Separação efectiva IVA/ISPC e bloqueios de incompatibilidades.
- Apuramentos reconciliados com documentos e compras, com origem dos ajustes.
- Obrigações, revisão, submissão, referências e comprovativos com histórico.

### F. Autoridade Tributária
- Obter e validar as especificações oficiais aplicáveis: comunicação mensal, SAF-T (Moz), layouts, campos, formatos, limites e procedimentos.
- Implementar e testar exportações exactamente segundo as especificações confirmadas.
- Preparar dossier técnico, identificação do produtor/produto/versão, documentação e casos de teste.
- Submeter o produto ao procedimento formal aplicável e guardar evidência da decisão.
- Não afirmar certificação/autorização antes da confirmação formal da AT.

### G. Segurança e qualidade
- Rever as 83 políticas RLS e todas as tabelas expostas.
- Rever as 5 funções SECURITY DEFINER, privilégios EXECUTE e validação interna de utilizador, papel e tenant.
- Testes de isolamento entre empresas e de acesso por papel.
- Corrigir erros SSR/prerender e avisos de lint relevantes.
- Testes automatizados de build, typecheck e fluxos críticos.
- Testes de backup/restauro, acessibilidade, dispositivos móveis e monitorização.

### H. Operação e sincronização
- Publicação web estável, monitorizada e com procedimentos de recuperação.
- Documentação de configuração e operação.
- Implementar e testar PWA/aplicação local, rascunhos offline, fila idempotente, sincronização e resolução de conflitos, se mantida como requisito de lançamento.

## 5. Regras para todas as actualizações futuras

1. Esta ponderação mantém-se fixa durante o projecto. Alterações aos pesos só com decisão explícita do responsável do produto.
2. Em cada bulk, actualizar apenas a maturidade das áreas realmente afectadas.
3. Não aumentar pontuação por código escrito sem integração e teste.
4. Se um teste falhar ou surgir regressão, reduzir a pontuação da área afectada e registar o motivo.
5. Cada actualização deve indicar: data, commit, deployment, pontuação anterior, pontuação actual, variação, evidências, bloqueios e próximo conjunto de tarefas.
6. Não arredondar para cima para aparentar progresso. Apresentar uma casa decimal quando necessário.
7. Separar sempre conclusão técnica do produto e aprovação externa da AT.
8. **100% significa todos os critérios deste painel fechados e evidenciados**, incluindo a decisão formal da AT quando exigida para o uso pretendido. Se a AT tiver prazos externos, manter essa dependência visível e não a marcar como concluída antecipadamente.

## 6. Próxima prioridade recomendada

1. Estabilização técnica: localizar e corrigir o acesso a `location` durante SSR/prerender e limpar avisos relevantes.
2. Testes funcionais autenticados do fluxo principal: rascunho → validação → pré-visualização → PDF/impressão.
3. Testes de segurança multiempresa, papéis e funções privilegiadas no Supabase.
4. Fechar arquivo de PDF no Storage e a integridade documental.
5. Só depois avançar para os restantes gaps fiscais e de compatibilidade AT.

**Última revisão deste painel:** 23/11/2026 — baseline inicial de 47%.


## 7. Diário de execução — primeiro bulk de estabilização

**Data:** 23/11/2026  
**Commit de código mais recente:** `614fac9e73a3274fff697e1a281116c4046c1df3`  
**Estado da avaliação:** alterações gravadas na `main`; deployment de produção ainda em fila na última verificação.

### Alterações realizadas
- `app/ispc/model-b/page.tsx`: estabilizada a função de carregamento com `useCallback` e dependência explícita do efeito.
- `app/customers/[id]/page.tsx`: estabilizado o carregamento do extracto por período/cliente e alinhadas as dependências do efeito.
- `app/documents/[id]/edit/page.tsx`: o carregamento de dados auxiliares volta a reagir à mudança do identificador do rascunho.
- `app/components/app-shell.tsx`: removidas variáveis de perfil fiscal não utilizadas.
- `app/api/ispc/preview/route.ts`: removido parâmetro de captura de erro não utilizado.

### Resultado e limites
- As alterações foram confirmadas na branch `main` em commits separados; o último SHA é o indicado acima.
- Ainda não existe evidência de build concluído para o conjunto final destas alterações. Não marcar os avisos como resolvidos até inspeccionar os logs do deployment final.
- A advertência de imagem `<img>` permanece por tratar; não foi alterada sem contexto suficiente.
- A ocorrência anterior de `ReferenceError: location is not defined` durante prerenderização ainda não foi localizada. A pesquisa textual no código não encontrou acesso directo que explique o stack minificado; continua pendente análise da dependência/bundle.
- Não houve testes autenticados de navegação nem testes de integração com dados reais. A pontuação global permanece **47%**; este bulk não gera aumento de percentagem sem validação.

### Próximo passo
Aguardar o deployment associado ao commit final, rever todos os logs de lint/SSR e, se o build estiver limpo, executar testes funcionais autenticados do fluxo de rascunho, extracto de cliente e mapa ISPC.


## 8. Diário de execução — segundo bulk de estabilização

**Data:** 23/11/2026  
**Deployment anterior:** `dpl_FVv7d7owvqer9hCZStihYitUCMXo`  
**Commit avaliado:** `5848c606c3a74bd04e91014bfb57821bfb7a0871`  
**Estado:** Production / READY; build de 43 segundos; 59/59 páginas estáticas geradas.

### Resultado da inspecção dos logs
- Não foram encontradas ocorrências de `ReferenceError: location is not defined` nos eventos do deployment `5848c606`.
- Também não foram encontrados avisos `react-hooks/exhaustive-deps` nesse build.
- Permaneciam avisos de variáveis/imports não utilizados e a recomendação Next.js para imagem `<img>`.
- O erro histórico de `location` não está demonstrado como resolvido de forma definitiva: não foi identificado o componente/biblioteca de origem e a ausência no log mais recente não prova que não volte a ocorrer noutro caminho de prerenderização.

### Alterações efectuadas neste bulk
- `app/components/app-shell.tsx`: removido estado/perfil fiscal que não era utilizado no shell; mantida a consulta fiscal necessária às regras de encaminhamento.
- `app/ispc/model-b/page.tsx`: removido import não utilizado.
- `app/page.tsx`: removidos import e estado/cálculo fiscal sem utilização, bem como uma chamada redundante a `/api/tax-profile` no dashboard.
- `app/payments/page.tsx`: removidos imports de ícones não utilizados.
- `app/reconciliation/page.tsx`: removido import não utilizado.
- `app/documents/[id]/page.tsx`: documentada a excepção local para `<img>`, pois o logótipo é configurável por organização e o URL é fornecido em runtime; não foi substituído por `next/image` sem uma estratégia de configuração/remote patterns compatível com URLs multi-tenant.

### Commits na branch main
- `69e3bfb` — app shell
- `92d19dd` — página Modelo B
- `ad9c125` — dashboard
- `add4d10` — pagamentos
- `42440ff` — reconciliação
- `18b3685` — detalhe de documento

### Critérios ainda não fechados
- Aguardam build e revisão dos logs do deployment que inclui todos estes commits.
- A origem do antigo erro SSR `location` continua sob observação.
- Ainda não foi executado um conjunto autenticado de testes de ponta a ponta.
- A maturidade global mantém-se em **47%** até confirmação do build e testes de aceitação; as limpezas de lint isoladas não justificam aumento da pontuação.

### Próximo passo
Confirmar o deployment final associado ao último commit, rever warnings/errors, e depois avançar para testes autenticados do fluxo de rascunho → emissão autorizada → PDF/impressão, sem emitir documentos fiscais reais de teste.


## 9. Diário de execução — primeiro bulk funcional do ciclo documental

**Data:** 23/11/2026  
**Commit:** `4b2c7a0c8b5d63992f7bc0e64967bf6b26a3b8c2`  
**Deployment:** `dpl_C8tDXBhLUWpqYidZYF2SinUdPpcm` — Production / READY.

### Alteração funcional
- Implementado `PATCH /api/documents`, que faltava apesar de o formulário de edição de rascunhos já o invocar.
- A API autentica a sessão e valida papel, UUID, estado do documento, datas, observações, quantidade de linhas, descrições, unidades, quantidades, preços e descontos.
- A actualização usa a função existente `update_fiscal_document_draft` no Supabase, que bloqueia a linha do documento, confirma que continua em rascunho, valida o cliente e o perfil fiscal, recalcula impostos e totais no servidor e regista eventos/auditoria.
- O template seleccionado é validado no tenant antes da associação ao documento.
- Não foi criada uma lógica fiscal duplicada na API.

### Verificação
- O deployment de produção correspondente ao commit ficou em estado `READY`.
- O log confirma compilação bem-sucedida, verificação de lint/tipos e geração de 59/59 páginas estáticas.
- Permanecem avisos de lint em páginas fora deste fluxo.
- O mesmo deployment registou novamente `ReferenceError: location is not defined` em prerenderização (chunk minificado `5591.js`). Portanto, esta falha continua aberta e deve ser localizada; não deve ser considerada resolvida.
- Não foi executado teste funcional autenticado de edição com dados de uma empresa. O build confirma compilação, não o comportamento de runtime da operação.
- A pontuação global permanece **47%**. A implementação fecha uma lacuna de API, mas ainda falta validar o fluxo ponta a ponta e os cenários de erro/concorrência.

### Próximos critérios funcionais
1. Testar criar → editar → reabrir rascunho e confirmar persistência de cliente, linhas, impostos, vencimento e template.
2. Testar que documentos emitidos/anulados não podem ser alterados e que utilizadores sem papel autorizado recebem 403.
3. Testar tentativas com cliente/artigo/template de outro tenant.
4. Testar duas actualizações concorrentes do mesmo rascunho e confirmar que a função SQL mantém a integridade.
5. Investigar a origem de `location` no chunk SSR e corrigir sem ocultar o erro.
6. Prosseguir para PDF/arquivo privado e testes de emissão/rectificação/pagamento.


## 10. Auditoria de preparação AT — 23/11/2026

- Actualizada a matriz de preparação AT em `docs/MAPA-SISTEMA-E-PREPARACAO-AT-2026-11-15.md`, com reauditoria da função de emissão, autorização, comunicação mensal, SAF-T (Moz), produtor, dossier e gates formais.
- Consulta directa Supabase: `tenant_fiscal_authorizations` tem **0 registos**.
- Inspecção da RPC `issue_fiscal_document`: verifica autorização aprovada e versão exacta, mas selecciona o tenant pela primeira associação do utilizador (`ORDER BY created_at LIMIT 1`). É um bloqueador técnico crítico para utilizadores multiempresa; exige correcção e testes antes de qualquer emissão.
- Corrigida a rota `/api/system-info` para filtrar a autorização pelo tenant activo e a ficha técnica para mostrar ausência, correspondência ou divergência de versão.
- Commits desta actualização: `f54689a` (consulta de autorização tenant-scoped), `e840e13` (estado da autorização na ficha), `9de4613` (matriz AT).
- A emissão continua bloqueada na ausência de autorização formal. Não inserir registos fictícios nem activar emissão para testes.
- Não foi obtido da AT o layout oficial de comunicação mensal, XSD/SAF-T (Moz), casos de teste, nem decisão de certificação. Sem estes artefactos externos, esses blocos não podem ser tecnicamente finalizados nem declarados aprovados.
- A pontuação global permanece **47%**. O trabalho desta secção é auditoria, correcção de escopo de leitura e formalização de bloqueadores; não representa aprovação AT nem teste de aceitação.
