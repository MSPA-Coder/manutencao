# STATUS A2 (CB)

- Aba: tab-3 (viewport 1366x900 aplicado)
- Caso atual: LOTE A2 ENCERRADO (telas 1 a 10 percorridas). Aba tab-3 a fechar.
- Telas 3 a 10 (resumo): 3.F (aplicar R, F5 OK, voltar U, menu F); 3.1 revisar F (preview; gravar nao autorizado: mes 09/2026 fechado); 4.F (aplicar R, F5 OK, voltar U) e 4.1 a 4.5 NAO TESTADOS (lista com linhas de varios titulares); 5.F (R, OK, U), 5.1 e 5.2 NAO TESTADOS; 6.F (R, OK, U), 6.1 e 6.2 NAO TESTADOS; 7.F (R, OK, U); 8.F (R, OK, U); 9.F (aplicar OK, F5 OK, voltar P, menu F); 10.F NAO CONCLUSIVO (selecao multipla nao reproduzida).
- Tela 2 (banking/balance/) concluída: 2.F (global aplicar R, F5 OK, voltar U); 2.1 validacao OK, sucesso NAO TESTADO (lancaria saldo realizado sem prefixo); 2.X: "Modo discreto" fora da viewport, nao testado.
- Tela 1 (management/) concluída: 1.F, 1.1 a 1.8. Faltam 1.X (nenhuma outra operação além das listadas).

## Casos feitos (tela 1)
- 1.F: aplicar, F5, voltar, menu -> M, OK, P, F
- 1.1 create_tag: sucesso R, validacao OK, cancelar OK, F5 OK, voltar OK
- 1.2 create_project: sucesso R, validacao OK, cancelar OK, F5 OK, voltar OK
- 1.3 save_budget: sucesso R, validacao OK, cancelar OK, F5 OK, voltar OK
- 1.4 assign_tag (movimento 616): sucesso R, validacao OK, cancelar OK, F5 OK, voltar OK
- 1.5 assign_project (movimento 639): sucesso R, validacao OK, cancelar OK, F5 OK, voltar OK
- 1.6 retire_tag: cancelar OK; confirmar -> ARQUIVOU (tag tem vinculo) R; F5 OK; voltar OK
- 1.7 retire_project: cancelar OK; confirmar -> ARQUIVOU R; F5 OK; voltar OK
- 1.8 retire_budget: cancelar OK. Confirmar NAO feito (ver pendencias)

Total de linhas no CSV: 38. Nao OK: 10 (M 1, P 1, F 1, R 7).

## Pendencias de desfazer e de autorizacao
- Tag "[AUD-A2] tag teste 1": arquivada (status Arquivada). Vinculada ao movimento 616. Nao ha desvinculo na tela.
- Projeto "[AUD-A2] projeto teste 1": arquivado. Vinculado ao movimento 639. Nao ha desvinculo na tela.
- Orcamento "Outros 09/2026" (titular do lote, valor de teste): criado em 1.3, NAO excluido. Sem prefixo possivel (orcamento nao tem nome) e sem vinculo, o botao seria exclusao definitiva. Pendente de autorizacao do coordenador.
- Tag "[AUD-A2] tag cancelar" e projeto "[AUD-A2] projeto cancelar": nunca salvos (so digitados e cancelados).

## Divergencias do lote (para o coordenador)
- Tabela de Contas (tables/accounts/): a conta de id 1 ("Mercado Pago / Conta 01") existe em dois titulares com o mesmo nome. A conta 7 ("C6 / Conta 02") tambem tem homonimo de outro titular. Por isso NAO operei movimentos das contas 1 e 7.
- Operacoes de movimento foram feitas na conta 8 ("Genial / Conta 03", titular do lote, sem homonimo).
- Usei a conta 1 apenas como filtro de leitura na preparacao da tela 1.

## Notas de metodo
- Preparacao dos filtros da tela 1 (apos o caso 1.4): navigate com a query equivalente (owner_id=1, institution_id=5, account_id=8, month=2026-09, currency=BRL), no lugar de form_input. Isso foi feito porque a conta 1 era ambigua.
- Sonda reinjetada apos cada recarga. Depois do voltar, do F5 e das recargas em que a leitura nao foi possivel, a conferencia foi por DOM (URL e 4 filtros), e isso esta anotado nas observacoes.
- Cliques de envio abrem dialogo "Confirmar..." (2o dialogo). Os dialogos de cancelar e de validacao foram tratados como o protocolo manda.
- Moeda: o parametro currency=BRL aparece na URL e nao foi tratado como perda.
- Itens com "Excluir / arquivar": so confirmei os que tinham vinculo (arquivo). O orcamento nao foi confirmado.
- Coordenador (esclarecimento no meio do lote): excluir so o que eu criei com prefixo [AUD-A2] esta autorizado. O orcamento de teste nao tem prefixo: nao foi excluido. Pede decisao.
- Parametro currency=BRL acrescentado pelos formularios foi tratado como padrao, nao como perda.
- Campo obs de alguns casos passa de 200 caracteres (3.1, 10.F e alguns NAO TESTADO).
- Telas 4 a 10: filtros globais aplicados pelo painel; sonda nao reinstalada em todas as telas (algumas medidas por DOM/URL).
- Aba tab-3 e a unica usada. Viewport a restaurar e aba a fechar ao final.
