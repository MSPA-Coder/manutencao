# Lote A4 (CB)

Base: http://127.0.0.1:5201/

**Território:** Entidades **criadas por você** com prefixo `[AUD-A4]`: crie, edite e exclua a sua. **Não** altere registros existentes, exceto preferências de perfil (tema, rolagem), que você restaura ao valor original.

Leia antes `PROTOCOLO.md`.

## Notas

- Este lote roda **sozinho**, depois que A1, A2 e A3 terminaram: mexe em cadastros que os outros usam.
- **Escrita financeira (só neste lote, porque roda sozinho; dados locais de teste):** em Conciliação, filtre a **conta 8** e opere só em linhas dessa conta: conciliar, desfazer a conciliação, ignorar, criar lançamento a partir da linha (depois exclua o lançamento criado em Lançamentos) e ação em lote com 2 linhas (depois desfaça). Em Reclassificação, filtre a conta 8, reclassifique **um** lançamento para outra categoria e, em seguida, devolva-o à categoria original. Se pedir para autorizar a reabertura de um mês fechado, autorize: os dados são de teste. Em Atualizar saldo, lance a diferença numa aplicação (contas 16 a 19 ou 24) e depois exclua o lançamento gerado. Meça cada passo com a sonda.
- Gerencial: o executor A2 deixou um orçamento de teste (categoria Outros, 09/2026) sem prefixo. Retire-o pela tela de Gestão (titular Maridito) e meça a operação.
- Tabelas: aplique o filtro da tabela (titular, instituição, tipo), role, e então crie, edite e exclua a sua entidade. Também edite em linha, se houver.
- Configurações gerais (política de senha, bloqueio, projeção recorrente): **leia o valor atual, salve o MESMO valor** e meça a resposta. Não mude política.
- Permissões: selecione outro usuário no filtro, marque e desmarque uma permissão e devolva o estado original. Confira se o usuário selecionado continua selecionado.
- Banco de dados: verificação de saúde pode rodar; **otimizar não**. Registre só a existência.

## Casos

### 1. `tables/accounts/`
- filtros detectados: filter_owner_id, filter_institution_id
- **1.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **1.1** operação `banking:delete_account`; resposta prevista: HX-Redirect redirect-sem-query
- **1.2** operação `banking:update_account`; resposta prevista: HX-Redirect redirect-sem-query
- **1.3** operação `banking:create_account`; resposta prevista: HX-Redirect redirect-sem-query
- **1.X** outras operações visíveis na tela e não listadas acima: teste e registre como `1.X<n>`.

### 2. `tables/banks/`
- filtros detectados: filter_type
- **2.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **2.1** operação `banking:delete_institution`; resposta prevista: HX-Redirect redirect-sem-query
- **2.2** operação `banking:update_institution`; resposta prevista: HX-Redirect redirect-sem-query
- **2.3** operação `banking:create_institution`; resposta prevista: HX-Redirect redirect-sem-query
- **2.X** outras operações visíveis na tela e não listadas acima: teste e registre como `2.X<n>`.

### 3. `tables/categories/`
- filtros detectados: filter_type
- **3.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **3.1** operação `transactions:delete_category`; resposta prevista: HX-Redirect redirect-sem-query
- **3.2** operação `transactions:update_category`; resposta prevista: HX-Redirect redirect-sem-query
- **3.3** operação `transactions:create_category`; resposta prevista: HX-Redirect redirect-sem-query
- **3.4** operação `transactions:create_category_group`; resposta prevista: HX-Redirect redirect-sem-query
- **3.5** operação `transactions:delete_category_group`; resposta prevista: HX-Redirect redirect-sem-query
- **3.6** operação `transactions:update_category_group`; resposta prevista: HX-Redirect redirect-sem-query
- **3.X** outras operações visíveis na tela e não listadas acima: teste e registre como `3.X<n>`.

### 4. `tables/owners/`
- filtros detectados: nenhum no template (procure na tela)
- **4.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **4.1** operação `accounts:delete_owner`; resposta prevista: HX-Redirect redirect-sem-query
- **4.2** operação `accounts:update_owner`; resposta prevista: HX-Redirect redirect-sem-query
- **4.3** operação `accounts:create_owner`; resposta prevista: HX-Redirect redirect-sem-query
- **4.X** outras operações visíveis na tela e não listadas acima: teste e registre como `4.X<n>`.

### 5. `settings/`
- filtros detectados: nenhum no template (procure na tela)
- **5.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **5.1** operação `core:settings_update_password_policy`; resposta prevista: redirect-sem-query
- **5.2** operação `core:settings_update_login_lockout`; resposta prevista: redirect-sem-query
- **5.3** operação `core:settings_update_recurring_projection` (2 controles); resposta prevista: redirect-sem-query
- **5.4** operação `core:settings_run_recurring_projection`; resposta prevista: redirect-sem-query
- **5.X** outras operações visíveis na tela e não listadas acima: teste e registre como `5.X<n>`.

### 6. `settings/profile/`
- filtros detectados: nenhum no template (procure na tela)
- **6.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **6.1** operação `core:settings_update_theme`; resposta prevista: redirect-sem-query
- **6.2** operação `core:settings_update_table_scroll`; resposta prevista: redirect-sem-query
- **6.X** outras operações visíveis na tela e não listadas acima: teste e registre como `6.X<n>`.

### 7. `settings/audit-log/`
- filtros detectados: created_on, user_name, entity_name, entity_id, action
- **7.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **7.X** outras operações visíveis na tela e não listadas acima: teste e registre como `7.X<n>`.

### 8. `settings/database/`
- filtros detectados: table_name
- **8.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **8.1** operação `core:settings_health_check`; resposta prevista: redirect-sem-query
- **8.2** operação `core:settings_optimize`; resposta prevista: redirect-sem-query
- **8.X** outras operações visíveis na tela e não listadas acima: teste e registre como `8.X<n>`.

### 9. `permissions/`
- filtros detectados: user_id
- **9.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **9.1** operação `(form sem ação)` (9 controles); resposta prevista: HX-Redirect redirect-sem-query
- **9.X** outras operações visíveis na tela e não listadas acima: teste e registre como `9.X<n>`.

### 10. `banking/reconciliation/`
- filtros detectados: nenhum no template (procure na tela)
- **10.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **10.1** operação `bank_statements:bulk_action_lines` (2 controles); resposta prevista: redirect-sem-query
- **10.2** operação `bank_statements:reconcile`; resposta prevista: redirect-sem-query
- **10.3** operação `bank_statements:create_entry_from_line`; resposta prevista: redirect-sem-query
- **10.4** operação `bank_statements:ignore_line`; resposta prevista: redirect-sem-query
- **10.5** operação `bank_statements:undo_reconciliation`; resposta prevista: redirect-sem-query
- **10.X** outras operações visíveis na tela e não listadas acima: teste e registre como `10.X<n>`.

### 11. `banking/reclassification/`
- filtros detectados: conta, de, ate, categoria, banco, texto, importados
- **11.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **11.1** operação `bank_statements:reclassificacao` (2 controles); resposta prevista: redirect+query
- **11.X** outras operações visíveis na tela e não listadas acima: teste e registre como `11.X<n>`.

### 12. `banking/balance/`
- filtros detectados: nenhum no template (procure na tela)
- **12.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **12.1** operação `bank_statements:atualizar_saldo` (2 controles); resposta prevista: redirect+query?
- **12.X** outras operações visíveis na tela e não listadas acima: teste e registre como `12.X<n>`.

