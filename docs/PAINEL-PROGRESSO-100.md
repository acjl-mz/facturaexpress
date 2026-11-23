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
