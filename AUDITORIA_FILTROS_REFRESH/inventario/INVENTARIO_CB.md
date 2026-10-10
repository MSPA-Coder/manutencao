# Inventário CB

- rotas de aplicação: 93
- telas GET com template: 33 (página cheia: 32)
- endpoints de escrita: 53 (sem tela de origem encontrada: 3)
- operações (tela × controle de escrita): 71
- controles de filtro: 98
- trechos JS de navegação/recarga: 10

## Respostas dos endpoints de escrita

- `redirect-sem-query`: 34
- `HX-Redirect`: 17
- `redirect+query?`: 15
- `204`: 7
- `HX-Trigger`: 5
- `redirect+query`: 4

## Telas

### `banking/accounts/<int:account_id>/` (banking:account_detail)
- filtros (1): period
- operações (0):

### `banking/attachments/` (bank_statements:attachments_view)
- filtros (0): —
- operações (2):
  - `bank_statements:create_attachment` → redirect-sem-query
  - `bank_statements:delete_attachment` → redirect-sem-query

### `banking/balance/` (bank_statements:atualizar_saldo)
- filtros (0): —
- operações (2):
  - `bank_statements:atualizar_saldo` → redirect+query? ×2

### `banking/cards/` (bank_statements:faturas)
- filtros (0): —
- operações (0):

### `banking/import/<int:batch_id>/extrato/` (bank_statements:extrato)
- filtros (0): —
- operações (0):

### `banking/import/<int:batch_id>/fatura/` (bank_statements:fatura)
- filtros (0): —
- operações (1):
  - `bank_statements:processar_fatura` → redirect-sem-query

### `banking/imports/` (bank_statements:imports_view)
- filtros (0): —
- operações (2):
  - `bank_statements:stage_imports` → 204 HX-Redirect redirect-sem-query
  - `bank_statements:undo_import` → redirect-sem-query

### `banking/imports/confirm/` (bank_statements:confirm_imports)
- filtros (0): —
- operações (1):
  - `bank_statements:process_imports` → 204 HX-Redirect redirect-sem-query

### `banking/reclassification/` (bank_statements:reclassificacao)
- filtros (7): ate, banco, categoria, conta, de, importados, texto
- operações (2):
  - `bank_statements:reclassificacao` → redirect+query ×2

### `banking/reconciliation/` (bank_statements:reconciliation_view)
- filtros (0): —
- operações (6):
  - `bank_statements:bulk_action_lines` → redirect-sem-query ×2
  - `bank_statements:create_entry_from_line` → redirect-sem-query
  - `bank_statements:ignore_line` → redirect-sem-query
  - `bank_statements:reconcile` → redirect-sem-query
  - `bank_statements:undo_reconciliation` → redirect-sem-query

### `banking/statements/` (bank_statements:extratos)
- filtros (0): —
- operações (0):

### `banking/status/` (bank_statements:situacao_das_contas)
- filtros (0): —
- operações (0):

### `change-password/` (accounts:change_password)
- filtros (0): —
- operações (1):
  - `` → HX-Redirect redirect-sem-query

### `dashboard/` (dashboard:dashboard)
- filtros (7): account_id, categorias, filter_type, institution_id, mode, owner_id, period
- operações (0):

### `dashboard/content/` (dashboard:dashboard_content)
- filtros (7): account_id, categorias, filter_type, institution_id, mode, owner_id, period
- operações (0):

### `management/` (management:management_view)
- filtros (4): account_id, institution_id, month, owner_id
- operações (8):
  - `management:assign_project` → redirect+query?
  - `management:assign_tag` → redirect+query?
  - `management:create_project` → redirect+query?
  - `management:create_tag` → redirect+query?
  - `management:retire_budget` → redirect+query?
  - `management:retire_project` → redirect+query?
  - `management:retire_tag` → redirect+query?
  - `management:save_budget` → redirect+query?

### `operations/` (transactions:operations_view)
- filtros (4): end, operation_type, start, status
- operações (0):

### `permissions/` (core:permissions)
- filtros (1): user_id
- operações (9):
  - `` → HX-Redirect redirect-sem-query ×9

