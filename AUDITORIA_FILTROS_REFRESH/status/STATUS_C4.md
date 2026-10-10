# STATUS C4 (CRV)

- Aba: tab-15 (viewport 1366x900 emulado)
- Caso atual: nenhum (lote encerrado em 09/10; aba a fechar)
- Telas concluídas: 1 (/tables/brokers), 2 (/tables/tickers), 3 (/tables/portfolios), 4 (/tables/options/contracts, parcial), 5 (/tables/options/expirations, só F), 6 (/quotes, só F e um LATERAL), 7 (/settings, só F), 8 (/preferences, só F), 9 (/users, só F)

## Tela 4 /tables/options/contracts (parcial)
- Feito: 4.F (F5), 4.1 sucesso, 4.2 sucesso, 4.3 cancelar e sucesso. Contrato de teste id 7; código de opção de teste (ticker AUD-C4 id 33, criado para isso e excluído depois).
- Não-OK: 4.1 (R+F), 4.2 (R+F, e o código não persistiu: LATERAL 4.L), 4.3 sucesso (R+F).
- Pendente: 4.1 erro e cancelar; 4.2 erro e cancelar; 4.F voltar; 4.X não testado.
- Observação: o código da opção do contrato 7 não mudou após "Salvar" (recarga sem mensagem). Não investiguei causa; pode ser validação do servidor ou falha de gravação. Registro LATERAL 4.L.

## Telas 5 a 9 (só filtro; operações não executadas)
- 5 (/tables/options/expirations): F5 OK. Não criei vencimento; 5.1 a 5.3 não testados (faltou tempo/contexto).
- 6 (/quotes): ticker_id na URL mantém a página OK. benchmark_ticker_id devolve "404 Not Found" (LATERAL 6.L). 6.1 a 6.4 não executadas, por regra (cotações: nada de importar, apagar por data ou excluir). 6.3 (criar entrada de cotação) também não foi feita, por cautela.
- 7 (/settings): F5 OK. 7.1 e 7.2 não executados.
- 8 (/preferences): F5 OK. 8.1 não executado.
- 9 (/users): F5 OK, só abrir e filtrar. 9.1 a 9.4 não executadas (regra: usuários só abrir e filtrar).

## Limpeza (conferida em 09/10)
- Corretora id 6: criada, editada, excluída. Não resta nenhum [AUD-C4] em corretoras.
- Ticker id 32: criado, editado, excluído. Ticker id 33 (código da opção): criado e excluído na limpeza.
- Carteira id 4: criada, editada, excluída (ticker existente associado e desassociado só nela).
- Contrato id 7: criado, editado (sem efeito), excluído.
- Modo discreto: ativado e desfeito (estado original).
- Filtro global: a moeda vem só da URL (currency=ALL). Não há gravação do filtro; ao abrir a tela sem o parâmetro ele volta a BRL.
- Pendências de desfazer: nenhuma.
- Aba tab-15 fechada; viewport emulado reposto para o padrão (desktop).

## Pendências gerais (não testadas)
- 1.4, 2.4, 3.4: ativar/reativar sem controle na tela. Não testado.
- 2.X: variação de criar ticker com a opção de referência (benchmark) marcada. Não testada.
- Variações de cancelar e erro em 3.5, 3.6, 4.1, 4.2 (algumas), 5.x (sem criar) e todas as de 5 a 9.

## Tela 3 /tables/portfolios (concluída, com pendências)
- Casos feitos: 3.F; 3.1 (sucesso, erro, cancelar); 3.2 (sucesso, erro, cancelar); 3.3 (cancelar, sucesso); 3.5 (sucesso); 3.6 (sucesso). 3.4 não testado.
- Não-OK: nenhum. Todas as operações desta tela trocaram só a lista (`portfolios-results`), sem recarga, e mantiveram `currency=ALL`. Diferente de corretoras e tickers.
- Pendente nesta tela: 3.5 cancelar e 3.6 cancelar/erro não foram feitos (custo de contexto). Ficam para retomada.
- 3.4 (ativar carteira): a tela só mostra o estado "Ativa", sem controle de ativar/desativar. Não testado.
- Registros criados e excluídos: carteira id 4 (AUD-C4; criada, editada, excluída). Ticker existente foi associado à carteira 4 e desassociado (só na minha carteira; nenhum ticker alterado). Nenhuma carteira existente foi tocada.
- Método: cadastro/edição em diálogo; a seção "Adicionar ticker" é um details fechado, e precisa ser aberta (clique no resumo) antes do botão de envio ficar clicável.

