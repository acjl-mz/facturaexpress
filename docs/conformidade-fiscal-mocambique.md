# FacturaExpress — Matriz de conformidade fiscal (Moçambique)

**Estado da implementação:** Fase 7 em desenvolvimento. A emissão fiscal efectiva permanece bloqueada.

## Diplomas-base identificados

- **Lei n.º 10/2025, de 29 de Dezembro** — altera o Código do IVA. Deve ser lida com a republicação no BR n.º 248, Suplemento n.º 1.
- **Lei n.º 9/2025, de 29 de Dezembro** — altera e republica o regime do ISPC, com vigência indicada a partir de 1 de Janeiro de 2026.
- **Lei n.º 11/2025 e Lei n.º 12/2025** — alterações aos Códigos do IRPS e IRPC; relevantes para retenções e enquadramento, mas não devem ser convertidas automaticamente em taxas de imposto sobre linhas de factura.
- **Regulamentação fiscal aprovada em 29 de Setembro de 2026** — o Conselho de Ministros aprovou alterações aos regulamentos do IVA, IRPS e IRPC e o novo Regulamento do ISPC. É indispensável obter os textos publicados no Boletim da República e parametrizar as respectivas regras operacionais antes de fechar a matriz fiscal.\n- **Aviso n.º 40/AT/DGI/2025** — procedimento relacionado com programas de facturação e comunicação de dados, a confirmar na versão integral e instruções operacionais da AT.
- **Decreto n.º 7/2008** e alterações — Regulamento do Código do IVA; confirmar disposições ainda vigentes após as alterações legislativas posteriores.

## Regras de desenho implementadas

1. Rascunhos não recebem número fiscal nem data de emissão.
2. A numeração é atribuída apenas dentro de uma transacção de emissão, com série activa e bloqueio concorrente.
3. O número, a série, a data e um snapshot dos dados do emitente, adquirente e linhas ficam registados na emissão.
4. Documentos emitidos não podem ser apagados nem ter conteúdo fiscal alterado. O estado de liquidação pode evoluir por recebimentos registados.
5. A emissão exige uma autorização registada para o tenant e para a versão exacta do software.
6. A Factura-Recibo permanece bloqueada até existir captura de pagamento integrada atomicamente.
7. A emissão permanece bloqueada para tipos documentais sem fluxo implementado.

## Pontos que exigem validação formal antes de produção

- Certificação/homologação do FacturaExpress pela Autoridade Tributária e procedimento de submissão aplicável ao software.
- Layout e elementos obrigatórios por tipo documental, incluindo referências legais, menções de IVA, isenções, retenções e documentos rectificativos.
- Regras de comunicação electrónica, formato, frequência, autenticação, ambiente de testes e resposta da AT.
- Excepções legalmente permitidas para identificação de adquirente/consumidor final.
- Séries, exercício, reinício/continuidade de numeração, documentos anulados e trilho de auditoria.
- Taxas e regimes de IVA em vigor, incluindo taxa normal, reduzidas, taxa zero, isenções e regras de incidência específicas.
- ISPC: tratar como imposto do regime/volume de negócios, e não como uma taxa de IVA por linha de factura. A Lei n.º 9/2025 e o novo regulamento aprovado em Setembro de 2026 exigem parametrização por actividade e escalão; não aplicar automaticamente à linha sem modelo fiscal próprio.
- IRPS/IRPC e retenções: regras separadas, parametrizadas por natureza de pagamento, beneficiário e fundamento legal.

## Fontes oficiais de referência

- Imprensa Nacional — BR n.º 248, Suplemento n.º 1, de 29.12.2025: https://www.inm.gov.mz/pt-br/content/suplemento-n%C2%BA-1-de-291225-pag-2180-1-20-br-n%C2%BA-248-boletim-da-rep%C3%BAblica-i-serie
- Autoridade Tributária — Legislação Fiscal: https://www.at.gov.mz/legislacao/fiscal
- Presidência da República — comunicado sobre a alteração do Código do IVA: https://www.presidencia.gov.mz/wp-content/uploads/2025/05/CI_PR-promulga-Lei-que-altera-o-Codigo-sobre-o-IVA.pdf

> Este documento é uma matriz técnica de trabalho, não um parecer jurídico nem uma confirmação de homologação. A parametrização fiscal final deve ser confrontada com os diplomas integrais e instruções oficiais aplicáveis na data de cada operação.
