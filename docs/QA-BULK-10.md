# Bulk 10 — Plano de validação e regressão

## Escopo
- Pesquisa global por número, tipo, nome do cliente e NUIT.
- Filtros por tipo, estado e período de registo.
- Paginação no servidor, com limite máximo de 100 registos por página.
- Isolamento por tenant nas consultas de documentos e clientes.
- Regressão dos fluxos de emissão, pagamentos, proformas e impressão.

## Casos de teste obrigatórios

| ID | Cenário | Resultado esperado |
|---|---|---|
| DOC-01 | Pesquisar número completo | Apenas documentos correspondentes da empresa activa |
| DOC-02 | Pesquisar parte do número | Correspondências parciais, sem dados de outras empresas |
| DOC-03 | Pesquisar nome de cliente | Documentos desse cliente |
| DOC-04 | Pesquisar NUIT | Documentos do cliente identificado |
| DOC-05 | Pesquisar caracteres especiais | Pedido validado; sem erro de sintaxe PostgREST |
| DOC-06 | Filtrar FT, FR, PF, NC e ND | Apenas o tipo escolhido |
| DOC-07 | Filtrar estados | Apenas os estados escolhidos |
| DOC-08 | Filtrar intervalo de datas | Período de registo inclusivo |
| DOC-09 | Navegar entre páginas | Sem duplicação nem perda de registos |
| DOC-10 | Utilizador sem sessão | HTTP 401 |
| DOC-11 | Empresa A tenta pesquisar documento da empresa B | Documento não devolvido |
| ISS-01 | Emitir FT sem autorização fiscal aplicável | Emissão recusada, sem número atribuído |
| ISS-02 | Repetir pedido idempotente de emissão | Não criar segunda emissão |
| FR-01 | Emitir FR com pagamento integral | Documento e pagamento na mesma transacção |
| FR-02 | Falha no registo do pagamento | Rollback integral da emissão |
| PAY-01 | Registar pagamento parcial | Saldo actualizado uma única vez |
| PAY-02 | Repetir operação com mesmo identificador | Sem pagamento duplicado |
| PF-01 | Converter proforma | Novo rascunho FT, proforma preservada |
| PRINT-01 | Imprimir documento A4 com várias linhas | Cabeçalho, linhas e totais legíveis |
| PRINT-02 | Imprimir em 80 mm | Conteúdo sem corte horizontal |
| PRINT-03 | Imprimir rascunho | Marca RASCUNHO visível e aviso de não emissão |

## Critério de aprovação
Não marcar qualquer cenário como aprovado sem executar o teste no ambiente correspondente e guardar evidência do resultado. A aprovação do build não substitui testes de integração nem autorização/certificação fiscal.
