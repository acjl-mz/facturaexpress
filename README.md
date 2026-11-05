# FacturaExpress

Sistema de facturação para Moçambique, com prioridade à versão web e arquitectura preparada para operação local/offline e sincronização contínua.

## Estado do produto

**Fase inicial — fundação da versão web.** O sistema ainda não está certificado nem autorizado pela Autoridade Tributária de Moçambique. A utilização em produção para emissão de documentos fiscais depende da validação legal, técnica e dos procedimentos de autorização/certificação aplicáveis.

## Princípios

- Next.js App Router + TypeScript.
- PostgreSQL como base de dados, sem dependência estrutural de Supabase.
- Valores monetários em MZN e cálculos decimais no servidor.
- Documentos emitidos imutáveis; correcções por documentos rectificativos.
- Séries e sequências documentais controladas no servidor e por transacção.
- Auditoria de operações críticas.
- Preparação para fila de sincronização offline-first e exportações fiscais.
- Regras fiscais versionadas e configuráveis, sem assumir taxas como permanentes.

## Desenvolvimento

Requisitos: Node.js 22+, PostgreSQL 15+.

```bash
npm install
cp .env.example .env.local
# configurar DATABASE_URL
npm run dev
```

## Documentação

- docs/LEGAL-COMPLIANCE-MZ.md — matriz legal e pontos pendentes de validação.
- docs/ARCHITECTURE.md — arquitectura web/local e sincronização.
- database/migrations/001_initial_schema.sql — esquema inicial PostgreSQL.

## Limitação legal importante

A presença de campos, validações ou exportações neste produto não constitui certificação fiscal. A emissão comercial deverá aguardar confirmação documental da autorização/certificação do software e validação dos layouts, séries, formatos de exportação e procedimentos exigidos pela AT.