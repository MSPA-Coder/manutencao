# L03 - Carteira Simulada ausente em Performance e Exposição

Data: 09/10/2026. Repositório: `C:\Dev\VSCodeProjects\ControleRendaVariavel` (HEAD `ede6f5d`, árvore limpa antes e depois). Nenhum arquivo do repositório foi alterado, nenhum commit foi feito, o navegador não foi usado. Banco: somente SELECT, e o relatório traz apenas ids e contagens.

## Veredito

**Intencional** a exclusão da carteira Simulada em Performance e Exposição. A regra está no código, no docstring do modelo, em comentários de rota e em um teste de domínio. Há duas lacunas: o contrato funcional de Exposição não a menciona, e a tela não avisa o usuário (o seletor mostra "Todas" enquanto o filtro efetivo é a carteira 3, que resulta vazia).

A hipótese de `currency` NULL como causa **foi refutada**: nenhum filtro lê `Portfolio.currency`.

Achado colateral, classificado como **indeterminado**: a cópia local tem 10 movimentos `OPEN` nas posições da Simulada, o que contradiz a premissa de que simulada não gera extrato. A origem não foi identificada.

## 1. Nome do parâmetro

- O parâmetro é **`portfolio_id`**: `app/routes/helpers.py:177` (`request.args.get("portfolio_id")`), dentro de `selected_filters()` (`helpers.py:164-185`).
- Atenção: Performance também lê `portfolio` em `app/routes/performance.py:54`, mas esse parâmetro é o **tipo de instrumento** (`stocks`, `options`, `all`), não a carteira. `?portfolio=3` cai silenciosamente em `stocks`.
- `selected_filters()` só valida que o id pertence ao dono (`helpers.py:182`). Não rejeita carteira simulada, então o id é aceito e a consulta roda filtrada por ele.

## 2. Intenção (evidências)

Código:
- `app/routes/performance.py:58-62`: "Performance continua excluindo a carteira Simulada incondicionalmente".
- `app/routes/positions.py:892-896` (`_render_exposure`): "Exposição continua excluindo a carteira Simulada incondicionalmente", com `positions_query(..., exclude_simulated=True)` na linha 897.
- `app/patrimonio/queries.py:77-78` (`position_timeline`, usado pelo TWR): "A carteira simulada fica de fora sempre, de forma explícita". O filtro está na linha 114.
- `app/models.py:307-313`, docstring de `Portfolio`: "posições nela ficam fora de Risco, Performance e exposição e não geram transação".
- `app/routes/helpers.py:149-161` (`real_portfolio_records`): "Opções do filtro de Carteira em Performance e Exposição ... nunca oferecem a carteira Simulada".

Testes:
- `tests/test_linha_do_tempo_de_posicoes.py:195-196`: `position_movement_events(portfolio_id=<simulada>) == []`, com a observação "A simulada nunca entra, nem pedida pelo id". O cenário (linhas 100-101) já grava um `OPEN` na simulada, então a exclusão é provada explicitamente e não por ausência de dados.
- Não há teste HTTP para o seletor de Performance/Exposição, para `real_portfolio_records`, nem para `positions_query(exclude_simulated=True)`. `tests/test_audit_priorities.py:134` só renderiza o partial.

Documentação:
- `docs/planilha-acoes.md:88-90`: a carteira simulada "existe só para ver valores nas grades, não para operar". Não diz que Performance e Exposição a excluem.
- `docs/planilha-acoes.md:460` (seção "Exposição") não menciona a Simulada.
- `docs/planilha-acoes.md:444-446` diz que o padrão "Todas" mostra "linhas de todas as carteiras", mas o código exclui a simulada de "Todas" (`helpers.py:247-250`; `positions.py:335-339`). Divergência entre doc e código.
- `docs/architecture.md:75` e `README.md:26-28`: "não é patrimônio" e "servem apenas para insight", em contexto de patrimônio e cotações, não de telas.

