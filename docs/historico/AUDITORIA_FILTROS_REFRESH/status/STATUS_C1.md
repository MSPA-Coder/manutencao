# STATUS C1 (CRV) - lote concluido

- Aba: tab-8 (viewport 1366x900 emulado; reset e fechamento no fim)
- Caso atual: nenhum; as 4 telas foram feitas (`/`, `/transactions`, `/options`, `/positions/33`)
- Dados gravados: `status/ACHADOS_C1.csv` (uma linha por variacao)

## Contagem geral (linhas do CSV)

- OK: 1.F (3 linhas), X-1v, 2.F (3 linhas), 2.1 cancelar, 3.F (3 linhas), 3.1 cancelar, 4.1 cancelar, 4.F F5 e voltar
- R (recarga cheia): X-1, X-1c, 2.X1, 2.X2, 3.X1 sucesso, 3.X1 cancelar, 3.X2, 4.F periodo, 4.X1, 4.X2, 3.X1 validacao do servidor
- M: X-2 (expandir linha trocou o bloco inteiro)
- LATERAL: seletor de contrato vencido em nova opcao (3.X1)
- NT (nao testado ou bloqueado): 1.1, 1.2, 2.1 sucesso, 2.1 pela lista, 3.1 sucesso, 3.1 movimento, 4.1 sucesso, 4.1 movimento

## Desfazer: PENDENTE (3 registros [AUD-C1] seguem existindo)

1. Posicao de acoes de teste: id 33 (carteira 1, Genial, ticker id 22) com lancamento de abertura id 59. Sem campo de notas no formulario.
2. Transacao encerrada de teste: id 31 (nota [AUD-C1], carteira 1, Genial, ticker id 24).
3. Posicao de opcao de teste: id 8 (carteira 1, Genial, contrato id 2).

Motivo: os dialogos de exclusao ("Excluir esta posicao?", "Excluir esta transacao?", "Excluir esta posicao de opcao?") nao citam nome nem nota. Pelo protocolo, cancelei em todos. Eu verifiquei a identidade pela propria pagina (nota [AUD-C1] no campo, ids na URL e na acao do formulario), mas a regra pede o dialogo. Preciso de decisao do coordenador: excluir pelo caminho manual, ou aceitar o que sobrou.

Nada mais foi criado. As linhas de teste nao usam ativo ou contrato que a carteira ja tinha; a verificacao foi feita antes de criar.

## Notas de metodo e limitacoes

- Menu superior: os itens do menu ficaram com centro (0,0), fora da area visivel, e nao aceitaram clique por ref. A ida a outra tela foi por `navigate` ao href, e o "voltar" pelo historico. Limitacao de metodo.
- 1.1 (`rtd_service_partial`): o gatilho e automatico (`quote-refresh-due` no bloco `portfolio-results`). Em ~80s com a aba em segundo plano nao disparou. Nao forcei. Reavaliar com a aba na frente, se o coordenador autorizar.
- 1.2 e 4.1 (`delete_position_movement`): a posicao de teste nao tem controle de exclusao de movimento individual, nem em `/`, nem na edicao do lancamento, nem na linha expandida. O unico controle e "Excluir posicao" (apaga a posicao inteira). Medi o cancelar desse controle (OK). O sucesso ficou NT pelo bloqueio do diálogo.
- Dialogo de cancelar: a primeira leitura em 2.1 (display:flex) deu falsa impressao de dialogo aberto. A altura do retangulo (zero) mostrou que ele estava oculto. Ajustei o CSV: 2.1 cancelar virou OK.
- Filtros do periodo em `/positions/33` sao links de navegacao completa, por isso R. A URL manteve o periodo.
- Nao foram testados: "Limpar" (intencional), "Abrir filtros globais", o cancelar da edicao do lancamento (4.X2), a validacao do navegador na edicao de posicao (4.X1), e o menu de ida/volta em 2 e 3 (feito por URL).
- A sonda foi reinstalada a cada recarga cheia (o `window` se perde).
