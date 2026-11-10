# Desenho funcional — FacturaExpress

## 1. Objectivo e utilizadores

O FacturaExpress permite a uma organização preparar, emitir quando legalmente autorizada, imprimir e acompanhar documentos de facturação. Os utilizadores principais são:
- **Administrador/Proprietário:** configura a organização, utilizadores, séries e permissões.
- **Emissor:** prepara documentos e executa operações autorizadas de facturação.
- **Financeiro:** acompanha pagamentos, saldos e conta corrente.
- **Contabilista:** consulta documentos e informação fiscal, dentro das permissões atribuídas.

O produto é multiempresa. Todos os registos comerciais e documentais devem pertencer a uma organização (tenant), e a segurança deve ser aplicada no servidor e por RLS.

## 2. Fluxo principal

1. O utilizador entra no sistema e selecciona a organização activa.
2. Abre **Nova factura**.
3. Selecciona ou regista o cliente.
4. Adiciona produtos/serviços do catálogo ou descreve uma linha manual.
5. Introduz quantidade, unidade, preço e desconto.
6. O sistema calcula os valores no servidor e apresenta uma pré-visualização actualizada.
7. O utilizador guarda o documento como rascunho.
8. O utilizador reabre, corrige e valida os dados.
9. Se todas as condições legais e de autorização estiverem satisfeitas, o perfil autorizado pode emitir; caso contrário, o sistema mantém o documento como rascunho e explica o bloqueio.
10. O utilizador consulta, guarda em PDF e imprime o documento.
11. Quando aplicável, regista pagamentos e acompanha o saldo.

## 3. Ecrãs e funcionalidades

### 3.1 Painel inicial
- Acção principal: **Nova factura**.
- Atalhos: Documentos, Clientes, Produtos/Serviços e Pagamentos.
- Indicadores reais: total facturado, por receber, documentos do período e clientes activos.
- Filtros por período e organização/estabelecimento.
- Estados vazios úteis; não apresentar números fictícios em ambiente real.

### 3.2 Lista de documentos
- Pesquisa por número, cliente, NUIT ou referência.
- Filtros por tipo, estado, data e intervalo de valores.
- Ordenação por data e número.
- Acções conforme estado e permissão: abrir, continuar rascunho, imprimir, exportar PDF, consultar eventos.
- Rascunhos identificados inequivocamente como **RASCUNHO**.
- Documentos emitidos não apresentam acções de edição ou eliminação.

### 3.3 Formulário de factura
**Cabeçalho**
- Tipo documental permitido.
- Cliente/adquirente.
- Data e vencimento, quando aplicável.
- Moeda e referência interna.
- Observações.

**Linhas**
- Produto/serviço opcional do catálogo.
- Descrição obrigatória.
- Quantidade positiva.
- Unidade.
- Preço unitário não negativo.
- Desconto limitado ao valor bruto da linha.
- Classificação fiscal seleccionada de regras activas e aprovadas.
- Prova/fundamento adicional quando exigido pela regra.

**Resumo**
- Subtotal bruto.
- Descontos.
- Bases tributáveis por classificação.
- Impostos por taxa/código.
- Retenções, quando aplicáveis.
- Total do documento e total a pagar.

**Acções**
- Guardar rascunho.
- Guardar e continuar.
- Cancelar.
- Pré-visualizar.
- Validar para emissão, quando habilitado.

Os cálculos finais são sempre recalculados/validados no servidor. O browser nunca é a fonte de verdade para valores fiscais ou numeração.

### 3.4 Detalhe e impressão
- Mostrar estado e identificação do documento.
- Pré-visualização de impressão sem navegação, botões ou menus.
- Suportar paginação de tabelas longas, cabeçalho repetido e bloco de totais sem cortes.
- Mostrar dados do emitente/adquirente e discriminação fiscal.
- Permitir PDF e impressão.
- Utilizar a configuração visual da organização (logótipo, cores, cabeçalho, rodapé, campos visíveis) sem remover nem alterar campos legalmente obrigatórios.
- Rascunhos têm marca de água e não podem ser confundidos com documentos fiscais emitidos.
- PDF final, quando arquivado, deve ser associado ao documento e guardado em Storage privado com política por tenant.

### 3.5 Clientes
- Nome/denominação, NUIT, endereço, e-mail e telefone.
- Estado activo/inactivo.
- Pesquisa por nome e NUIT.
- Histórico documental e saldo.
- Validação de duplicados, sem impedir casos legitimamente distintos.

