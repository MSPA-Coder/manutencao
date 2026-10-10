# Lote BC1 (CRV): reprodução às cegas

Base: http://127.0.0.1:5301

**Território para escrita:** Carteira id 1 (BRL), corretora 1; cadastros só [AUD-BC1]. A carteira Simulada (id 3) foi EXCLUÍDA: casos que a citem, refaça na carteira indicada. DADOS REAIS (cópia da produção): posição nova só numa combinação carteira+corretora+ticker que ainda não existe, quantidade 1; provento, transação e opção de teste com valor mínimo; corretora, ticker e carteira só com prefixo no nome. Anote o id de tudo o que criar e exclua no fim. Nunca altere nem exclua registro que já existia.

Leia antes `PROTOCOLO.md`. Este lote **não** traz o resultado que outro agente obteve, de propósito: meça do zero, com a sonda, e classifique com o seu próprio código.

Para cada caso:
1. abra a tela indicada (pode ajustar ids e valores para o seu território, mantendo os **mesmos nomes de filtro**);
2. faça a operação e a variação;
3. registre em `status/ACHADOS_<SEU_ID>.csv`, com a coluna `caso` igual ao **R-número** abaixo.

Se um passo for ambíguo, escolha a leitura mais natural para um usuário e anote em `obs`.

## Casos

- **R001**: tela `/positions/33`; operação: trocar periodo (link 1 ano); variação: sucesso
- **R002**: tela `/?portfolio_id=1&broker=Genial&return_days=30`; operação: expandir movimentos de linha existente (id 28); variação: sucesso
- **R003**: tela `/dividends/import?currency=USD`; operação: ir pelo menu Carteira -> Proventos; variação: menu
- **R004**: tela `/tables/options/contracts?currency=ALL`; operação: options.create_contract (codigo de teste AUD-C4 id 33; subjacente e vencimento existentes); variação: sucesso
- **R005**: tela `/positions/33/edit`; operação: excluir posicao (botao Excluir posicao); variação: sucesso
- **R006**: tela `/options/new`; operação: criar opcao em contrato ja vencido (Salvar > Confirmar); variação: validacao do servidor
- **R007**: tela `/dividends?broker=Nomad&currency=USD`; operação: expandir ativo (1 de 1 na lista); variação: sucesso
- **R008**: tela `/analysis/exposure-broker?portfolio_id=3`; operação: filtro corretora=XP; variação: sucesso
- **R009**: tela `/positions/new`; operação: Cancelar (link do formulario); variação: cancelar
- **R010**: tela `/dividends?broker=XP`; operação: abrir filtros globais e aplicar moeda USD (Dolar marcado e Real desmarcado); variação: sucesso
- **R011**: tela `/options/positions/8/edit`; operação: editar posicao de teste sem mudar valores (Salvar > Confirmar); variação: sucesso
- **R012**: tela `/tables/brokers?currency=ALL`; operação: preferencia modo discreto (POST /privacy/toggle-values); variação: ativar
- **R013**: tela `/tables/brokers`; operação: aplicar filtro global de moeda (GET do menu); variação: sucesso
- **R014**: tela `/positions/33/movements/59/edit`; operação: exclusao de movimento individual (delete_position_movement); variação: nao testado
- **R015**: tela `/tables/tickers?currency=ALL`; operação: portfolio.update_ticker (id 32); variação: sucesso
- **R016**: tela `/dividends?broker=XP&currency=USD`; operação: voltar (back); variação: voltar
- **R017**: tela `/tables/brokers?currency=ALL`; operação: voltar (history back); variação: sucesso
- **R018**: tela `/positions/new`; operação: link Cancelar (href /); variação: cancelar
- **R019**: tela `/dividends/new?currency=USD`; operação: salvar provento de teste (valor minimo) e confirmar; variação: sucesso
- **R020**: tela `/dividends/import?currency=USD`; operação: cancelar (link Cancelar); variação: cancelar
- **R021**: tela `/risk`; operação: filtro global de moeda: marca USD e Aplicar (unico filtro da tela); variação: sucesso
- **R022**: tela `/dividends/import?currency=USD`; operação: moeda ALL no filtro global (BRL e USD marcados); variação: sucesso
- **R023**: tela `/transactions/31/edit`; operação: editar nota do registro de teste (Salvar > Confirmar); variação: sucesso
- **R024**: tela `/performance?portfolio_id=3`; operação: filtro corretora=XP; variação: sucesso
- **R025**: tela `/tables/tickers?currency=ALL`; operação: portfolio.delete_ticker (id 32); variação: sucesso (foco por Tab
- **R026**: tela `/dividends/import?currency=BRL`; operação: voltar (back); variação: voltar
- **R027**: tela `/dividends?broker=Nomad&currency=USD`; operação: F5 com ativo e ano expandidos; variação: F5
- **R028**: tela `/analysis/exposure-asset?portfolio_id=3`; operação: filtro corretora=XP; variação: sucesso
- **R029**: tela `/positions/33/edit`; operação: editar posicao sem mudar valores (Salvar > Confirmar); variação: sucesso
- **R030**: tela `/tables/tickers?currency=ALL`; operação: voltar (history back); variação: sucesso
- **R031**: tela `/options/positions/8/edit`; operação: excluir posicao (botao Excluir posicao); variação: sucesso
- **R032**: tela `/dividends/import?currency=USD`; operação: aplicar moeda BRL no filtro global (USD desmarcado); variação: sucesso
- **R033**: tela `/tables/brokers?currency=ALL`; operação: preferencia modo discreto (POST /privacy/toggle-values); variação: desativar (desfaz)
- **R034**: tela `/transactions/new`; operação: criar transacao encerrada (Salvar > Confirmar); variação: sucesso
- **R035**: tela `/positions/33?periodo=1y`; operação: F5 (navigate mesma URL); variação: F5
- **R036**: tela `/performance?broker=XP`; operação: voltar (history back); variação: voltar
- **R037**: tela `/analysis/exposure-market?portfolio_id=3`; operação: filtro corretora=XP; variação: sucesso
- **R038**: tela `/analysis/exposure-asset`; operação: menu Analise > Performance; variação: menu