### `reports/account-position/` (reports:account_position_view)
- filtros (4): institution_id, mode, owner_id, period
- operações (0):

### `reports/annual-planning/` (reports:annual_planning_view)
- filtros (7): account_ids, agrupar, layout, mode, owner_ids, reference_month, show_descriptions
- operações (0):

### `reports/projections/` (reports:projections_view)
- filtros (6): account_id, end_month, institution_id, mode, owner_id, start_month
- operações (0):

### `reports/upcoming-movements/` (reports:upcoming_movements_view)
- filtros (6): account_id, end_date, institution_id, mode, owner_id, start_date
- operações (0):

### `settings/` (core:settings_home)
- filtros (0): —
- operações (5):
  - `core:settings_run_recurring_projection` → redirect-sem-query
  - `core:settings_update_login_lockout` → redirect-sem-query
  - `core:settings_update_password_policy` → redirect-sem-query
  - `core:settings_update_recurring_projection` → redirect-sem-query ×2

### `settings/audit-log/` (core:settings_audit_log)
- filtros (5): action, created_on, entity_id, entity_name, user_name
- operações (0):

### `settings/database/` (core:settings_database)
- filtros (1): table_name
- operações (2):
  - `core:settings_health_check` → redirect-sem-query
  - `core:settings_optimize` → redirect-sem-query

### `settings/monthly-close/` (core:settings_monthly_close)
- filtros (4): filter_account_id, filter_month, filter_status, filter_year
- operações (2):
  - `core:settings_close_month` → redirect+query
  - `core:settings_reopen_month` → redirect+query

### `settings/profile/` (core:settings_profile)
- filtros (0): —
- operações (2):
  - `core:settings_update_table_scroll` → redirect-sem-query
  - `core:settings_update_theme` → redirect-sem-query

### `tables/accounts/` (banking:accounts_view)
- filtros (2): filter_institution_id, filter_owner_id
- operações (3):
  - `banking:create_account` → HX-Redirect redirect-sem-query
  - `banking:delete_account` → HX-Redirect redirect-sem-query
  - `banking:update_account` → HX-Redirect redirect-sem-query

### `tables/banks/` (banking:institutions_view)
- filtros (1): filter_type
- operações (3):
  - `banking:create_institution` → HX-Redirect redirect-sem-query
  - `banking:delete_institution` → HX-Redirect redirect-sem-query
  - `banking:update_institution` → HX-Redirect redirect-sem-query

### `tables/categories/` (transactions:categories_view)
- filtros (1): filter_type
- operações (6):
  - `transactions:create_category` → HX-Redirect redirect-sem-query
  - `transactions:create_category_group` → HX-Redirect redirect-sem-query
  - `transactions:delete_category` → HX-Redirect redirect-sem-query
  - `transactions:delete_category_group` → HX-Redirect redirect-sem-query
  - `transactions:update_category` → HX-Redirect redirect-sem-query
  - `transactions:update_category_group` → HX-Redirect redirect-sem-query

### `tables/owners/` (accounts:owners_view)
- filtros (0): —
- operações (3):
  - `accounts:create_owner` → HX-Redirect redirect-sem-query
  - `accounts:delete_owner` → HX-Redirect redirect-sem-query
  - `accounts:update_owner` → HX-Redirect redirect-sem-query

### `transactions/` (transactions:transactions_view)
- filtros (8): account_id, filter_category, filter_date, filter_type, institution_id, mode, owner_id, period
- operações (5):
  - `` → HX-Redirect redirect-sem-query
  - `transactions:mark_realized` → 204 HX-Trigger redirect+query?
  - `transactions:mark_unrealized` → 204 HX-Trigger redirect+query?
  - `transactions:transaction_edit` → 204 HX-Trigger redirect+query?
  - `transactions:transaction_new` → 204 HX-Trigger redirect+query?

## Endpoints de escrita sem tela de origem encontrada (achar no navegador)

- `accounts:change_password` change-password/ → redirect+query
- `core:permissions` permissions/ → redirect+query?
- `transactions:transaction_delete` transaction/delete/<int:tx_id>/ → 204 HX-Trigger redirect+query?
