# STATUS B3 (CB) - fim do lote

- Abas: tab-4 e tab-5 (criadas por B3). Fechar ao final.
- Casos: K2, K4, K6, G1, G2, G3 (3 telas), G4 feitos. Ver ACHADOS_B3.csv.

## Resultados por caso

- K2 (filtro em voo + Realizar): C. Trocar filtro com o dialogo Realizar aberto faz o clique em Realizar do segundo dialogo nao gerar requisicao (2 tentativas; linha nao realizada). Controle sem troca: realiza, recarga cheia (R). Filtro + Realizar no mesmo batch: M, ref obsoleta, nada executado.
- K4 (duas abas): OK para operacoes cruzadas (criar/excluir na aba 1 e na aba 2, filtros da outra aba intactos). Fechamento: fechar e reabrir 2026-10 da conta 5 com filtro de ano em outra aba: F na URL do fechamento (period/account_id somem), R nas acoes; filtro da outra aba mantido.
- K6 (recarga com filtro HTMX): Desfazer realizacao e edicao salvas com recarga cheia; filtro de categoria mantido. Achado F: trocar um filtro de coluna remove o outro (Tipo <-> Categoria), na URL e no select.
- G1 (compra cartao 20): criar R, editar R, cancelar exclusao R (recarrega e nao exclui), excluir R. Validacao: descricao vazia nao bloqueada pelo servidor (LATERAL, lancamento sem descricao gravado e removido por mim).
- G2 (transferencia parcelada conta 5 -> aplicacao 16): criada (2 tentativas, dois grupos). Edicao com escopo "Este registro e os proximos": dialogo "Este registro e os proximos serao recriados. Deseja continuar?"; confirmou e gravou. Exclusao com "Todos os registros do grupo": grupos removidos.
- G3 (filtros globais): 3 telas (Projecoes, Posicao por conta, Proximos movimentos) + Dashboard: moeda USD e grupo Cartoes resetam ao trocar de tela pelo menu (F). Demais itens do menu NAO cobertos.
- G4 (planejamento anual): nao concluido. Ctrl+clique nao alterou a selecao de titulares; Aplicar fora da area visivel.

## Sobrou (nao excluivel por mim)

- Fechamento Mensal: conta 5, 2026-10, status Reaberto, motivo "[AUD-B3] reabertura teste K4" (registro de reabertura permanece).
- Nada mais com [AUD-B3] nas contas 5, 16 e 20 (periodos 2026-11 e 2026-12 verificados; transferencias de teste removidas).
- Alteracoes acidentais: 1 clique em filtro global (aplicacoes) na tela de projecoes; resetado ao trocar de tela. Nenhuma linha de terceiros foi editada, excluida ou salva (a linha de 04/12 da conta 5 apenas apareceu nas listagens; nao foi tocada).

## Notas de metodo

- Realizar/Desfazer: dois dialogos; Desfazer do menu abre app-modal, depois sa-modal "Confirmar reversao".
- Refs saem de validade apos swap do appMain; clique de linha em batch apos filtro falha por design.
- Sonda reinstalada apos cada recarga cheia.
