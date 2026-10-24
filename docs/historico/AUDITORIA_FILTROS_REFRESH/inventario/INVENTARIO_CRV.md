# Inventário CRV

- rotas de aplicação: 91
- telas GET com template: 36 (página cheia: 33)
- endpoints de escrita: 55 (sem tela de origem encontrada: 10)
- operações (tela × controle de escrita): 65
- controles de filtro: 24
- trechos JS de navegação/recarga: 1

## Respostas dos endpoints de escrita

- `redirect-sem-query`: 44
- `redirect+query`: 5
- `render`: 5
- `?`: 2

## Telas

### `/` (portfolio.index)
- filtros (5): broker, group_by_broker, portfolio_id, result_mode, return_days
- operações (2):
  - `portfolio.delete_position_movement` → redirect-sem-query
  - `portfolio.rtd_service_partial` → render

### `/analysis/exposure-asset` (portfolio.exposure_asset)
- filtros (2): broker, portfolio_id
- operações (0):

### `/analysis/exposure-broker` (portfolio.exposure_broker)
- filtros (2): broker, portfolio_id
- operações (0):

### `/analysis/exposure-market` (portfolio.exposure_market)
- filtros (2): broker, portfolio_id
- operações (0):

### `/data-status` (portfolio.data_status)
- filtros (0): —
- operações (0):

### `/dividends` (portfolio.dividends)
- filtros (1): broker
- operações (0):

### `/dividends/<int:dividend_id>/edit` (portfolio.edit_dividend)
- filtros (0): —
- operações (2):
  - `portfolio.delete_dividend` → redirect-sem-query
  - `portfolio.update_dividend` → redirect-sem-query

### `/dividends/import` (portfolio.import_dividends)
- filtros (0): —
- operações (1):
  - `portfolio.import_dividends` → redirect-sem-query

### `/dividends/new` (portfolio.new_dividend)
- filtros (0): —
- operações (2):
  - `portfolio.delete_dividend` → redirect-sem-query
  - `portfolio.update_dividend` → redirect-sem-query

### `/minha-senha` (account.change_password)
- filtros (0): —
- operações (2):
  - `account.change_password` → redirect-sem-query
  - `auth.logout` → redirect-sem-query

### `/options` (options.index)
- filtros (2): broker, portfolio_id
- operações (1):
  - `portfolio.delete_position_movement` → redirect-sem-query

### `/options/new` (options.new_position)
- filtros (0): —
- operações (2):
  - `options.delete_position` → redirect-sem-query
  - `options.update_position` → redirect-sem-query

### `/options/positions/<int:position_id>/close` (options.close_position_form)
- filtros (0): —
- operações (2):
  - `options.close_position` → redirect-sem-query
  - `portfolio.delete_position_movement` → redirect-sem-query

### `/options/positions/<int:position_id>/edit` (options.edit_position)
- filtros (0): —
- operações (2):
  - `options.delete_position` → redirect-sem-query
  - `options.update_position` → redirect-sem-query

### `/performance` (portfolio.monthly_performance)
- filtros (5): benchmark_ticker_id, broker, period, portfolio, portfolio_id
- operações (0):

### `/positions/<int:position_id>` (portfolio.position_detail)
- filtros (0): —
- operações (1):
  - `portfolio.delete_position_movement` → redirect-sem-query

### `/positions/<int:position_id>/close` (portfolio.close_position_form)
- filtros (0): —
- operações (2):
  - `portfolio.close_position` → redirect-sem-query
  - `portfolio.delete_position_movement` → redirect-sem-query

### `/positions/<int:position_id>/edit` (portfolio.edit_position)
- filtros (0): —
- operações (2):
  - `portfolio.delete_position` → redirect-sem-query
  - `portfolio.update_position` → redirect-sem-query

### `/positions/<int:position_id>/movements/<int:movement_id>/edit` (portfolio.edit_position_movement)
- filtros (0): —
- operações (1):
  - `portfolio.update_position_movement` → redirect-sem-query

### `/positions/new` (portfolio.new_position)
- filtros (0): —
- operações (2):
  - `portfolio.delete_position` → redirect-sem-query
  - `portfolio.update_position` → redirect-sem-query

