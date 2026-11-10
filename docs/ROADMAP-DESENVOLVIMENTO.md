# Roadmap de desenvolvimento — FacturaExpress

## Direcção do produto

O FacturaExpress é, antes de tudo, um sistema de **emissão, gestão e impressão de documentos de facturação** para organizações que operam em Moçambique. O percurso principal deve ser simples: preparar documento → validar dados → calcular valores → emitir quando legalmente autorizado → visualizar/guardar PDF → imprimir → acompanhar pagamentos.

A personalização visual é por organização. O produto não deve impor um layout único nem transformar a construção de templates no centro do projecto. O sistema deve separar os dados e regras do documento da sua apresentação.

## Princípios de execução

1. Desenvolver por conjuntos funcionais integrados (*bulk mode*), evitando acrescentar módulos isolados sem fechar o fluxo do utilizador.
2. Aproveitar o que já existe no repositório antes de criar tabelas, APIs ou páginas duplicadas.
3. Manter Supabase como backend único da versão web: Auth, PostgreSQL/Data API, RLS, Storage e Realtime.
4. Não introduzir uma base de dados externa nem dependências de backend fora do Supabase.
5. Manter os documentos emitidos imutáveis; corrigir por documento rectificativo quando aplicável.
6. Não atribuir numeração fiscal nem permitir emissão de produção sem validação dos requisitos e autorizações aplicáveis em Moçambique.
7. Cada organização controla a sua identidade visual e os seus modelos de apresentação.
8. Cada fase termina com testes funcionais, de permissões, isolamento multiempresa e build.

## Fases e entregáveis

### Fase 0 — Auditoria e estabilização da fundação
- Inventariar páginas, APIs, tabelas, funções SQL, políticas RLS e migrações existentes.
- Confirmar o fluxo actual de autenticação, tenant activo e permissões.
- Corrigir erros de build/typecheck e inconsistências de navegação.
- Identificar dados demonstrativos que ainda aparecem como se fossem dados reais.
- Criar testes de regressão para criação, consulta e actualização de rascunhos.

**Saída:** mapa técnico fiável e aplicação compilável, sem regressões no fluxo existente.

### Fase 1 — Núcleo de facturação
- Consolidar tipos de documento suportados e respectivas regras de transição.
- Formulário de criação com cliente, artigos, quantidades, preços, descontos, observações e datas.
- Pesquisa rápida e selecção de clientes/artigos, com criação de novos registos sem abandonar o documento.
- Adição, edição, duplicação e remoção de linhas enquanto o documento for rascunho.
- Cálculo consistente no servidor: subtotal, descontos, base tributável, impostos, retenções e total a pagar.
- Guardar, reabrir, editar e eliminar apenas rascunhos autorizados.
- Validar campos obrigatórios e impedir valores inválidos ou inconsistentes.
- Preservar o identificador idempotente para evitar rascunhos duplicados por reenvio.

**Saída:** fluxo de preparação de factura completo, consistente e persistido no Supabase.

### Fase 2 — Documento final, pré-visualização e impressão
- Construir uma representação documental única, usada na página, PDF e impressão.
- Melhorar a pré-visualização A4 e suportar formatos adicionais apenas quando necessários.
- Controlar quebras de página, repetição de cabeçalhos de tabela, totais e rodapés.
- Corrigir margens, tipografia, alinhamento, símbolos monetários e impressão sem elementos da interface.
- Permitir guardar/transferir PDF e imprimir sem alterar os dados do documento.
- Aplicar a configuração visual de cada organização sem modificar os campos fiscais obrigatórios.
- Guardar PDF final em Supabase Storage quando a política de arquivo for definida.

**Saída:** documento legível e consistente no ecrã, PDF e papel, com apresentação configurável por organização.

### Fase 3 — Cadastro comercial integrado
- Completar ficha de cliente: nome/denominação, NUIT, endereço, contactos e dados comerciais.
- Completar catálogo: código, descrição, unidade, preço, classificação fiscal e estado activo.
- Pesquisa, filtros, paginação e importação/exportação controlada.
- Histórico de documentos por cliente e artigos mais utilizados.
- Evitar duplicação de clientes por NUIT, respeitando casos de consumidor final e regras aplicáveis.

**Saída:** dados comerciais prontos para acelerar a emissão recorrente.

### Fase 4 — Ciclo documental
- Consolidar séries por organização, estabelecimento, tipo e exercício, conforme requisitos confirmados.
- Gerir estados: rascunho, em validação, emitido, pago parcialmente, pago, anulado/rectificado quando permitido.
- Completar factura, factura-recibo, proforma, recibo e notas de crédito/débito apenas segundo enquadramento legal validado.
- Ligar documentos rectificativos ao documento original, com motivo e trilho de auditoria.
- Preservar snapshots dos dados do emitente, adquirente, linhas e regras aplicadas no momento da emissão.

