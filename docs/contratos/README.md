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
| `sistema-financeiro` (CB) | `tests/contrato/patrimonio-v4.schema.json` | a saída real das três rotas, num cenário com os quatro recursos que o CB publica (`tests/test_contrato_v4_schema.py`) |
| `ControleRendaVariavel` (CRV) | `tests/contrato/patrimonio-v4.schema.json` | a saída real das três rotas (`tests/test_contrato_v4_schema.py`) |
| `WealthfolioTeste` | `addons/controle-patrimonial-sync/sim/contrato/patrimonio-v4.schema.json` | as fixtures da simulação do add-on e, com `SIM_REAL=1`, as respostas de produção (`sim/contrato.mjs`) |

O CI semanal de cada um baixa esta cópia e confere que a dele é idêntica. A
rodada é só semanal de propósito: depende da rede, e uma indisponibilidade do
GitHub não deve travar um PR nem o portão do deploy.

### Como mudar o contrato

1. Mude **este** arquivo.
2. Copie para os três repositórios acima, no mesmo dia, cada um em um PR com a
   mudança de código que a motivou.
3. Rode `python3 docs/contratos/verificar.py` aqui: confere JSON, LF, `$ref`s e as
   seis definições.

Para o publicador, o schema funciona assim: **exige** os campos que ele emite
hoje, com o tipo e o formato de hoje (valor monetário e quantidade como texto
decimal, data e instante ISO 8601, moeda ISO 4217, ids prefixados pela fonte),
e **permite propriedades a mais**. Acréscimo opcional não muda a versão do
contrato (assim entraram `purpose`, `group` e `effective_status`), e quem não o
conhece o ignora. Para tornar um campo novo obrigatório, acrescente-o a
`required`. Remover ou renomear um campo, ou trocar o tipo dele, reprova a suíte
de quem fez a mudança — que é o ponto.

Os formatos são `pattern`, e não `format`: nenhum validador precisa de
`FormatChecker`. O schema é válido em modo estrito no Ajv, e é preciso que
continue: o Ajv é mais exigente que o `jsonschema` do Python.
