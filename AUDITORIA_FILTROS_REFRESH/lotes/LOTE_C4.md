# Lote C4 (CRV)

Base: http://127.0.0.1:5301

**Território:** Entidades **criadas por você** `[AUD-C4]`: corretora, ticker, carteira, vencimento e contrato de opção. **Não** altere nem exclua registros existentes. Cotações: nada de importar, apagar por data ou excluir.

Leia antes `PROTOCOLO.md`.

## Notas

- Este lote roda **sozinho**, depois de C1, C2 e C3.
- Tabelas: filtre, role, crie a sua entidade, edite, desative e reative (se houver) e exclua.
- Preferências, configurações e modo discreto: leia o valor, salve o mesmo valor (ou alterne e desfaça) e meça a resposta.
- Usuários: só abra e filtre; não crie usuário.

## Casos

### 1. `/tables/brokers`
- filtros detectados: nenhum no template (procure na tela)
- **1.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **1.1** operação `portfolio.create_broker`; resposta prevista: redirect-sem-query
- **1.2** operação `portfolio.update_broker`; resposta prevista: redirect-sem-query
- **1.3** operação `portfolio.delete_broker`; resposta prevista: redirect-sem-query
- **1.4** operação `portfolio.activate_broker`; resposta prevista: redirect-sem-query
- **1.X** outras operações visíveis na tela e não listadas acima: teste e registre como `1.X<n>`.

### 2. `/tables/tickers`
- filtros detectados: nenhum no template (procure na tela)
- **2.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **2.1** operação `portfolio.create_ticker`; resposta prevista: redirect-sem-query
- **2.2** operação `portfolio.update_ticker`; resposta prevista: redirect-sem-query
- **2.3** operação `portfolio.delete_ticker`; resposta prevista: redirect-sem-query
- **2.4** operação `portfolio.activate_ticker`; resposta prevista: redirect-sem-query
- **2.X** outras operações visíveis na tela e não listadas acima: teste e registre como `2.X<n>`.

### 3. `/tables/portfolios`
- filtros detectados: nenhum no template (procure na tela)
- **3.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **3.1** operação `portfolio.create_portfolio`; resposta prevista: redirect-sem-query
- **3.2** operação `portfolio.update_portfolio`; resposta prevista: redirect-sem-query
- **3.3** operação `portfolio.delete_portfolio`; resposta prevista: redirect-sem-query
- **3.4** operação `portfolio.activate_portfolio`; resposta prevista: redirect-sem-query
- **3.5** operação `portfolio.remove_portfolio_ticker`; resposta prevista: redirect-sem-query
- **3.6** operação `portfolio.add_portfolio_ticker`; resposta prevista: redirect-sem-query
- **3.X** outras operações visíveis na tela e não listadas acima: teste e registre como `3.X<n>`.

### 4. `/tables/options/contracts`
- filtros detectados: nenhum no template (procure na tela)
- **4.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **4.1** operação `options.create_contract`; resposta prevista: redirect-sem-query
- **4.2** operação `options.update_contract`; resposta prevista: redirect-sem-query
- **4.3** operação `options.delete_contract`; resposta prevista: redirect-sem-query
- **4.X** outras operações visíveis na tela e não listadas acima: teste e registre como `4.X<n>`.

### 5. `/tables/options/expirations`
- filtros detectados: nenhum no template (procure na tela)
- **5.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **5.1** operação `options.create_expiration`; resposta prevista: redirect-sem-query
- **5.2** operação `options.update_expiration`; resposta prevista: redirect-sem-query
- **5.3** operação `options.delete_expiration`; resposta prevista: redirect-sem-query
- **5.X** outras operações visíveis na tela e não listadas acima: teste e registre como `5.X<n>`.

### 6. `/quotes`
- filtros detectados: ticker_id, benchmark_ticker_id
- **6.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **6.1** operação `portfolio.import_quote_history`; resposta prevista: redirect+query
- **6.2** operação `portfolio.import_position_quote_history`; resposta prevista: redirect+query
- **6.3** operação `portfolio.create_quote_history_entry` (2 controles); resposta prevista: redirect+query
- **6.4** operação `portfolio.delete_quote_history_by_date`; resposta prevista: redirect+query
- **6.X** outras operações visíveis na tela e não listadas acima: teste e registre como `6.X<n>`.

### 7. `/settings`
- filtros detectados: nenhum no template (procure na tela)
- **7.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **7.1** operação `(form sem ação)`
- **7.2** operação `portfolio.rtd_service_partial`; resposta prevista: render
- **7.X** outras operações visíveis na tela e não listadas acima: teste e registre como `7.X<n>`.

### 8. `/preferences`
- filtros detectados: nenhum no template (procure na tela)
- **8.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **8.1** operação `(form sem ação)`
- **8.X** outras operações visíveis na tela e não listadas acima: teste e registre como `8.X<n>`.

### 9. `/users`
- filtros detectados: nenhum no template (procure na tela)
- **9.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **9.1** operação `users.create`; resposta prevista: render
- **9.2** operação `users.edit`; resposta prevista: render
- **9.3** operação `users.reset_user_password`; resposta prevista: render
- **9.4** operação `users.change_active`; resposta prevista: render
- **9.X** outras operações visíveis na tela e não listadas acima: teste e registre como `9.X<n>`.