### `/preferences` (portfolio.preferences)
- filtros (0): —
- operações (1):
  - `` → ?

### `/quotes` (portfolio.quote_history)
- filtros (2): benchmark_ticker_id, ticker_id
- operações (5):
  - `portfolio.create_quote_history_entry` → redirect+query ×2
  - `portfolio.delete_quote_history_by_date` → redirect+query
  - `portfolio.import_position_quote_history` → redirect+query
  - `portfolio.import_quote_history` → redirect+query

### `/risk` (portfolio.risk_report)
- filtros (0): —
- operações (0):

### `/settings` (portfolio.settings)
- filtros (0): —
- operações (2):
  - `` → ?
  - `portfolio.rtd_service_partial` → render

### `/tables/brokers` (portfolio.table_brokers)
- filtros (0): —
- operações (4):
  - `portfolio.activate_broker` → redirect-sem-query
  - `portfolio.create_broker` → redirect-sem-query
  - `portfolio.delete_broker` → redirect-sem-query
  - `portfolio.update_broker` → redirect-sem-query

### `/tables/options/contracts` (options.table_contracts)
- filtros (0): —
- operações (3):
  - `options.create_contract` → redirect-sem-query
  - `options.delete_contract` → redirect-sem-query
  - `options.update_contract` → redirect-sem-query

### `/tables/options/expirations` (options.table_expirations)
- filtros (0): —
- operações (3):
  - `options.create_expiration` → redirect-sem-query
  - `options.delete_expiration` → redirect-sem-query
  - `options.update_expiration` → redirect-sem-query

### `/tables/portfolios` (portfolio.table_portfolios)
- filtros (0): —
- operações (6):
  - `portfolio.activate_portfolio` → redirect-sem-query
  - `portfolio.add_portfolio_ticker` → redirect-sem-query
  - `portfolio.create_portfolio` → redirect-sem-query
  - `portfolio.delete_portfolio` → redirect-sem-query
  - `portfolio.remove_portfolio_ticker` → redirect-sem-query
  - `portfolio.update_portfolio` → redirect-sem-query

### `/tables/tickers` (portfolio.table_tickers)
- filtros (0): —
- operações (4):
  - `portfolio.activate_ticker` → redirect-sem-query
  - `portfolio.create_ticker` → redirect-sem-query
  - `portfolio.delete_ticker` → redirect-sem-query
  - `portfolio.update_ticker` → redirect-sem-query

### `/transactions` (portfolio.transactions)
- filtros (3): broker, portfolio_id, status
- operações (2):
  - `portfolio.delete_transaction` → redirect-sem-query ×2

### `/transactions/<int:transaction_id>/edit` (portfolio.edit_transaction)
- filtros (0): —
- operações (2):
  - `portfolio.delete_transaction` → redirect-sem-query
  - `portfolio.update_transaction` → redirect-sem-query

### `/transactions/new` (portfolio.new_transaction)
- filtros (0): —
- operações (2):
  - `portfolio.delete_transaction` → redirect-sem-query
  - `portfolio.update_transaction` → redirect-sem-query

### `/users` (users.index)
- filtros (0): —
- operações (4):
  - `users.change_active` → render
  - `users.create` → render
  - `users.edit` → render
  - `users.reset_user_password` → render

## Endpoints de escrita sem tela de origem encontrada (achar no navegador)

- `options.create_position` /options/positions → redirect-sem-query
- `portfolio.collector_agent_failure` /api/collector/failure → ?
- `portfolio.collector_agent_quotes` /api/collector/quotes → ?
- `portfolio.create_dividend` /dividends → redirect-sem-query
- `portfolio.create_position` /positions → redirect-sem-query
- `portfolio.create_transaction` /transactions → redirect-sem-query
- `portfolio.preferences` /preferences → redirect-sem-query
- `portfolio.request_collector_refresh` /settings/collector/refresh → redirect-sem-query
- `portfolio.settings` /settings → redirect-sem-query
- `portfolio.toggle_values_privacy` /privacy/toggle-values → redirect-sem-query
