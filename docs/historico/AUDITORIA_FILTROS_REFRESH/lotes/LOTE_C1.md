# Lote C1 (CRV)

Base: http://127.0.0.1:5301

**Território:** Carteira **id 1** (BRL), corretoras **1 e 2**. **DADOS REAIS (cópia da produção):** 1) Posição nova SÓ numa combinação carteira+corretora+ticker que **ainda não existe** (confira na Carteira filtrando por carteira 1 e corretora); criar numa combinação existente **funde com a posição real** (vira aporte) — se o formulário avisar de aporte, abertura anterior ou duplicata, **cancele**. 2) Nunca exclua nem encerre uma posição que existia antes; para desfazer um aporte, exclua só o **movimento** que você criou. 3) Transações encerradas: crie com `[AUD-C1]` nas notas e exclua. 4) Opções: só em contrato que a carteira não tem; exclua no fim. Quantidade 1 em tudo.

Leia antes `PROTOCOLO.md`.

## Notas

- A Carteira (`/`) é o centro: filtre por carteira, corretora e o que mais houver, e role. Então: nova posição, editar, movimento (aporte), encerrar parcial e excluir — tudo na posição que VOCÊ criou.
- Transações e Opções: filtre, opere (criar, editar, excluir; em opção também encerrar) e confira se a lista volta filtrada.
- O CRV declara que cada tela tem uma URL só: confira se os filtros aplicados **aparecem na URL** (`U`).

## Casos

### 1. `/`
- filtros detectados: portfolio_id, broker, return_days, result_mode, group_by_broker
- **1.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **1.1** operação `portfolio.rtd_service_partial`; resposta prevista: render
- **1.2** operação `portfolio.delete_position_movement`; resposta prevista: redirect-sem-query
- **1.X** outras operações visíveis na tela e não listadas acima: teste e registre como `1.X<n>`.

### 2. `/transactions`
- filtros detectados: status, broker, portfolio_id
- **2.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **2.1** operação `portfolio.delete_transaction` (2 controles); resposta prevista: redirect-sem-query
- **2.X** outras operações visíveis na tela e não listadas acima: teste e registre como `2.X<n>`.

### 3. `/options`
- filtros detectados: portfolio_id, broker
- **3.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **3.1** operação `portfolio.delete_position_movement`; resposta prevista: redirect-sem-query
- **3.X** outras operações visíveis na tela e não listadas acima: teste e registre como `3.X<n>`.

### 4. `/positions/<int:position_id>`
- filtros detectados: nenhum no template (procure na tela)
- **4.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **4.1** operação `portfolio.delete_position_movement`; resposta prevista: redirect-sem-query
- **4.X** outras operações visíveis na tela e não listadas acima: teste e registre como `4.X<n>`.

