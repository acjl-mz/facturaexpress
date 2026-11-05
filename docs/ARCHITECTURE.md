# Arquitectura

## Fase web
- Next.js App Router para interface e API.
- PostgreSQL como fonte central de verdade.
- Serviços de domínio separados da interface: emissão, numeração, cálculo fiscal, pagamentos, relatórios e auditoria.
- Autenticação multiempresa com isolamento por tenant e permissões por utilizador.
- Anexos e PDFs em armazenamento privado.

## Fase local/offline
- PWA para cache da interface e rascunhos; aplicação desktop com serviço local PostgreSQL/SQLite a definir após prova de conceito.
- Outbox local com UUID por operação, sequência causal, idempotency key e estado pendente/sincronizado/erro.
- Sincronização incremental por cursor e tombstones; retries com backoff.
- Documentos emitidos offline ficam em estado local pendente de sincronização e não recebem número fiscal definitivo até existir autoridade de numeração confiável.
- Séries fiscais atribuídas por estabelecimento/dispositivo com intervalos previamente autorizados, se a AT permitir; nunca gerar números concorrentes por simples relógio local.
- Conflitos de cadastro podem ser resolvidos por versão; conflitos de documentos fiscais exigem intervenção, nunca sobrescrita silenciosa.

## Segurança
- RLS/tenant scoping em todas as entidades.
- Auditoria append-only para eventos fiscais.
- Segredos apenas no servidor.
- Backups e testes de restauro.
