# STATUS A3 (CB) - FINAL

- Aba: tab-4 (viewport 1366x900 aplicado; fechar com resize preset desktop e tabs_close)
- Caso atual: nenhum. Lote concluido.
- Telas concluidas: 1 settings/monthly-close, 2 banking/cards, 3 banking/accounts/14 (conta em dolar do territorio)

## Resultado (30 linhas em ACHADOS_A3.csv)
- OK: 23 | R: 6 | M: 1 | F: 0 | U: 0 (as duas perdas de currency na URL aparecem como nota em R)
- Pior achado: 1.F M (appMain em todo filtro); R em POST de fechar/reabrir (currency sumiu da URL)

## Casos
- 1.F: filtros conta/ano/mes/status, F5, voltar, menu: OK exceto troca appMain (M)
- 1.1 fechar 2026-10 e 2026-09 conta 5: sucesso R (2x), validacao OK, cancelar OK, F5/voltar OK
- 1.2 reabrir 2026-10 e 2026-09 conta 5: validacao OK, cancelar OK (09), sucesso R (2x), F5/voltar OK
- G.monthly-close (aplicar USD + sem corretoras): R (GET comum)
- G.dashboard, G.transactions, G.balance, G.reclassification, G.operations: OK
- 2.F grupos (Mostrar todas): OK; F5 OK; voltar OK; menu OK (grupos voltam ao global, esperado)
- 2.X1-3 faturas Black 42 e 41 e Carbon 24: OK (sem rolagem: pagina cabe na viewport)
- 3.F periodo 2026-09 conta 14: R (GET); F5 OK; voltar OK; menu OK
- 3.X1 link Lancamentos da conta 14: OK

## Desfeito
- Conta 5: 2026-10 reaberto; 2026-09 fechado de novo (estado inicial).
- Filtro global restaurado: BRL marcado, USD desmarcado, grupos padrao.

## Nao feito (e por que)
- Lancamento em cartao [AUD-A3] no cartao 20 (criar e excluir): NAO criado. A regra de dados proibe excluir sem confirmacao direta do usuario, e o lote exige exclusao. Pendente de autorizacao explicita.
- Menu: contas e cartoes ficam em grupo recolhido em algumas telas (link com area zero); o clique por ref falha. Usei links visiveis e historico.

## Notas de metodo
- Dialogos de confirmacao e itens de menu fora da viewport precisaram de scroll_to antes do clique.
- F5 com a mesma URL substitui a entrada do historico; o voltar seguinte cai na entrada anterior (comportamento do navegador, nao do app).
- Filtro global e persistido na sessao do navegador: outros executores que usam a mesma sessao podem ter visto USD durante a janela do teste.
