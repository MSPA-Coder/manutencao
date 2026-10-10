# Lote A2 (CB)

Base: http://127.0.0.1:5201/

**Território:** Titular **Maridito** (owner_id=1), contas **1, 7, 8, 9, 10 e 11**. Gerencial: crie só projetos e tags `[AUD-A2]`.

Leia antes `PROTOCOLO.md`.

## Notas

- Upload de arquivo (importar extrato, anexo) **não** é possível neste navegador: registre `NAO_TESTAVEL` e siga. Operações sobre linhas já importadas (conciliar, ignorar, criar lançamento a partir da linha, desfazer) são testáveis se a linha for de conta do seu território.
- Desfazer importação inteira: **não** faça (é destrutivo e global ao lote importado). Só registre que existe.
- Planejamento anual tem seletor próprio de contas e titulares (múltiplo): marque várias e confira se sobrevivem.

## Casos

### 1. `management/`
- filtros detectados: owner_id, institution_id, account_id, month
- **1.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **1.1** operação `management:create_tag`; resposta prevista: redirect+query?
- **1.2** operação `management:create_project`; resposta prevista: redirect+query?
- **1.3** operação `management:save_budget`; resposta prevista: redirect+query?
- **1.4** operação `management:assign_tag`; resposta prevista: redirect+query?
- **1.5** operação `management:assign_project`; resposta prevista: redirect+query?
- **1.6** operação `management:retire_tag`; resposta prevista: redirect+query?
- **1.7** operação `management:retire_project`; resposta prevista: redirect+query?
- **1.8** operação `management:retire_budget`; resposta prevista: redirect+query?
- **1.X** outras operações visíveis na tela e não listadas acima: teste e registre como `1.X<n>`.

### 2. `banking/balance/`
- filtros detectados: nenhum no template (procure na tela)
- **2.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **2.1** operação `bank_statements:atualizar_saldo` (2 controles); resposta prevista: redirect+query?
- **2.X** outras operações visíveis na tela e não listadas acima: teste e registre como `2.X<n>`.

### 3. `banking/reclassification/`
- filtros detectados: conta, de, ate, categoria, banco, texto, importados
- **3.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **3.1** operação `bank_statements:reclassificacao` (2 controles); resposta prevista: redirect+query
- **3.X** outras operações visíveis na tela e não listadas acima: teste e registre como `3.X<n>`.

### 4. `banking/reconciliation/`
- filtros detectados: nenhum no template (procure na tela)
- **4.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **4.1** operação `bank_statements:bulk_action_lines` (2 controles); resposta prevista: redirect-sem-query
- **4.2** operação `bank_statements:reconcile`; resposta prevista: redirect-sem-query
- **4.3** operação `bank_statements:create_entry_from_line`; resposta prevista: redirect-sem-query
- **4.4** operação `bank_statements:ignore_line`; resposta prevista: redirect-sem-query
- **4.5** operação `bank_statements:undo_reconciliation`; resposta prevista: redirect-sem-query
- **4.X** outras operações visíveis na tela e não listadas acima: teste e registre como `4.X<n>`.

### 5. `banking/attachments/`
- filtros detectados: nenhum no template (procure na tela)
- **5.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **5.1** operação `bank_statements:create_attachment`; resposta prevista: redirect-sem-query
- **5.2** operação `bank_statements:delete_attachment`; resposta prevista: redirect-sem-query
- **5.X** outras operações visíveis na tela e não listadas acima: teste e registre como `5.X<n>`.

### 6. `banking/imports/`
- filtros detectados: nenhum no template (procure na tela)
- **6.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **6.1** operação `bank_statements:stage_imports`; resposta prevista: 204 HX-Redirect redirect-sem-query
- **6.2** operação `bank_statements:undo_import`; resposta prevista: redirect-sem-query
- **6.X** outras operações visíveis na tela e não listadas acima: teste e registre como `6.X<n>`.

### 7. `banking/statements/`
- filtros detectados: nenhum no template (procure na tela)
- **7.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **7.X** outras operações visíveis na tela e não listadas acima: teste e registre como `7.X<n>`.

### 8. `banking/status/`
- filtros detectados: nenhum no template (procure na tela)
- **8.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **8.X** outras operações visíveis na tela e não listadas acima: teste e registre como `8.X<n>`.

### 9. `reports/account-position/`
- filtros detectados: period, mode, owner_id, institution_id
- **9.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **9.X** outras operações visíveis na tela e não listadas acima: teste e registre como `9.X<n>`.

### 10. `reports/annual-planning/`
- filtros detectados: reference_month, layout, mode, owner_ids, account_ids, show_descriptions, agrupar
- **10.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **10.X** outras operações visíveis na tela e não listadas acima: teste e registre como `10.X<n>`.

