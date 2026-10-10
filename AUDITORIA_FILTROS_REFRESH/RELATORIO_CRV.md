# Relatório CRV: filtros perdidos e recargas desnecessárias

09/10/2026. A base é a cópia da produção das 06:00, já sem a carteira Simulada,
excluída a pedido. O inventário tem 33 telas e 65 operações.

- **Medição:** 4 executores (C1 a C4, 144 linhas).
- **Contestação:** 3 adversários.
  - BC1 e BC2 reproduziram 75 casos às cegas: 42 achados reproduzidos, 8 falsos
    negativos de C, sem causa nova.
  - BCK atacou corridas: nenhuma corrida de filtro; achou o L09.

Todo achado abaixo tem a **causa conferida no código**.

## O que já funciona (modelo a seguir)

- **Os filtros das telas** (Carteira, Transações, Opções, Proventos, Performance
  e Exposição) trocam só a região de resultados, por HTMX. A URL acompanha
  (`hx-replace-url` com URL canônica). Não houve corrida em filtro em voo nem
  com duas abas (BCK K2 a K4).
- **Carteiras** (`/tables/portfolios`): incluir, editar e associar ticker trocam
  só a lista, sem recarga e sem perder filtro (`_portfolios_response` devolve
  fragmento no HTMX). É o padrão a levar para as outras tabelas.
- **"Voltar" do navegador** sai da tela por decisão documentada
  (`app/templates/index.html:2`), a mesma adotada no CB.

## Os padrões (causa raiz) e a correção proposta

### CP1. Escrita volta para a lista sem query
**Sintoma:** em quase toda escrita (posição, transação, opção, provento,
corretora, ticker, contrato, vencimento), salvar ou excluir recarrega a página
e volta para a lista **sem filtros e sem a moeda**. Fontes: C1, C2, C4, BC1
(10 casos), BC2 e BCK K2.

**Causa:** 44 endpoints terminam em `redirect(url_for(...))` sem query, por
exemplo `app/routes/dividends.py:263`, `options.py:315` e `_tables_redirect`
(`tables.py:35`).

**Correção:** um ajudante de volta, equivalente ao `core/volta.py` do CB, que
devolve a lista com a query viva da tela de origem, sempre com a moeda. O
destino continua sendo resolvido pelo servidor.

### CP2. Os formulários são páginas separadas, e o caminho até eles perde os filtros
**Sintoma:** "Nova posição", "Novo provento", "Editar" e "Cancelar" levam ao
formulário ou de volta à lista **sem os filtros** (C1 X-1, C2 1.X3 e 1.X4, C3
4.P, BC2 R001).

**Causa:** os links são `url_for(...)` fixos, e as telas de formulário
(`position_form.html`, `dividend_form.html`, `option_form.html`,
`transaction_form.html`) não sabem de onde vieram.

**Correção:** a query da lista viaja como `volta`.
- O link que abre o formulário leva a query atual: o `app.js` completa no
  clique, como o CB faz com os globais.
- O formulário guarda o `volta` num campo oculto.
- "Cancelar" e o retorno do POST usam o `volta`.

### CP3. As tabelas cadastrais recarregam
**Sintoma:** corretoras, tickers, contratos e vencimentos recarregam a página a
cada escrita (C4 1.x a 4.x).

**Correção:** o padrão de Carteiras, com o fragmento da lista no HTMX, mais o
CP1 no POST sem HTMX.

### CP4. O painel global e o modo discreto desfazem filtros trocados depois
**Sintoma:** "Aplicar" moeda descarta a corretora (C2 1.F, BCK K2). O modo
discreto volta para a URL da carga da página.

**Causa:** os campos ocultos do painel saem de `request.args` na carga
(`base.html:230`), e o `next` do modo discreto sai de `request.full_path`
(`:253`). O cabeçalho não acompanha as trocas por HTMX. É **o mesmo defeito**
achado no CB pelo reteste.

**Correção:** no envio, refazer os campos a partir da URL atual. É a mesma
solução aplicada e testada no CB.

### CP5. Expandir uma linha troca a lista inteira
**Sintoma:** expandir os movimentos de uma posição troca o bloco
`portfolio-results` inteiro (C1 X-2, código M). A expansão some ao trocar um
filtro (BCK K5, código S).

**Causa:** a expansão fica fora da URL **de propósito** (`index.html:14`).

**Correção:** prioridade baixa. Trocar só a linha é melhoria de desenho, não
defeito.

### CP6. Envio duplicado de provento dá erro 500 (L09)
**Causa:** `create_dividend` não trata o `IntegrityError` da chave única
`import_key`.

**Correção:** tratar como "já cadastrado", mais a trava de envio único da
SharedAuth 0.14.

## Laterais

| Id | Situação |
|---|---|
| L03 | Simulada fora de Performance e Exposição: intencional. Com a Simulada excluída, sobra só ajustar a doc |
| L04 | Descartado (erro de clique do agente) |
| L05 | **Defeito**: o seletor de nova opção oferece contrato vencido. Filtrar `>= hoje` na criação e manter o contrato atual na edição |
| L06 | Dados apagados em produção a pedido. A brecha de código (editar ou excluir movimento de carteira simulada) continua: proteção pequena |
| L07 | Indeterminado: provável erro de leitura do agente. Reproduzir na Fase 3 |
| L08 | **Defeito**: benchmark fora da lista de candidatos dá 404, inclusive ao trocar o **filtro de moeda**, e a tela fica parada. Tratar como "Nenhum" |
| L09 | **Defeito**: duplo envio de provento dá 500 (CP6) |
| BC2 | "Transação de ação sem excluir na lista" e "botão Adicionar sem clique": conferir na correção. O "modo discreto ligou sozinho" é preferência do usuário, válida para todas as abas |

## Comportamento esperado (não é defeito)

- A moeda na URL ausente equivale a BRL.
- A expansão de linha fica fora da URL, por desenho.
- O "voltar" sai da tela, por desenho.
- O F5 de um formulário de página recarrega.

## Portão 1 do CRV: decidido em 09/10/2026

- **CD1, sim:** carteira e corretora acompanham o menu entre as telas do mesmo
  seletor.
- **CD2:** os formulários continuam páginas separadas e passam a carregar a
  volta.
- **CD3, sim:** as tabelas cadastrais adotam o padrão de Carteiras.
- **CD4, sim:** fechar a brecha do L06.

## Decisões para você (Portão 1 do CRV)

| | Pergunta | Recomendação |
|---|---|---|
| **CD1** | Carteira e corretora acompanham o menu entre as telas do mesmo seletor (Carteira, Transações, Opções, Proventos, Performance, Exposição), como titular e conta no CB? | **Sim**, mesmo contrato: só na URL e com faixa de recorte |
| **CD2** | Os formulários continuam páginas separadas (só carregando a volta, CP2) ou passam a abrir na própria lista, sem sair dela? | **Páginas separadas com volta**: resolve a perda de filtro com risco baixo. Formulário na lista é refazer quatro telas e fica para depois |
| **CD3** | As tabelas cadastrais adotam o padrão de Carteiras (fragmento, sem recarga)? | **Sim** |
| **CD4** | Fechar a brecha de movimento em carteira simulada (L06), mesmo sem simulada hoje? | **Sim**: proteção pequena |
