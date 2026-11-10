# FacturaExpress

Sistema de facturação para Moçambique, com prioridade à versão web e arquitectura preparada para operação local/offline e sincronização contínua.

## Estado do produto

**Fundação web em implementação.** O sistema ainda não está certificado nem autorizado pela Autoridade Tributária de Moçambique. A utilização em produção para emissão de documentos fiscais depende da validação legal, técnica e dos procedimentos de autorização/certificação aplicáveis.

## Arquitectura

- Next.js App Router + TypeScript.
- Supabase como plataforma única de backend: PostgreSQL, Auth, Data API, RLS, Storage e Realtime.
- A aplicação não utiliza ligação PostgreSQL directa, servidor de autenticação próprio, nem credenciais de base de dados no Vercel.
- Valores monetários em MZN; regras fiscais versionadas e configuráveis.
- Documentos emitidos imutáveis; correcções por documentos rectificativos.
- Séries e sequências documentais controladas no servidor.
- Auditoria de operações críticas e isolamento de dados por empresa através de RLS.
- Preparação para operação offline-first e sincronização contínua.

## Desenvolvimento

Requisitos: Node.js 22+ e um projecto Supabase.

```bash
npm install
cp .env.example .env.local
# configurar NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
npm run dev
```

As tabelas, políticas RLS, funções e triggers são geridas no Supabase. Não configurar DATABASE_URL, PGHOST, PGUSER, PGPORT ou credenciais PostgreSQL no Vercel.

## Documentação

- docs/LEGAL-COMPLIANCE-MZ.md — matriz legal e pontos pendentes de validação.
- docs/ROADMAP-DESENVOLVIMENTO.md — fases e critérios de conclusão do produto.
- docs/DESENHO-FUNCIONAL.md — fluxo principal, ecrãs, regras e critérios de aceitação.
- docs/ARCHITECTURE.md — arquitectura web/local e sincronização.
- database/migrations/ — histórico de esquema SQL gerido no Supabase.

## Limitação legal importante

A presença de campos, validações ou exportações neste produto não constitui certificação fiscal. A emissão comercial deverá aguardar confirmação documental da autorização/certificação do software e validação dos layouts, séries, formatos de exportação e procedimentos exigidos pela AT.
