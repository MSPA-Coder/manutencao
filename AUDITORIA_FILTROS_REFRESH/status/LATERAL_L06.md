# LATERAL L06 - Movimentos de OPEN em carteira Simulada (ControleRendaVariavel)

Data da investigação: 09/10/2026. Base: cópia local de produção (06:00 de 09/10).
Escopo: só leitura. Nenhum arquivo do repositório foi alterado, nenhum commit, nenhum navegador, nenhuma escrita no banco. Os valores (quantidades, preços, ativos) não foram transcritos.

## Veredito

**Dado legado, não defeito de criação no código atual.** Com confiança alta de que os 10 movimentos não vieram do fluxo normal do sistema, e com confiança média-alta de que vieram de um lote de "abertura sintética" gravado em 12/08/2026 21:13:53, fora deste repositório (o histórico git começa em 16/08). A origem exata é **indeterminada**, porque o código que escreveu o lote não está no repo.

Há, porém, uma **lacuna de código real e independente da origem**: a tela de detalhe de posição (`/positions/<id>`), o gráfico dela e os endpoints de editar/excluir lançamento não checam carteira simulada. Por isso os 10 movimentos aparecem e são editáveis. As leituras de performance, risco, patrimônio v4 e custo médio ignoram a simulada explicitamente.

## 1. A regra existe? Fontes

Sim. A regra é "carteira simulada não gera movimento nem transação, não consolida e não pode ser encerrada".

- `AGENTS.md:177-178`: "carteira simulada não gera movimentos ou transações, não consolida posições e não pode ser encerrada".
- `README.md:26-27`: "Carteiras simuladas servem apenas para insight: não geram movimentos ou transações".
- `app/routes/positions.py:548-551`: comentário na criação (a fonte citada na pergunta).
- `app/positions/closure.py:415-424`: em `create_or_merge_position`, a simulada é recusada no merge (linha 416), e o `OPEN` só é gravado quando `not candidate.simulated` (linha 423).
- `app/positions/closure.py:495`, `:585`, `:115`: guardas em ajuste, encerramento e espelho de transação.
- `app/positions/closure.py:529-535` (`discard_simulation_history`): apaga a linha aberta e o extrato ao entrar na simulada.
- `app/routes/positions.py:662-663`: chama o descarte quando a posição passa de real para simulada.
- `app/routes/tables.py:342-358` e `:376`: `simulated` não muda depois da criação da carteira.

Correção ao enunciado: `app/models.py:307-313` diz "não geram transação", e não "movimento". A frase com "movimento" está nos docs e nos comentários citados acima.

Testes que cobrem a regra: `tests/test_quote_position_lines.py:70-71` (sem extrato), `tests/test_contrato_v4_schema.py:135` (4 holdings, a simulada fica de fora), `tests/test_linha_do_tempo_de_posicoes.py:100-101` e `:196` (semeia um `OPEN` numa simulada e verifica que a leitura o ignora).

## 2. Caminho de criação dos movimentos (hipóteses)

Fatos do banco (contagens e datas, sem valores):

- Carteira 3: simulada, 10 posições, 10 movimentos, 0 transações.
- As 10 posições da carteira 3 têm `created_at` idêntico, 2026-08-08 06:54:56.971292, o mesmo instante de 4 posições reais da carteira 1. `updated_at` igual a `created_at` em todas, ou seja, nunca editadas.
- Os 10 movimentos da carteira 3 (ids 9 a 18) têm `created_at` idêntico, 2026-08-12 21:13:53.894975. Esse lote tem 15 linhas: 4 da carteira 1, 1 da carteira 2 e 10 da carteira 3. As 15 posições cujo primeiro movimento tem `created_at` diferente do da posição são exatamente as 15 do lote (4 + 1 + 10).
- Consulta por posição (`mesma_transacao` = movimento e posição com o mesmo `created_at`): carteira 3 tem 10 de 10 com `f`. As posições reais com `t` são as criadas pelo fluxo normal (3 na carteira 1 e 2 na carteira 2). Todo movimento do fluxo normal nasce na mesma transação da posição (`create_or_merge_position`, `closure.py:423-433`).
- Perfil dos 10 `OPEN` da carteira 3: quantidade, preço e data iguais aos da posição atual, e sem `transaction_id`. Ou seja, é uma reconstrução da abertura a partir do estado atual.
- Nenhuma posição do banco está sem extrato (0 de 20).
- Commit raiz do git: `a654732`, 2026-08-16, "versão inicial consolidada V2.0". Não há commit do repo anterior a 16/08 (`git log --all --before=2026-08-17` só retorna commits de 16/08). A regra já está nesse commit (`git log -S`).
- Baseline de migração (`migrations/versions/20260813_0001_baseline.py`): cria as tabelas e insere as carteiras BRL, USD e Simulada, todas com `created_at` de 2026-08-13 20:14:11.

