# Hipóteses do coordenador (verificadas no código; NÃO entregar aos adversários)

Cruzar com os achados dos executores na rodada C. Cada uma tem a causa no código;
falta o sintoma medido no navegador.

## CB

- **H-CB1:** as tabelas cadastrais (contas, bancos, categorias, titulares) chamam
  `_respond`, que no HTMX devolve `HX-Redirect` para `reverse(nome)` **sem
  query**. Esperado: R e F em `filter_owner_id`, `filter_institution_id` e
  `filter_type`, e possivelmente perda de `currency` e `grupos`. Onde:
  `banking/views.py:325`; o mesmo padrão em `transactions/views.py:553` e
  `accounts/views`.
- **H-CB2:** `_redirect_to_transactions` preserva só `TRANSACTIONS_QUERY_PARAMS`
  (`transactions/services.py:2016`), sem `currency` nem `grupos`. Realizar,
  desfazer, editar ou criar fora do HTMX volta com R e P (moeda e grupos
  perdidos). Medido por mim antes da rodada: realizar faz **R** com a URL
  preservada (sem moeda, porque a moeda não estava na URL).
- **H-CB3:** no ramo HTMX, Lançamentos responde 204 com `HX-Trigger:
  tableRefresh`, e o `tbody` refaz o GET com a URL congelada na renderização
  (`templates/transactions/_table_body.html:50`, `request.GET.urlencode`). Se o
  `tbody` veio de uma troca anterior, com filtros de coluna alterados por HTMX,
  a URL congelada pode ser a velha. Esperado: F ou C nos filtros de coluna
  depois de trocar o filtro e realizar.
- **H-CB4:** o Gerencial volta por `redirect_qs` ou `QUERY_STRING`
  (`management/views.py:20`). É provável que preserve, mas conferir se
  `redirect_qs` está nos formulários.
- **H-CB5:** as configurações (`core/views.py`) voltam por `redirect('core:...')`
  sem query. Isso só pesa se a tela tiver filtros (`settings/database` tem
  `table_name`).
- **Observação de domínio, fora do escopo:** desfazer a realização de um
  lançamento com vencimento futuro (1382, vence em 09/11/2026) o deixou como
  `vencidos`, e o diálogo avisa "voltará para Vencidos". Conferir com o
  mantenedor.

## CRV

- **H-CRV1:** os GET de filtro por HTMX recebem `HX-Replace-Url` canônico
  (`app/__init__.py`, `_canonizar_url`), então a URL deveria acompanhar o filtro
  (não deveria haver U).
- **H-CRV2:** 44 endpoints de escrita voltam por `redirect(url_for(...))` sem
  query, por exemplo `_tables_redirect` (`app/routes/tables.py:35`) e
  dividendos, posições e opções. Quando o formulário é uma página separada
  (`position_form.html`, `option_form.html`, `dividend_form.html`), a volta cai
  na tela sem filtros. Esperado: F em quase toda operação.
- **H-CRV3:** Carteiras usa `_portfolios_response`, que devolve fragmento no
  HTMX. Provavelmente OK e serve de modelo.
