# Lote A3 (CB)

Base: http://127.0.0.1:5201/

**Território:** Cartões **20 e 21**; contas em dólar **12, 13, 14 e 26**; aplicações **16, 17, 18, 19 e 24**; titular **Mamita** (conta 5). Fechamento de mês **só** nessas contas.

Leia antes `PROTOCOLO.md`.

## Notas

- Fechamento de mês: feche **2026-10** de uma conta sua com filtros aplicados na lista, depois reabra; repita reabrindo **2026-09** e fechando de novo. Confira a lista e os filtros depois de cada ação.
- Faturas: abra a fatura de cada cartão, navegue entre faturas e volte; confira filtros e rolagem.
- **Filtros globais (tarefa extra deste lote, só leitura):** em **cada** tela do menu do CB, marque Dólar (ou Real+Dólar) e desmarque um grupo de conta no menu "Abrir filtros globais", clique Aplicar e navegue pelo menu para 5 outras telas: a moeda e os grupos têm de acompanhar. Registre como caso `G.<tela>`.
- Lançamentos em cartão: crie uma compra `[AUD-A3]` no cartão 20 a partir de Lançamentos filtrado no cartão, depois exclua. Use `transactions/` só para isso.

## Casos

### 1. `settings/monthly-close/`
- filtros detectados: filter_account_id, filter_year, filter_month, filter_status
- **1.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **1.1** operação `core:settings_close_month`; resposta prevista: redirect+query
- **1.2** operação `core:settings_reopen_month`; resposta prevista: redirect+query
- **1.X** outras operações visíveis na tela e não listadas acima: teste e registre como `1.X<n>`.

### 2. `banking/cards/`
- filtros detectados: nenhum no template (procure na tela)
- **2.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **2.X** outras operações visíveis na tela e não listadas acima: teste e registre como `2.X<n>`.

### 3. `banking/accounts/<int:account_id>/`
- filtros detectados: period
- **3.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **3.X** outras operações visíveis na tela e não listadas acima: teste e registre como `3.X<n>`.

