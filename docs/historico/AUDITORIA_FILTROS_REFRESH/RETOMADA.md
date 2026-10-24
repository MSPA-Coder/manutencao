# Retomada (09/10/2026, limite de uso)

## Estado

- **Subagentes:** nenhum em execução. Todos os lotes (A, B, C, BC, BCK, R1) e as
  laterais (L01 a L08) terminaram e gravaram status em `status/`.
- **CB:** branch `fix/filtros-e-recargas` tem 3 commits (`e7a986d`, `2260234`,
  `5f0bc4c`). Não houve push. A última suíte deu 1025 passed.
- **SharedAuth:** branch `feat/envio-unico` tem v0.14.0 como componente
  (`966da3a`). Não houve push. A suíte deu 300 passed.
- **CRV:** branch `fix/filtros-e-recargas` foi criada e está **sem alterações**.
  As decisões do Portão 1 (CD1 a CD4) estão em `RELATORIO_CRV.md`.

## Próximo passo: corrigir o CRV

1. Criar `app/core/volta.py`, equivalente ao `core/volta.py` do CB, com a ordem
   `volta` do POST → `HX-Current-URL` → `request.args`. Ele mantém sempre
   `currency`.
2. Trocar os `redirect(url_for(...))` de escrita pelo ajudante. São 44; a lista
   está em `inventario/endpoints_escrita_crv.csv`. `_tables_redirect` fica em
   `tables.py:35`.
3. Mexer no `app/static/app.js`:
   - no submit de POST, incluir o campo oculto `volta` com o valor de
     `location.search`;
   - no clique dos links "Nova / Editar", levar a query;
   - no envio do painel global e do modo discreto, refazer os campos ocultos
     a partir da URL atual (`base.html:230` e `:253`).
4. Nos formulários de página (`position_form`, `dividend_form`, `option_form`,
   `transaction_form`, `close_*`, `position_movement_form`), guardar o `volta`
   oculto e fazer o "Cancelar" usá-lo.
5. CP3: levar corretoras, tickers, contratos e vencimentos para o padrão
   `_portfolios_response`, com fragmento no HTMX (`tables.py:300` em diante).
6. CD1: carteira e corretora acompanham o menu, com faixa de recorte.
7. Laterais:
   - L05: `options.py:150`, filtro `>= hoje`;
   - L06: `positions.py:714` e `:763`, guarda de carteira simulada;
   - L08: `quotes.py:108`, tratar como "Nenhum";
   - L09: `dividends.py:258`, tratar `IntegrityError` na `import_key`.
8. Rodar testes e `quality`, conferir no navegador e fazer o reteste com Haiku.

Depois disso vem a Fase 3, como em `PLANO.md`: restaurar os bancos,
regressão, PRs, merge e deploy com autorização.
