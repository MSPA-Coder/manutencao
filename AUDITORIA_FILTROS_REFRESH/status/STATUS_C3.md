# STATUS C3 (CRV: Performance, Risco, Dados, Exposicao, Posicoes)

- Aba: tab-10 (viewport 1366x900 aplicado; resetar com preset "desktop" ao fim)
- Caso atual: fechamento. Todas as telas do lote foram tocadas.

## Feitos (ACHADOS_C3.csv tem 31 linhas de dados)
- 1.F /performance: 7 linhas. F x3 (troca de corretora apaga portfolio_id=3; menu de Risco e menu de Performance zeram filtros), OK x3, LATERAL x1.
- 1.X /performance: 3 linhas, todas R (filtro global de moeda, modo discreto, Limpar). Moeda e modo discreto revertidos.
- 2.F /risk: 5 linhas. R, OK, U (voltar), OK (menu leva moeda), LATERAL (item Risco do menu abre Alocacao).
- 3.F /data-status: 4 linhas. R, OK, U (voltar), OK.
- E1 /analysis/exposure-asset, E2 /analysis/exposure-broker, E3 /analysis/exposure-market: troca de corretora apaga portfolio_id=3 (F em cada).
- 4.F /: troca de periodo, corretora e tipo mantem os filtros (OK x3), F5 OK.
- 4.P /positions/new: link Nova posicao (F), salvar com quantidade vazia (OK, barrado no navegador), Cancelar (F).

## Nao feito
- Criar, editar e excluir posicao [AUD-C3] na Simulada. Motivo: o formulario de nova posicao nao tem campo de descricao, entao nao ha como marcar a posicao com o prefixo. Sem a marca, a regra de exclusao manda cancelar. Nada foi criado nem alterado. Precisa de decisao do coordenador.
- Variacao "erro de validacao" em /risk e /data-status: nao se aplica, nao ha formulario.
- Volta (history back) em E1 e em /: nao medida (a volta caiu em outra tela do historico).
- Menu de volta para /data-status: o item esta em menu que nao abre por clique visivel; nao medido.
- Modo discreto em /risk e /data-status: mesma operacao global ja medida em 1.X2.
- Rolagem ate a linha operada: nao ha tabela operavel nas telas de filtro.

## Sobrou sem desfazer
- Nada criado (nenhuma posicao [AUD-C3]).
- Filtro global de moeda em BRL (padrao). Modo discreto inativo.

## Notas de metodo
- A sonda foi perdida em cada navegacao completa; nas recargas posteriores, a leitura foi feita direto na URL e nos controles.
- Clique por ref no menu Analise > Risco caiu em Alocacao por Ativo, nas duas vezes (LATERAL). Refs mudam apos cada carga: reler com read_page.
- Drawer de filtros globais e botao de modo discreto so respondem depois de "Abrir filtros globais".
