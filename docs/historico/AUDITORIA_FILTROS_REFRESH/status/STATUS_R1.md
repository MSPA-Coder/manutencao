# STATUS R1 (CB, reteste das correções) - FINAL

- Aba: tab-17 (fechada ao fim; viewport resetado para desktop)
- Lote: 16 casos feitos (R1.1 a R1.16). Resultados em status/ACHADOS_R1.csv (47 linhas de dados, CSV validado: 12 campos em todas).

## Resultado por caso

- R1.1 F: filtro de coluna Categoria mantém tabela e URL, sem recarga; mas o select de Tipo perde opções e valor (URL segue com filter_type=despesa), inclusive após F5.
- R1.2 OK: Realizar sem recarga, filtros e URL iguais; cancelar sem requisição; F5 OK. Erro de validação não feito (formulário sem campo obrigatório visível).
- R1.3 OK: Desfazer realização sem recarga; lançamento voltou a A vencer; F5 OK. Cancelar não testado (sem outro realizado no território).
- R1.4 OK: Novo lançamento [AUD-R1] x2 sem recarga; form mantém conta, tipo, status e vencimento. Categoria zera (fora da lista do lote). F5 OK.
- R1.5 OK: sem descrição, o navegador recusou no Salvar do diálogo; nada criado.
- R1.6 OK: duplo clique real: 1 POST, 1 lançamento.
- R1.7 OK: edição em linha sem recarga; erro (valor vazio) recusado; cancelar sem POST; F5 OK.
- R1.8 OK (parcial): cancelar OK. Exclusão NÃO confirmada: o diálogo não cita [AUD-R1] (regra do protocolo).
- R1.9 OK: Voltar do Novo lançamento só fecha o cartão.
- R1.10 OK (parcial, só categorias): incluir, editar e trocar filtro sem recarga; URL acompanha. Exclusão não confirmada (diálogo sem nome). Bancos, contas e titulares não testados.
  - Achado de preparo F (fora do caso): ao Aplicar filtros globais em Categorias, filter_type sumiu da URL e do select.
- R1.11 OK: nome só de espaços: navegador aceita, servidor recusa com "Nome da instituição é obrigatório" (error); nada recarrega.
- R1.12 OK, com LATERAL: tag e projeto [AUD-R1] criados sem recarga (appMain trocado, aceito pelo lote); arquivar não confirmado (diálogo sem nome; cancelar OK); F5 OK; voltar OK. LATERAL: o campo Mês mostra 2026-10 com period=2026-11 na URL; a página usa month; ao escolher o mês, period some.
- R1.13 F: fechar 2026-10 da conta 4 sem recarga, mas a moeda (currency=ALL) sumiu da URL. Reabrir OK (motivo auditável, sem perda adicional); F5 OK.
- R1.14 OK: Revisar mantém conta, categoria e moeda na URL; nada gravado. Não há botão Cancelar: saída por Filtrar (GET comum, recarga normal). "Gravar reclassificação" não clicado.
- R1.15 OK: Dashboard, Projeções, Próximos movimentos e Gerencial levam titular e conta com faixa "Recorte"; Posição por conta leva só titular; Planejamento anual e Fechamento não levam; Limpar recorte remove.
- R1.16 OK: voltar do navegador sai da tela (não é achado).

## Contagem (casos)

- OK: R1.2, R1.3, R1.4, R1.5, R1.6, R1.7, R1.8, R1.9, R1.10, R1.11, R1.12, R1.14, R1.15, R1.16 (14, com parciais em R1.8, R1.10 e R1.12)
- Não-OK: R1.1 (F), R1.13 (F). Fora do caso: preparo do R1.10 (F), achado LATERAL no R1.12.

## Estado dos dados [AUD-R1] NÃO desfeito (pendente de decisão)

- Lançamentos (Esposita, conta 6): teste 1 (id 3870, valor 2), teste 2 (20/11/2026), teste 4 (20/11/2026), teste 3 (09/10/2026).
- Categoria "[AUD-R1] cat 1 ed" (id 29).
- Tag "[AUD-R1] tag 1" (id 4). Projeto "[AUD-R1] projeto 1" (id 2).
- Motivo: os diálogos de Confirmar exclusão, Confirmar ciclo de vida (arquivar) não citam o nome [AUD-R1]; o protocolo manda cancelar. Nenhuma exclusão/arquivamento foi confirmada. Id conferidos antes do clique (botão aponta para o id esperado).
- Restaurado de forma já feita: lançamento 853 (realizado no R1.2 e revertido no R1.3). Instituição: a tentativa de nome em espaços foi recusada; nada criado.

## Notas de método

- Cancelar de edição de categoria não existe (só Salvar); saída feita por recarga da própria URL, sem gravar.
- Moeda: "Real + Dólar" aplicada via Abrir filtros globais; conta 4 = C6 / Conta 02; conta 6 = Itaú / Conta 03.
- F5 e voltar lidos pelo DOM (a sonda some no reload); voltar leva a entrada anterior do histórico (não comparável).
