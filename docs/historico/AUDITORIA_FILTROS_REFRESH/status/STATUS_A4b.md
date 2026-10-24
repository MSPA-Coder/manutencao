# STATUS A4b (CB, lote sozinho) - CONCLUIDO COM LACUNAS

- Aba: tab-6 (viewport 1366x900 aplicado e depois restaurado para desktop). Fechar com tabs_close.
- Casos: 10 (Conciliacao), 11 (Reclassificacao), 12 (Atualizar saldo). Nenhum caso aberto.
- Arquivo de achados: status/ACHADOS_A4b.csv (17 linhas, cabecalho incluso).

## Tela 10 (Conciliacao)
- 10.F feito: aplicar filtros globais (moeda e grupos), F5 OK, voltar F (entrada anterior sem query), menu lateral OK.
- 10.1 a 10.4 NAO TESTADOS: lista de linhas pendentes vazia ("Nenhuma linha pendente") com moeda ALL e todos os grupos; a tela nao tem filtro de conta. Sem alvo para conciliar, criar, ignorar ou acao em lote.
- 10.5 (desfazer conciliacao) NAO TESTADO: as conciliacoes listadas sao de outras contas, nao criadas por este executor.
- 10.X NAO TESTADOS: "Aplicar sugestoes", "Conciliar/Criar/Ignorar selecionadas" e "Selecionar todas" dependem de linhas pendentes.
- Nada criado nesta tela; nada a desfazer.

## Tela 11 (Reclassificacao) - conta 8 = "Genial / Conta 03"
- 11.F feito: conta e categoria aplicados (R, GET com recarga); F5 OK; voltar U (tela mantem conta e categoria por cache do formulario, URL sem eles; F5 perderia); menu lateral F (conta e categoria saem da URL; globais mantidos).
- 11.1 feito (reclassificar um lancamento e devolver): lancamento da primeira linha (conta 8) movido para Outros e de volta para a categoria original, com inclusao em lote DESMARCADA. Gravado duas vezes; verificado na tela ao final (categoria original restaurada).
- Autorizacao de reabertura: o lancamento caiu em mes fechado (02/2026). Marquei "Autorizo reabrir" como permitido no lote; o app fecha o mes de novo ao gravar. NAO verifiquei o fechamento do mes (a tela de fechamento fica em Configuracoes, fora do escopo).
- Validacao (revisar sem selecao): sem resposta visivel (sem mensagem, previa ou dialogo). Registrado como OK com observacao.
- Cancelar do dialogo de confirmacao NAO testado nesta tela.
- Lacuna de medicao: F5 apos gravacao nao medido por sonda; removido do CSV.

## Tela 12 (Atualizar saldo)
- 12.F feito: filtro global de grupos (R), F5 OK, voltar OK (volta ao valor anterior, sem perda).
- 12.1 parcial: "Comparar" (POST de previa, sem gravar) executado com saldo informado e data de hoje. Resultado: F (URL perdeu moeda e grupos; a pagina recarregou). O botao de lancar a diferenca NAO apareceu; a tela mostra aviso de que o extrato de 10/2026 da conta de movimento nao foi importado. Lancamento NAO gravado, nada a excluir.
- 12.X NAO TESTADO.

## Desfazer
- Nenhum lancamento [AUD-A4b] criado (a reclassificacao foi revertida; a comparacao de saldo nao grava).
- Pendencia para o coordenador: a reabertura e o refechamento de 02/2026 (conta 8) foram autorizados pelo lote; conferir o estado de fechamento na tela de fechamento mensal.

## Fora do escopo, nao feito
- Nota de Gerencial (orcamento de teste sem prefixo, deixado pelo A2): NAO excluido, porque o protocolo proibe excluir o que nao foi criado pelo executor.
- Permissoes, Configuracoes, Tabelas: fora do lote.

## Notas de metodo
- Filtros GET (globais e da Reclassificacao) recarregam a pagina inteira; a sonda registra R nessas trocas, esperado.
- Menu lateral: grupo de Bancos colapsa a cada recarga; expandir antes de clicar Conciliacao ou Reclassificacao.
- Sonda: "antes" fica no sessionStorage. Apos navegacao, reinjetar e chamar ler(). Em alguns passos a leitura foi feita por DOM (indicado na observacao do CSV).
- Clique por coordenada so funcionou depois de screenshot; o label de autorizacao ocupa a linha inteira e o clique por ref caia num paragrafo.
