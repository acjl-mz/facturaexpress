# Arquitectura

## Plataforma única de backend — Supabase
- Next.js App Router para a interface web; Vercel apenas aloja a aplicação.
- Supabase PostgreSQL como fonte central de verdade, acedido exclusivamente pela Data API.
- Supabase Auth para credenciais, tokens, renovação de sessões e logout.
- Supabase RLS para isolamento multiempresa e permissões por papel.
- Supabase Storage para PDFs e anexos privados, com políticas por tenant.
- Supabase Realtime para actualizações de dados e sincronização.
- Supabase Edge Functions para tarefas privilegiadas que não devem expor segredos no cliente.
- Não usar DATABASE_URL, driver PostgreSQL directo, serviço de autenticação próprio ou base de dados externa.

## Serviços de domínio
- Emissão, numeração, cálculo fiscal, pagamentos, relatórios e auditoria.
- Séries e sequências documentais transaccionais no PostgreSQL/Supabase.
- Documentos emitidos imutáveis; correcções por documentos rectificativos.

## Fase local/offline
- PWA para cache da interface e rascunhos; aplicação desktop a definir após prova de conceito.
- Outbox local com UUID por operação, sequência causal, idempotency key e estado pendente/sincronizado/erro.
- Sincronização incremental por cursor e tombstones; retries com backoff.
- Documentos emitidos offline ficam em estado local pendente de sincronização e não recebem número fiscal definitivo até existir autoridade de numeração confiável.
- Séries fiscais atribuídas por estabelecimento/dispositivo com intervalos previamente autorizados, se a AT permitir; nunca gerar números concorrentes por simples relógio local.
- Conflitos de cadastro podem ser resolvidos por versão; conflitos de documentos fiscais exigem intervenção, nunca sobrescrita silenciosa.

## Segurança
- RLS activo em todas as tabelas expostas e políticas por empresa/utilizador.
- Auditoria de eventos fiscais.
- Chaves secretas apenas em Supabase Edge Functions/servidor; a chave publishable pode estar no browser.
- Backups e testes de restauro.
