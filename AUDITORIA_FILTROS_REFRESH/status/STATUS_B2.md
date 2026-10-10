# STATUS B2 (CB, ataques de corrida e lacunas G1-G4)

## Situação: PARCIAL (parei com o lote incompleto)

- Aba: `tab-3` (criada em 09/10 após a `tab-9` sumir; viewport 1366x900 aplicado). Deixada aberta.
- Tela atual: Relatórios > Planejamento anual (`/reports/annual-planning/`).

## Casos feitos

- K1 (duplo clique), Parte 1: criar, excluir e realizar. Detalhe no CSV.
  - Criar: 2 lançamentos `[AUD-B2]` com a mesma descrição (ids 3846 e 3847), por duas confirmações separadas no meu fluxo (C). Salvar do formulário com recarga cheia (R).
  - Excluir com duplo clique: 2 POST `/transaction/delete/3846`, ambos 200 (C).
  - Controle com clique simples: 1 POST `/transaction/delete/3847` (OK).
  - Realizar: o Confirmar do modal (`/mark_realized/3847`) não gera requisição, com clique simples e duplo; Cancelar não fecha o modal (LATERAL).
- K3 (dois filtros em batch): o filtro de categoria saiu da URL base e apagou o de tipo (C/F).
- K5 (filtro e voltar no mesmo batch): URL, selects e tabela coerentes; o voltar caiu na entrada anterior do histórico (OK).

## Não feitos

- K2: depende de Realizar, que está travado (LATERAL). Só o filtro em voo, sem realização, não foi feito.
- K4 (duas abas): não feito.
- K6 (edição HTMX, Desfazer realização): não feito; exige um `[AUD-B2]` novo e Realizar.
- G1 (compra no cartão 20), G2 (transferência e escopo): não feitos; exigem criar lançamentos.
- G3 (filtros globais nas demais telas do menu): não feito. O menu lateral fica fora da área visível neste viewport.
- G4 (planejamento anual, seleção múltipla): não feito. Titulares e contas vêm todos selecionados por padrão; falta desmarcar com Ctrl+clique.

## Contagem no CSV até aqui

- 8 linhas: C = 4 (K1 criar, K1 excluir duplo, K1 criar 2a confirmação, K3), R = 1, OK = 2 (K1 excluir controle, K5), LATERAL = 1 (K1 realizar).

## O que falta desfazer

- Nada pendente. Os dois `[AUD-B2]` de K1 foram excluídos. Conferido: 0 linhas `[AUD-B2]` em 2026-11 da conta 5.

## Para retomar

1. Abrir Lançamentos (`/transactions/?period=2026-10&mode=todos&account_id=5`) na `tab-3`. A sonda precisa ser reinstalada após cada recarga cheia.
2. Realizar está travado: antes de K2, K6 e G1 confirmar se o modal `realizeModal` ainda não responde.
3. Pendentes: K2, K4, K6, G1, G2, G3, G4.