Hipóteses:

- **H1 - Lote de abertura sintética (backfill), 12/08/2026 21:13:53. Mais provável.** Um processo único gravou um `OPEN` para cada posição existente sem extrato, incluindo as da simulada, copiando o estado atual. Evidência: o lote único de 15 linhas, o `created_at` diferente do da posição, e o perfil booleano (dado reconstruído). O processo não está no repo: as migrações que mexem em `position_movements` (`0004`, `0016`, `0024`) não inserem `OPEN`, e a baseline só cria a tabela. Confiança: alta na natureza de dado legado; média na origem exata.
- **H2 - Criação normal (`create_or_merge_position`). Descartada.** Gravaria o movimento na mesma transação da posição, e nunca para simulada.
- **H3 - Migração de dados em `migrations/`. Descartada para o repo atual.** Nenhuma revisão do repo insere `OPEN` em `position_movements`.
- **H4 - Importação de histórico (`import-position-history` e `app/quotes/history_import.py`). Descartada.** O comando usa `quote_update_targets()` e grava só cotações. A única construção de `PositionMovement(...)` é `record_movement` (`positions/closure.py:157`), chamada de `create_or_merge_position`, de ajuste, de encerramento e de `discard`.
- **H5 - Conversão de carteira comum em simulada. Descartada para o código atual.** `_requested_simulated_change` (`tables.py:342-358`) existe desde `a654732`. A troca de posição real para simulada passa por `discard_simulation_history`. Não é possível descartar o código anterior a 16/08, que não está no git.
- **H6 - Código anterior a 16/08 sem a regra ou sem o descarte. Indeterminado.** Compatível com as datas (08/08 e 12/08 são anteriores ao repo), mas não verificável aqui.

## 3. Efeito visível hoje

| Superfície | Efeito | Evidência |
|---|---|---|
| Extrato expandido na grade da carteira | Não | `partials/portfolio_results.html:30`: `has_history = len > 1`; cada posição tem 1 movimento, então não há botão `+` |
| Detalhe da posição `/positions/<id>` | **Sim** | `routes/positions.py:451` sem guarda; gráfico recebe o marcador "Abertura" (`average_cost_line.py:106` `aportes_da_posicao`) e degraus de custo (`:88`); tabela "Movimentos" mostra a abertura com "Resultado" hipotético (`positions/portfolio.py:211`) |
| Link para o detalhe | Sim | `partials/portfolio_results.html:43` liga o ticker de qualquer posição |
| Editar / excluir lançamento | **Sim (aceita)** | `routes/positions.py:705` (edição), `:714` (update) e `:763` (delete) sem guarda; `partials/position_movements.html:34-35` mostra o link "Editar" para qualquer movimento que não seja ajuste |
| Performance (TWR), risco, patrimônio v4 | Não | Ignorado explicitamente em `patrimonio/queries.py:77` (docstring) e no filtro `Portfolio.simulated.is_(False)` de `:114`, que alimenta `position_timeline`, usado por `routes/helpers.py` (`position_movement_events`) |
| Custo médio por ticker (gráfico) | Não | `average_cost_line.py:136` filtra as posições; `:144-152` só lê movimentos dessas posições |
| Totais e cards da carteira | Não | `positions/portfolio.py` só usa `movements` em `position_movement_results` (`:229`) |
| Aba Transações | Não | 0 transações na carteira 3 |
| Confirmação JS de troca para simulada | Não agora | `static/app.js:427-428` só pede confirmação com mais de 1 movimento |

