# Lote BC2 (CRV): reprodução às cegas

Base: http://127.0.0.1:5301

**Território para escrita:** Carteira id 2 (USD); proventos na corretora 4; cadastros só [AUD-BC2]. A carteira Simulada (id 3) foi EXCLUÍDA: casos que a citem, refaça na carteira indicada. DADOS REAIS (cópia da produção): posição nova só numa combinação carteira+corretora+ticker que ainda não existe, quantidade 1; provento, transação e opção de teste com valor mínimo; corretora, ticker e carteira só com prefixo no nome. Anote o id de tudo o que criar e exclua no fim. Nunca altere nem exclua registro que já existia.

Leia antes `PROTOCOLO.md`. Este lote **não** traz o resultado que outro agente obteve, de propósito: meça do zero, com a sonda, e classifique com o seu próprio código.

Para cada caso:
1. abra a tela indicada (pode ajustar ids e valores para o seu território, mantendo os **mesmos nomes de filtro**);
2. faça a operação e a variação;
3. registre em `status/ACHADOS_<SEU_ID>.csv`, com a coluna `caso` igual ao **R-número** abaixo.

Se um passo for ambíguo, escolha a leitura mais natural para um usuário e anote em `obs`.

## Casos

- **R001**: tela `/?portfolio_id=1&broker=Genial&return_days=30`; operação: criar posicao (Nova posicao > Salvar > Confirmar); variação: sucesso
- **R002**: tela `/tables/portfolios?currency=ALL`; operação: portfolio.add_portfolio_ticker (carteira id 4 apenas); variação: sucesso
- **R003**: tela `/tables/portfolios?currency=ALL`; operação: portfolio.create_portfolio (dialogo Adicionar carteira); variação: sucesso
- **R004**: tela `/tables/portfolios?currency=ALL`; operação: portfolio.update_portfolio (id 4); variação: cancelar (envio por Enter no campo)
- **R005**: tela `/data-status`; operação: filtro global de moeda: marca USD e Aplicar (unico filtro da tela); variação: sucesso
- **R006**: tela `/?portfolio_id=3&broker=XP&return_days=182&result_mode=acao_proventos`; operação: link Nova posicao (abre formulario); variação: abrir
- **R007**: tela `/options/new`; operação: Cancelar (link do formulario); variação: cancelar
- **R008**: tela `/options/new`; operação: criar opcao em contrato sem posicao da carteira (Salvar > Confirmar); variação: sucesso
- **R009**: tela `/dividends?broker=XP`; operação: ir e voltar pelo menu Carteira (Posicoes e Proventos); variação: menu
- **R010**: tela `/tables/portfolios?currency=ALL`; operação: portfolio.delete_portfolio (id 4); variação: cancelar (foco por Tab
- **R011**: tela `/options?portfolio_id=1&broker=Genial`; operação: ida por href (/transactions) e voltar; variação: voltar
- **R012**: tela `/performance?broker=XP&portfolio=all&period=year`; operação: menu Analise > Risco (href /risk); variação: menu
- **R013**: tela `/tables/brokers?currency=ALL`; operação: portfolio.update_broker (id 6); variação: sucesso
- **R014**: tela `/tables/brokers?currency=ALL`; operação: ir e voltar pelo menu (Cadastros > Tickers > Corretoras); variação: sucesso
- **R015**: tela `/?portfolio_id=1&broker=Genial&return_days=30`; operação: portfolio.delete_position_movement; variação: nao testado
- **R016**: tela `/data-status?currency=ALL`; operação: voltar (history back); variação: voltar
- **R017**: tela `/transactions`; operação: excluir pelo botao da lista; variação: sucesso
- **R018**: tela `/transactions/31/edit`; operação: excluir pelo botao da edicao; variação: sucesso
- **R019**: tela `/tables/portfolios?currency=ALL`; operação: portfolio.delete_portfolio (id 4); variação: sucesso (foco por Tab
- **R020**: tela `/dividends?broker=Nomad&currency=USD`; operação: abrir Novo provento a partir da lista filtrada; variação: abrir
- **R021**: tela `/performance?period=year&broker=XP`; operação: filtro global de moeda: marca USD e Aplicar; variação: sucesso
- **R022**: tela `/options`; operação: exclusao de movimento de opcao (delete_position_movement); variação: nao testado
- **R023**: tela `/dividends?broker=Nomad&currency=USD (ativo expandido)`; operação: editar provento de teste id 142 (valor de teste) e salvar; variação: sucesso
- **R024**: tela `/preferences?currency=ALL`; operação: F5 (navigate mesma URL); variação: sucesso
- **R025**: tela `/dividends/new?currency=USD`; operação: cancelar (link Cancelar); variação: cancelar
- **R026**: tela `/performance?period=year&broker=XP&currency=ALL`; operação: Ativar modo discreto (ida e volta); variação: sucesso
- **R027**: tela `/tables/brokers?currency=ALL`; operação: portfolio.create_broker; variação: sucesso
- **R028**: tela `/tables/tickers?currency=ALL`; operação: portfolio.create_ticker; variação: sucesso
- **R029**: tela `/tables/tickers?currency=ALL`; operação: portfolio.delete_ticker (id 32); variação: cancelar (foco por Tab ate Remover
- **R030**: tela `/performance?period=year&broker=XP&currency=BRL`; operação: link Limpar; variação: sucesso
- **R031**: tela `/dividends?broker=Nomad&currency=USD (ativo expandido)`; operação: editar e cancelar (link Cancelar); variação: cancelar
- **R032**: tela `/dividends?broker=Nomad&currency=USD`; operação: salvar criacao com sucesso (provento de teste id 142 criado); variação: sucesso
- **R033**: tela `/tables/options/contracts?currency=ALL`; operação: options.update_contract (id 7; trocar o codigo da opcao); variação: sucesso
- **R034**: tela `/tables/options/contracts?currency=ALL`; operação: options.delete_contract (id 7); variação: sucesso
- **R035**: tela `/tables/brokers?currency=ALL`; operação: portfolio.delete_broker (id 6); variação: sucesso
- **R036**: tela `/risk?currency=ALL`; operação: voltar (history back); variação: voltar
- **R037**: tela `/quotes?currency=ALL`; operação: abrir /quotes com ticker_id=1; variação: sucesso
