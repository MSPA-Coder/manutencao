# STATUS BCK (corrida) - lote K1-K5 - CRV

- Abas: tab-21 (aba A), tab-22 (aba B). Viewport 1366x900 emulado.
- Caso atual: fim do lote (K1-K5 executados).
- Casos feitos: 16 linhas em ACHADOS_BCK.csv. Nao-OK: 5 (F x3, S x1, LATERAL x1). Nenhuma corrida C reproduzida.
- Criados e excluidos (todos com confirmacao de id na URL): proventos 142 e 144; transacao 34 (nota AUD-BCK). Nenhum remanescente. 143 nunca existiu.
- Nao excluido: nada pendente.
- Nao executado: F5 e voltar apos sucesso (K1 e K2 proventos); K1 variacao "duplo clique em Confirmar" na transacao foi feita so como duplo clique unico (ok).

## Notas de metodo
- Salvar e Excluir abrem dialogo de duas etapas; duplo clique em Salvar abre e fecha o dialogo (2o clique cai no fundo). Para duplo envio real, usar duplo clique em Confirmar (ref).
- Refs mudam apos cada navegacao; reler com read_page antes de form_input.
- Sonda: window.__sonda some em cada carga completa; o estado fica em sessionStorage.
- Aba B: "Aplicar" em filtros globais recarrega a pagina com ?currency=ALL e descarta broker (F).