Ou seja: os 10 movimentos são visíveis e editáveis pelo detalhe da posição, mas não entram em nenhum indicador.

Lacunas de código (onde a regra não é aplicada): `position_detail` (`routes/positions.py:451`), `degraus_da_posicao` (`average_cost_line.py:88`), `aportes_da_posicao` (`:106`), `position_movement_results` (`positions/portfolio.py:211`), `update_position_movement` (`routes/positions.py:714`) e `delete_position_movement` (`:763`). A docstring de `models.py:307-313` só fala em "transação", então não documenta a proibição de movimento.

Lacuna de teste: `test_linha_do_tempo_de_posicoes.py` cobre só as leituras de performance. Não há teste de rota (detalhe, edição, exclusão) para posição de simulada com movimento. Também não encontrei teste que troque uma posição real para simulada e verifique que o extrato é apagado.

## 4. Veredito, proposta e teste

**Veredito:** dado legado (lote de abertura sintética de 12/08 que incluiu a simulada), mais uma lacuna de código que permite ver e editar esse dado. Não há evidência de que o fluxo atual crie `OPEN` em simulada.

**Proposta de código (não executada):**

1. Um ponto único para o extrato: uma função `extrato_da_posicao(position)` que devolve `[]` quando `position.simulated`. Usar em `position_detail`, `degraus_da_posicao`, `aportes_da_posicao`, `position_movement_results` e nos fragmentos do extrato.
2. Recusar edição e exclusão de lançamento quando a posição é simulada, com mensagem do mesmo estilo da recusa de encerramento (`routes/positions.py:809-814`, que é inline; a constante `SIMULATED_CLOSE_REJECTED` existe só em `options/closure.py:64`).
3. Esconder o link "Editar" e a seção "Movimentos" quando a posição é simulada.

**Proposta de limpeza (não executada, depende de autorização para produção):**

Preferir reusar o próprio `discard_simulation_history(position)` para cada posição de carteira simulada com movimentos, em um comando one-off com `--dry-run`, em uma única transação. Equivalente em SQL, só para referência:

```sql
BEGIN;
-- conferir antes: esperado 10 linhas, todas OPEN, sem transação
SELECT m.id, m.kind, m.transaction_id
FROM position_movements m
JOIN positions p ON p.id = m.position_id
JOIN portfolios pf ON pf.id = p.portfolio_id
WHERE pf.simulated AND m.owner_id = p.owner_id;
DELETE FROM position_movements m
USING positions p, portfolios pf
WHERE m.position_id = p.id AND pf.id = p.portfolio_id AND pf.simulated AND m.owner_id = p.owner_id;
-- conferir DELETE 10 e então COMMIT; senão ROLLBACK
```

A limpeza não deve mudar performance, risco, patrimônio ou custo médio, porque essas leituras já ignoram a simulada. Deve mudar só o detalhe da posição. Confirmar isso antes de aplicar. Produção: a mesma situação precisa ser conferida lá com consulta de leitura, e a aplicação só com autorização explícita.

**Teste que impediria a volta:**

- Rota: a partir do cenário que já semeia `OPEN` numa simulada (`test_linha_do_tempo_de_posicoes.py:100-101`), `GET /positions/<id>` não renderiza o marcador "Abertura" nem o link "Editar", e `POST /positions/<id>/movements/<mid>` e o delete são recusados.
- Transição: `update_position` de real para simulada deixa `position.movements == []` e nenhuma linha em `transactions`.
- Invariante de dados: consulta que conta movimentos de posições de carteira simulada e deve dar 0, executada no fim dos testes de integração ou num comando de diagnóstico.

## Limites da investigação

- Não foi possível ver o código anterior a 16/08/2026. Por isso H1 e H6 não podem ser confirmadas só com o repo.
- Não foi executada suíte de testes nem a aplicação; as conclusões sobre a tela vêm da leitura do código e dos templates.
- Os valores das posições e dos movimentos não foram lidos nem reportados, só contagens, ids, datas e flags.