### 3.6 Produtos e serviços
- Código interno, descrição, unidade, preço e classificação fiscal.
- Estado activo/inactivo.
- Pesquisa e selecção rápida no formulário.
- O preço do catálogo é uma sugestão inicial; o preço gravado na linha do documento é um snapshot e não muda quando o catálogo for actualizado.

### 3.7 Pagamentos
- Registo de pagamento associado a documento elegível.
- Valor, data, meio, referência e notas.
- Pagamentos parciais sucessivos.
- Saldo actualizado de forma transaccional.
- Comprovativo interno claramente identificado; não o apresentar como recibo fiscal sem validação e autorização.

## 4. Modelo de estados

- **draft:** documento interno editável.
- **pending_validation:** opcional, se existir revisão por outro utilizador.
- **issued:** documento emitido; imutável.
- **partially_paid:** documento emitido com saldo por liquidar.
- **paid:** documento totalmente liquidado.
- **voided/corrected:** apenas segundo fluxo legal e regras aprovadas; nunca apagar o histórico.

As transições devem ser controladas por API/função transaccional, com autorização por papel e registo em eventos/auditoria.

## 5. Regras de cálculo e integridade

- Valores monetários em MZN na configuração actual.
- Quantidades e preços aceitam precisão controlada; arredondamento monetário a duas casas, segundo regra validada.
- O servidor calcula: bruto da linha, desconto, base tributável, imposto e total.
- O total do documento é a soma das linhas e encargos aplicáveis, nunca um valor enviado pelo cliente sem validação.
- Cada regra fiscal tem código, taxa, natureza, vigência e estado de validação.
- Não presumir taxas, isenções ou retenções apenas pela descrição do artigo.
- Regimes fiscais incompatíveis com determinada taxa devem bloquear a operação e explicar a razão.
- Operações idempotentes devem evitar duplicação em reenvio ou falha de rede.
- Documentos finalizados guardam snapshot dos dados e regras aplicadas.

## 6. Personalização visual por organização

A personalização é uma camada de apresentação separada do conteúdo e das regras fiscais. Cada organização poderá configurar um ou mais modelos, seleccionar o padrão e definir:
- Logótipo e identidade visual.
- Cabeçalho, rodapé e cores.
- Disposição e alinhamento dos blocos.
- Campos de contacto que pretende exibir.
- Texto comercial adicional permitido.

O sistema mantém um conjunto de campos fiscais obrigatórios que não podem ser removidos. A personalização não pode alterar valores, taxas, numeração, datas ou dados de origem.

## 7. Segurança e multiempresa

- Todas as APIs exigem sessão válida.
- Tenant é resolvido no servidor; não confiar num tenant_id enviado pelo browser.
- RLS em todas as tabelas expostas.
- Papel e permissão verificados em cada operação sensível.
- Séries e emissão executadas transaccionalmente no servidor.
- Eventos de criação, edição, emissão, impressão/exportação, pagamento e rectificação auditáveis.
- Storage privado e caminhos isolados por tenant.
- Nunca expor service-role keys no browser.

## 8. Critérios de aceitação do núcleo

1. Um utilizador autorizado cria uma factura com cliente e várias linhas.
2. Pode adicionar, editar e remover linhas antes de guardar.
3. Os totais apresentados coincidem com os valores recalculados no servidor.
4. O rascunho fica persistido e pode ser reaberto.
5. Um utilizador de outra organização não consegue consultar ou alterar o documento.
6. Um rascunho não recebe número fiscal nem é apresentado como emitido.
7. Um documento emitido não pode ser editado nem eliminado.
8. A pré-visualização e impressão não incluem controlos da aplicação.
9. A impressão de documentos longos não corta linhas, totais ou cabeçalhos.
10. A personalização visual não remove os elementos documentais obrigatórios.
11. Falhas/reenvios não criam documentos ou pagamentos duplicados.
12. Sem autorização aplicável, a emissão continua bloqueada com mensagem clara.

## 9. Fora do âmbito imediato

- Editor gráfico avançado de templates como prioridade do produto.
- Integração directa com bancos ou gateways de pagamento.
- Emissão fiscal offline com numeração local não autorizada.
- Alegação de certificação/homologação ou submissão à AT sem prova e integração formal.
- Migração para uma base de dados externa ao Supabase.