**Saída:** ciclo documental rastreável, sem alteração silenciosa de documentos finalizados.

### Fase 5 — Recebimentos e conta corrente
- Registar pagamentos totais e parciais associados a documentos elegíveis.
- Suportar meios de pagamento, datas, referências e comprovativos internos.
- Calcular saldo em aberto e estado de liquidação.
- Impedir pagamentos duplicados e saldos negativos.
- Distinguir claramente comprovativo interno de recibo fiscal.
- Apresentar extracto de conta corrente por cliente.

**Saída:** acompanhamento comercial dos valores facturados e recebidos.

### Fase 6 — Fiscalidade integrada na emissão
- Confirmar perfil fiscal e regime da organização.
- Aplicar regras fiscais versionadas por data de vigência e operação.
- Classificar linhas: tributadas, isentas, não sujeitas e outras categorias legalmente aplicáveis.
- Calcular IVA e retenções apenas quando o enquadramento estiver confirmado.
- Apresentar menções legais e discriminação fiscal nos documentos.
- Gerar mapas de apoio a partir dos documentos e pagamentos, sem duplicar lançamentos manuais.
- Validar SAF-T (Moz), comunicação electrónica e demais obrigações com especificações oficiais da AT.

**Saída:** cálculos e informação fiscal coerentes com os documentos de origem. Não constitui, por si só, certificação do software.

### Fase 7 — Pesquisa, relatórios e gestão
- Painel baseado em dados reais, não em indicadores demonstrativos.
- Pesquisa global por número, cliente, NUIT, data, estado e valor.
- Relatórios de facturação por período, cliente, artigo e tipo documental.
- Mapas de valores em aberto, recebimentos e impostos.
- Exportações com controlo de permissões e registo de auditoria.

**Saída:** informação operacional e de gestão fiável.

### Fase 8 — Segurança, qualidade e preparação para produção
- Revisão completa de RLS, permissões por papel e isolamento por tenant.
- Testes de concorrência na atribuição de números e registo de pagamentos.
- Auditoria de emissão, impressão, exportação, anulação e rectificação.
- Testes de backup/restauro, acessibilidade e comportamento em dispositivos móveis.
- Testes automatizados de build, typecheck e fluxos críticos.
- Validação jurídica/fiscal e documental dos requisitos de Moçambique.
- Só activar emissão em produção após autorização/certificação aplicável e validação formal.

**Saída:** release candidata, com bloqueios legais explicitamente resolvidos ou documentados.

### Fase 9 — Operação local e sincronização
- PWA e/ou aplicação desktop a decidir após prova de conceito.
- Cache da interface e preparação de rascunhos offline.
- Fila local de operações com UUID, idempotência, tentativas e estado de sincronização.
- Sincronização incremental com Supabase quando a ligação regressar.
- Resolução explícita de conflitos; nunca sobrescrever silenciosamente documentos.
- Numeração fiscal definitiva apenas através de mecanismo autorizado e sem risco de duplicação.

**Saída:** operação resiliente à conectividade, sem comprometer integridade documental.

## Ordem de execução imediata

1. Fase 0: auditoria e estabilização.
2. Fase 1: fechar o núcleo de criação e edição de rascunhos.
3. Fase 2: fechar pré-visualização, PDF e impressão.
4. Fase 3: completar cadastro comercial e integração com o formulário.
5. Fases 4 e 5: ciclo documental e pagamentos.
6. Fases 6 a 8: fiscalidade, relatórios, segurança e preparação para produção.
7. Fase 9: modo local/offline depois da versão web estar estável.

## Critério de conclusão de cada bulk

Uma fase só é considerada concluída quando:
- interface, API e persistência estão ligadas;
- permissões e isolamento por organização foram testados;
- cálculos e transições de estado têm testes;
- não existem dados demonstrativos confundidos com dados reais;
- build e typecheck passam;
- documentação é actualizada;
- deployment é confirmado como pronto, não apenas colocado em fila.

## Estado inicial observado

A base actual já contém cadastro de clientes e artigos, criação e consulta de rascunhos, detalhe documental com pré-visualização/impressão do navegador, configuração de templates e mecanismo de emissão controlada. A emissão está bloqueada sem autorização/certificação aplicável. A prioridade não é recomeçar estes módulos, mas auditar e completar a experiência de ponta a ponta.
