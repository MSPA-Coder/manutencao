# STATUS C2 (CRV, proventos e moeda): LOTE CONCLUIDO

- Aba: tab-9 (fechada ao fim; viewport 1366x900 redefinido)
- Lote: 1.F, 1.X1 a 1.X6, 2.F, 2.1 (NAO_TESTAVEL), 2.X1 (cancelar), G.import (moeda ALL + propagacao pelo menu)
- Casos: 27 linhas em ACHADOS_C2.csv
- Contagem: OK 12, F 9, R 3, S 1, NAO_TESTAVEL 2

## Pendencia de desfazer (NAO resolvida)
- Provento de teste id 142 (Nomad, ativo id 31, US$ 0,01, pagamento 01-Oct-26) CRIADO e NAO EXCLUIDO.
  - O formulario de provento nao tem campo de descricao: o prefixo [AUD-C2] nao pode ser gravado.
  - O dialogo de exclusao tambem nao cita o prefixo; pela regra do protocolo a exclusao foi cancelada.
  - Valor de teste revertido para 0,01 apos a edicao de teste (conferido na lista).
  - Acao pedida ao coordenador: excluir manualmente o id 142 ou autorizar exclusao por id.
- NAO tocar nos proventos 136 e 141 (existentes, nao sao do C2).

## Notas de metodo
- Carteira 2 (USD) so aparece como filtro na tela inicial (portfolio_id=2); /dividends tem moeda global e corretora.
- Corretoras do territorio: XP = id 2, Nomad = id 4. XP em USD nao tem proventos; Nomad em USD tem 1 ativo com 2 registros existentes.
- Clique: o primeiro clique apos interagir com formulario muitas vezes nao dispara; repetir pelo ref e conferir a URL.
- Filtro global (moeda) aplicado por "Aplicar" recarrega a pagina inteira (R) e descarta a corretora.
