# Matriz de conformidade — Moçambique

> Documento de trabalho, não parecer jurídico. Confirmar sempre a versão vigente dos diplomas, instruções e procedimentos com a Autoridade Tributária (AT) e assessoria jurídica/fiscal local. O produto não deve ser anunciado como certificado/homologado sem prova documental.

## Requisitos funcionais a validar

1. Identificação do emitente: denominação, NUIT, endereço, actividade e dados de registo aplicáveis.
2. Identificação do adquirente e NUIT quando legalmente exigível.
3. Tipo documental, série, número sequencial, data/hora, descrição, quantidades, preços, descontos, bases tributáveis, taxas, imposto e total.
4. Regras específicas para IVA: operações tributáveis, taxas, isenções, não sujeição, menções legais e direito à dedução.
5. Documentos rectificativos: notas de crédito/débito ligadas ao original, motivo e valores; proibição de apagar ou alterar silenciosamente documentos emitidos.
6. Retenções na fonte e demais impostos apenas conforme enquadramento do emitente/operação e parametrização legal vigente.
7. Conservação, integridade, disponibilidade e exportação dos registos.
8. Auditoria de emissão, anulação, rectificação, impressão, exportação e sincronização.
9. Comunicação electrónica e SAF-T (Moz): formatos, prazos, canais, validações, assinatura e requisitos técnicos a confirmar com AT.
10. Requisitos de certificação, homologação ou autorização do software e do produtor, se aplicáveis ao enquadramento concreto.

## Diplomas e fontes oficiais a verificar antes de produção

- Código do IVA e legislação que o altera (incluindo taxas, isenções e regimes especiais).
- Regulamento do Código do IVA e regras de facturação.
- Código do IRPS e Código do IRPC, no que respeita a retenções na fonte.
- Regime do Imposto Simplificado para Pequenos Contribuintes (ISPC), quando aplicável.
- Legislação e instruções da AT relativas a facturação electrónica, comunicação de dados de facturação e SAF-T (Moz).
- Regras de arquivo, protecção de dados e prova documental aplicáveis.

## Bloqueios de lançamento fiscal

- Obter lista oficial e actualizada dos requisitos técnicos e legais da AT.
- Confirmar se o software precisa de certificação/homologação e obter aprovação antes de alegar conformidade.
- Validar modelos de factura, factura-recibo, recibo, proforma, nota de crédito e nota de débito.
- Validar taxas, menções e regras de arredondamento com casos oficiais.
- Validar geração/importação SAF-T (Moz) e comunicação electrónica com dados de teste da AT.
- Fazer revisão jurídica/fiscal e testes de aceitação assinados.


## Actualização de enquadramento — Novembro de 2026

### Obrigações que condicionam a emissão em produção

- A Lei n.º 10/2025, de 29 de Dezembro, alterou o Código do IVA com efeitos a partir de 1 de Janeiro de 2026, incluindo regras para bens e serviços digitais e a submissão de facturas/documentos equivalentes à AT nos termos a regulamentar. A implementação deve suportar regras fiscais com vigência temporal, operações com não residentes e reporte por estabelecimento. Ver análise da PwC e da SAL & Caldeira: https://www.pwc.pt/pt/pwcinforfisco/flash/mocambique/mocambique-iva-alteracao-civa.html e https://www.dlapiperafrica.com/pt/mozambique/insights/2026/Changes-to-the-VAT-Code-.
- O Aviso n.º 40/AT/DGI/2025, de 27 de Março, descreve a submissão electrónica mensal dos dados das facturas através de ficheiro extraído de software autorizado/certificado, com preparação do SAF-T (Moz). A OCAM publicou perguntas frequentes resultantes de diálogo com a AT sobre formatos e certificação: https://ocam.org.mz/2025/06/perguntas-frequentes-sobre-a-facturacao-electronica/ e https://ocam.org.mz/2025/06/ocam-e-at-debatem-implementacao-do-aviso-n-o-40-at-dgi-2025-sobre-comunicacao-eletronica-de-dados-de-faturacao/.
- O relatório anual do PESOE 2025 do Ministério da Economia e Finanças descreve uma solução transitória para software autorizado e indefinições na calendarização do SAF-T/e-factura: https://www.mef.gov.mz/index.php/publicacoes/politicas/bdpesoe/bdpesoe-2025/2484-bdpesoe-anual-2025-final/file.
- A Lei n.º 9/2025, de 29 de Dezembro, reformulou o ISPC. O sistema deve impedir a aplicação de IVA em documentos de sujeitos passivos ISPC, sem prejuízo das regras específicas de auto-facturação, retenção e reporte previstas no diploma: https://mooremz.co.mz/wp-content/uploads/2026/01/ISPC-2025.pdf.
- A taxa e a natureza fiscal de cada operação não devem ser presumidas pelo software. Devem resultar de regras legalmente validadas, regime fiscal confirmado e data da operação. A taxa normal indicada em fontes de análise para 2026 é 16%, mas o sistema não a aplica automaticamente nesta fase.

### Estado de implementação do produto

- O módulo actual cria apenas rascunhos internos (FT/FR como tipos de trabalho); não atribui número, série, data de emissão fiscal, assinatura, QR, hash fiscal ou estado de documento emitido.
- O rascunho não é factura válida nem deve ser entregue ao cliente como documento fiscal.
- Não foi implementada submissão à AT, SAF-T (Moz), exportação Aviso 40, nem integração e-Declaração. Antes disso, a ACJL deve obter junto da AT os layouts, esquemas, especificações, procedimentos de certificação e confirmação do regime aplicável.
- A emissão definitiva exige decisão formal sobre certificação/autorização do FacturaExpress, aprovação dos modelos, regras de numeração, arquivo, auditoria, cópias e correcções.
- A versão local/offline não pode atribuir números fiscais definitivos sem mecanismo autorizado de controlo de séries e prevenção de duplicados.

