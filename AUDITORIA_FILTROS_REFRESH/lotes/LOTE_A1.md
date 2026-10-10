# Lote A1 (CB)

Base: http://127.0.0.1:5201/

**Território:** Titular **Esposita** (owner_id=2): contas 3, 4, 6, 15 e 22. Lançamentos novos só em 2026-11 a 2027-03 dessas contas.

Leia antes `PROTOCOLO.md`.

## Notas

- Lançamentos é o centro deste lote: teste **cada** ação da linha (Editar inline, Excluir com cada escopo oferecido, Realizar, Desfazer realização, Ver operação) e o **Novo lançamento** (simples, parcelado, recorrente, transferência entre as SUAS contas).
- Em Lançamentos combine os filtros de contexto (período, status, titular, instituição, conta) com os **filtros de coluna** (data, tipo, categoria) antes de operar: são dois grupos e podem se perder separados.
- Dashboard e Relatórios: além dos filtros, siga os links e drilldowns que levam a Lançamentos e confira se chegam com os filtros (titular, conta, período, moeda e grupos).

## Casos

### 1. `transactions/`
- filtros detectados: filter_date, filter_type, filter_category, period, mode, owner_id, institution_id, account_id
- **1.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **1.1** operação `transactions:transaction_edit`; resposta prevista: 204 HX-Trigger redirect+query?
- **1.2** operação `transactions:transaction_new`; resposta prevista: 204 HX-Trigger redirect+query?
- **1.3** operação `transactions:mark_realized`; resposta prevista: 204 HX-Trigger redirect+query?
- **1.4** operação `transactions:mark_unrealized`; resposta prevista: 204 HX-Trigger redirect+query?
- **1.5** operação `(form sem ação)`; resposta prevista: HX-Redirect redirect-sem-query
- **1.X** outras operações visíveis na tela e não listadas acima: teste e registre como `1.X<n>`.

### 2. `operations/`
- filtros detectados: start, end, operation_type, status
- **2.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **2.X** outras operações visíveis na tela e não listadas acima: teste e registre como `2.X<n>`.

### 3. `dashboard/`
- filtros detectados: filter_type, categorias, period, mode, owner_id, institution_id, account_id
- **3.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **3.X** outras operações visíveis na tela e não listadas acima: teste e registre como `3.X<n>`.

### 4. `reports/upcoming-movements/`
- filtros detectados: start_date, end_date, mode, owner_id, institution_id, account_id
- **4.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **4.X** outras operações visíveis na tela e não listadas acima: teste e registre como `4.X<n>`.

### 5. `reports/projections/`
- filtros detectados: start_month, end_month, mode, owner_id, institution_id, account_id
- **5.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **5.X** outras operações visíveis na tela e não listadas acima: teste e registre como `5.X<n>`.

