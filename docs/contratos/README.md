# Contratos entre os sistemas

## `patrimonio-v4.schema.json`

O JSON Schema (2020-12) do contrato `patrimonio/v4`: o que o Controle Bancário
(CB) e o Controle de Renda Variável (CRV) publicam em
`/patrimonio/v4/{metadata,snapshot,changes}` para o Wealthfolio. Há uma definição
por fonte e endpoint: `cb_metadata`, `cb_snapshot`, `cb_changes`, `crv_metadata`,
`crv_snapshot` e `crv_changes`. A descrição do contrato em prosa está em
`docs/patrimonio-v4.md` do WealthfolioTeste.

**Este arquivo é a cópia canônica.** Cada repositório tem uma cópia idêntica,
byte a byte, e a suíte dele a aplica:

| Repositório | Cópia | Quem a valida |
|---|---|---|
| `controle-bancario` (CB) | `tests/contrato/patrimonio-v4.schema.json` | a saída real das três rotas, num cenário com os quatro recursos que o CB publica (`tests/test_contrato_v4_schema.py`) |
| `ControleRendaVariavel` (CRV) | `tests/contrato/patrimonio-v4.schema.json` | a saída real das três rotas (`tests/test_contrato_v4_schema.py`) |
| `WealthfolioTeste` | `addons/controle-patrimonial-sync/sim/contrato/patrimonio-v4.schema.json` | as fixtures da simulação do add-on e, com `SIM_REAL=1`, as respostas de produção (`sim/contrato.mjs`) |

O CI semanal de cada um baixa esta cópia e confere que a dele é idêntica. A
rodada é só semanal de propósito: depende da rede, e uma indisponibilidade do
GitHub não deve deixar a CI vermelha a cada push.

### Como mudar o contrato

1. Mude **este** arquivo.
2. `python compartilhados/sincronizar.py --aplicar` copia para os três
   repositórios acima; commite cada cópia junto com a mudança de código que a
   motivou.
3. Rode `python3 docs/contratos/verificar.py` aqui: confere JSON, LF, `$ref`s e as
   seis definições.

Para o publicador, o schema funciona assim: **exige** os campos que ele emite
hoje, com o tipo e o formato de hoje (valor monetário e quantidade como texto
decimal, data e instante ISO 8601, moeda ISO 4217, ids prefixados pela fonte),
e **permite propriedades a mais**. Acréscimo opcional não muda a versão do
contrato (assim entraram `purpose`, `group`, `effective_status` e
`statement_covered_until`), e quem não o
conhece o ignora. Para tornar um campo novo obrigatório, acrescente-o a
`required`. Remover ou renomear um campo, ou trocar o tipo dele, reprova a suíte
de quem fez a mudança — que é o ponto.

Os formatos são `pattern`, e não `format`: nenhum validador precisa de
`FormatChecker`. O schema é válido em modo estrito no Ajv, e é preciso que
continue: o Ajv é mais exigente que o `jsonschema` do Python.

## `crv-fechamento-1.schema.json`

O que o CRV responde em `GET /fechamento/status?ate=AAAA-MM-DD` ao Roteiro de
fechamento do CB (contrato `crv-fechamento/1`): itens já avaliados, com etapa,
estado e texto. Cópias em `tests/contrato/` do CRV e do CB.

| Repositório | Quem a valida |
|---|---|
| `ControleRendaVariavel` | a resposta real da rota e cada item que depende do CB, em todo estado (`tests/test_fechamento_status.py`, `tests/test_contrato_com_o_cb.py`) |
| `controle-bancario` | o leitor aceita exatamente os estados e as etapas do schema (`tests/test_contrato_com_o_crv.py`) |

Estado ou etapa novos entram aqui e nos dois lados na mesma mudança: o CB
descarta, calado, o item que não reconhece.

## `exemplos/cb-snapshot-vinculo.json`

A resposta **real** do CB ao CRV: o snapshot v4 pedido com o token do vínculo
(`CRV_LINK_TOKEN`), recortado às contas de corretora. Não é escrito à mão: a
suíte do CB o gera pelo caminho real (parser do extrato, detalhe gravado, rota)
e reprova quando a resposta deixa de ser igual a ele, mostrando o arquivo novo
(`tests/test_contrato_com_o_crv.py`). A suíte do CRV lê a mesma cópia com o
cliente dele (`tests/test_contrato_com_o_cb.py`). Ids, instantes e a data do
saldo são fixos; o resto é o que a rota respondeu.

Para mudar o que o CB publica ao CRV: rode a suíte do CB, grave aqui o texto que
o teste mostra entre `<<<EXEMPLO` e `EXEMPLO>>>`, rode
`python compartilhados/sincronizar.py --aplicar` e depois a suíte do CRV. É ela
que diz se o leitor do CRV ainda entende a resposta.