Git (`git log -S simulated`: 24 commits):
- A exclusão de Performance e Exposição já existe em `a654732` (versão inicial consolidada V2.0). `git log -S exclude_simulated` só encontra esse commit.
- `002933e` (#109) moveu o filtro de `Portfolio.simulated` para `position_timeline` (`queries.py:114`) e o manteve.
- `b794e3a` (#70, 18/09) introduziu o filtro global de moeda com padrão BRL (`app/core/currency_filter.py:10`).

## 3. Como a tela reage

- Performance (`/performance?portfolio_id=<simulada>`): `position_timeline` devolve vazio. A tela mostra "Nenhuma posição aberta encontrada para os filtros" (`app/templates/partials/performance_results.html:88`).
- Exposição (`/analysis/exposure-*`): `positions_query` devolve vazio. A tela mostra "Nenhuma posição encontrada para os filtros selecionados" (`app/templates/partials/exposure.html:101`).
- Seletor: nenhuma `<option>` tem `selected` quando o id não está na lista (`performance.html:13-16`, `partials/exposure.html:17-20`). O navegador então exibe a primeira opção, "Todas". O rótulo "Todas" fica sobre um filtro de carteira 3 que resulta vazio.
- Nenhuma das telas diz que a carteira é simulada e não entra ali. A carteira "some" do seletor, e o id manual gera vazio sem explicação.

## 4. A mesma carteira no seletor de Carteira e Transações

| Tela | Função que monta o seletor | Lista inclui a simulada? | "Todas" exclui a simulada? |
|---|---|---|---|
| Carteira `/` | `portfolio_records()` (`positions.py:400`) | sim | sim (`positions_query`, `helpers.py:247`) |
| Transações | `portfolio_records()` (`transactions.py:285`) | sim | sim (`transactions.py:233-239`) |
| Performance | `real_portfolio_records()` (`performance.py:209`) | não | já excluída |
| Exposição | `real_portfolio_records()` (`positions.py:905`) | não | já excluída |

Na Carteira há um efeito a mais, por moeda: `positions_query` (`helpers.py:259-261`) aplica o filtro de moeda sobre `Ticker.currency` com padrão BRL. Como as posições da carteira 3 são todas de tickers USD (contagem abaixo), `/?portfolio_id=3` mostra vazio com o padrão, e só aparece com `currency=USD` ou `ALL`. Esse efeito vem do filtro global de moeda, não da carteira.

## 5. Hipótese de `currency` NULL: refutada

- `Portfolio.currency` é NULL na simulada de propósito (`app/models.py:311-313`: "currency é None para carteiras simuladas ... podem misturar tickers de moedas diferentes").
- O filtro de moeda lê `Ticker.currency` (`helpers.py:259-261`, `performance.py:73-78`), nunca `Portfolio.currency`.
- `Portfolio.currency` só é lido em formulários e no cadastro (`app/quotes/reference_data.py:83-109`, `app/routes/tables.py:395`).

## 6. Dados do banco local (contagens)

- Carteiras: 3. Simuladas: 1. Simuladas com `currency` não NULL: 0. Simuladas inativas: 0.
- Posições da carteira 3: 10, todas com ticker de moeda USD.
- Movimentos de posição da carteira 3: 10, todos do tipo `OPEN`, um por posição, sem `transaction_id`.
- Opções, arquivo de encerradas e transações da carteira 3: 0 em cada.
- Posições em carteiras reais: 10, todas com movimento.
- Datas de criação (sem valores): a carteira 3 aparece com `created_at` em 13/08 e os movimentos de suas posições com `created_at` em 12/08, antes da própria carteira. Isso sugere restauração ou cópia do banco, não fluxo normal do app. Hipótese, não verificada.

## 7. Achado colateral: `OPEN` em posição simulada (indeterminado)

- O código atual não deveria gerar isso: a criação só grava `OPEN` quando `not candidate.simulated` (`app/positions/closure.py:423-431`); `record_position_adjustment` retorna cedo para simulada (`closure.py:495-496`); e a troca para simulada chama `discard_simulation_history` (`app/routes/positions.py:662-663`).
- Com o dado atual, a exclusão explícita é a única coisa que impede Performance de mostrar o extrato da simulada. O docstring de `helpers.py:523-528` e `queries.py:77-78` diz que "posição simulada já não gera movimento", e isso é falso para esta cópia.
- Hipóteses, nenhuma confirmada: (a) dados gravados antes de uma das guardas; (b) restauração de dump; (c) escrita fora das rotas.

## Proposta mínima (não aplicada)

1. Manter a exclusão em `helpers.py:247-256`, `queries.py:114` e `positions.py:897`. Não remover.
2. Dar à tela um aviso explícito quando o `portfolio_id` pedido for de carteira simulada. Em `performance.py` (contexto de `monthly_performance`) e em `_render_exposure`, consultar `Portfolio.simulated` para o id e passar um booleano ao template. Nos templates `performance.html` e `partials/exposure.html`, incluir uma `<option ... selected disabled>` para a carteira pedida e uma linha de ajuda: "Carteira simulada: não entra em Performance nem em Exposição; veja-a na Carteira." Isso remove o "Todas" enganoso.
3. Atualizar `docs/planilha-acoes.md`: uma frase em "Performance mensal" e outra em "Exposição", e corrigir 444-446 para dizer o que o código faz.
4. Antes de qualquer mudança nos invariantes de simulada, investigar a origem dos 10 `OPEN` (contagens apenas) e corrigir os docstrings que afirmam que simulada não gera movimento.

## Teste que provaria o comportamento

Na camada `banco` (modelo: `tests/test_financial_isolation_http.py:33` e `:46`, com `app_com_banco`):
- Semear uma carteira real com uma posição e uma simulada com uma posição e um `OPEN` (como em `test_linha_do_tempo_de_posicoes.py:100-101`).
- `GET /performance?portfolio_id=<simulada>` e `GET /analysis/exposure-asset|broker|market?portfolio_id=<simulada>`: afirmar 200, aviso presente, nenhuma `<option>` da simulada marcada como selecionada, e ausência do ticker da simulada no HTML. Hoje o aviso falha; é o teste que caracteriza a proposta.
- `GET /?portfolio_id=<simulada>&currency=ALL` e `GET /transactions`: afirmar que a simulada continua listada e visível. Esses devem passar antes e depois, protegendo o comportamento intencional da Carteira.
- Opções de `/performance` sem o id da simulada, e opções de `/` com ele.

## Limites

- Não reproduzi por HTTP nem no navegador (proibido) e não rodei a suíte. O veredito vem de leitura de código, testes, docs, git e contagens.
- A origem dos `OPEN` da cópia local é hipótese.