## Tela 2 /tables/tickers (concluída)
- Casos: 2.F (F5, voltar, menu; a aplicação do filtro global já está medida em 1.F), 2.1 (sucesso, erro, cancelar), 2.2 (sucesso, erro, cancelar), 2.3 (cancelar, sucesso). 2.4 não testado. 2.X não testado.
- Não-OK: 2.1 sucesso (R+F), 2.2 sucesso (R+F), 2.3 sucesso (R+F). Total 3 de 11 linhas.
- 2.4 (ativar ticker): a tela não tem controle de ativar nem reativar, e nenhum formulário de ativação (checado por JS). Não testado.
- 2.X: a tela só tem as operações já cobertas (cadastro com a opção de referência, edição, exclusão) e o filtro global. Não testei a variação de criar ticker com a referência marcada, por custo de contexto. Fica como pendência.
- Registro criado e excluído: ticker id 32, com nome de pregão prefixado AUD-C4, código de teste. Editado uma vez (código de teste trocado). Excluído pelo botão Remover, com o diálogo mostrando o código de teste. Nenhum ticker de teste restante nesta tela.
- Método: como a linha de teste ficou sem ref estável, a edição e a exclusão foram feitas pelo campo do símbolo (Enter) e por Tab até "Remover", com verificação por JS do formulário de destino antes de cada Enter.

## Tela 1 /tables/brokers (concluída)
- Casos: 1.F, 1.1 (sucesso, erro, cancelar), 1.2 (sucesso, erro, cancelar), 1.3 (sucesso, cancelar), 1.X1 (modo discreto ativar e desfazer). 1.4 não testado (ver abaixo).
- Não-OK: 1.F (aplicar filtro global = R), 1.1 sucesso (R + F), 1.2 sucesso (R + F), 1.3 sucesso (R + F), 1.X1 ativar (R) e desfazer (R). Total: 6 não-OK de 14 linhas.
- Achado recorrente: qualquer operação de escrita (criar, editar, excluir) recarrega a página inteira e o redirect perde `currency=ALL` da URL (volta para BRL). Ver CSV.
- 1.4 (ativar corretora): não testado. A tela não tem controle de ativar/desativar (linhas só mostram estado "Ativa", com Salvar e Remover) e não há corretora inativa para testar.
- Registro criado e excluído: corretora id 6, nome com prefixo AUD-C4 (criada, editada para "...editada", excluída). Excluída pelo botão Remover, com o diálogo citando o nome AUD-C4. Não há mais nenhum [AUD-C4] nesta tela.
- Pendente de desfazer: nenhum criado nesta tela. Filtro global: restaurar moeda para o padrão (BRL) ao final de tudo, desmarcando USD e aplicando (ou navegando para /tables/brokers sem query).
- Obs: o formulário "Cancelar" da corretora deixou valores digitados nos campos "Adicionar" (texto [AUD-C4] Corretora cancelada / sigla AUDC4C) e na linha da corretora excluída. Nada foi enviado com eles.

## Notas de método
- Sonda injetada uma vez por carga; após cada recarga é preciso reinjetar para ler. Em alguns casos, a leitura do estado foi feita direto do sessionStorage (chave `__sonda_auditoria`), com o mesmo dado da sonda.
- Preparação de filtro (currency=ALL) feita por navigate com query, sem gravar nada.
- Diálogos de confirmação: Adicionar/Salvar/Remover abrem "Confirmar"; Cancelar fecha sem enviar.
- Ao fim da tela 1, o `Sair` (logout) não foi clicado. Não há outros controles de escrita nesta tela.
