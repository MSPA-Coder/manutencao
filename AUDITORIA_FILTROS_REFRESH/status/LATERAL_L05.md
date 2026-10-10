# L05: seletor de contrato oferece contratos vencidos (ControleRendaVariavel)

Data: 09/10/2026. Investigação somente leitura: nenhum arquivo do repositório foi alterado, nada foi commitado, nenhum navegador foi usado. Não rodei a suíte de testes.

## Veredito

**DEFEITO.** A recusa no POST é intencional (regra de negócio, documentada e testada). O seletor de contrato não aplica o filtro que essa regra implica, então oferece exatamente o que o servidor vai recusar. A correção deve ser no seletor, com cuidado para não quebrar a edição.

## Evidência

### 1. Onde o seletor é montado e qual filtro aplica

- `app/routes/options.py:152-163`, função `_contracts()`: `SELECT OptionContract` com `joinedload` de ticker, ativo-objeto e vencimento, `order_by(OptionExpiration.exercise_date, OptionContract.id)`. **Não há nenhum WHERE sobre a data.**
- Chamadas de `_contracts()`: `new_position` (linha 254), `create_position` nos três caminhos de erro (270, 283, 300), `edit_position` (326) e `update_position` nos dois caminhos de erro (347, 367).
- Template `app/templates/option_form.html:33-38`: `{% for contract in contracts %}` renderiza todos os contratos. Não há filtro, marcação de "vencido" nem desabilitação. O rótulo (linha 36) é ticker, tipo e data de exercício.

### 2. Regra que recusa no POST

- `app/routes/options.py:166`: `_parse_position(*, permitir_contrato_vencido: bool = False)`.
- Linhas 189-192: se `not permitir_contrato_vencido and contract.expiration.exercise_date < date.today()`, lança `ValueError("Não é possível abrir uma posição em um contrato já vencido.")`.
- `create_position` (linha 263) chama sem a flag, então recusa. O erro volta por `flash` com status 422, e o formulário é re-renderizado com a mesma lista de `_contracts()`, ou seja, com o vencido de novo disponível.
- `update_position` (linha 337) chama com `permitir_contrato_vencido=True`, então a edição aceita qualquer contrato, vencido ou não.
- Limite: `<` estrito. Contrato que vence hoje ainda é aceito.

### 3. Intenção

- **Commit 06f0540** (PR #43, 01/09/2026, "Concluir prioridades e ciclo de vida"): introduziu a recusa e o parâmetro `permitir_contrato_vencido`. O diff desse commit não adiciona nenhum filtro de data em `_contracts()`.
- **`docs/planilha-opcoes.md:70-76`**, seção "Vencimentos": "Um contrato cuja data de exercício já passou continua consultável no histórico, mas não pode receber uma nova posição aberta." A doc diz consultável, não cadastrável. O seletor contradiz a doc.
- **`tests/test_audit_priorities.py:58-86`**, `test_new_option_position_rejects_expired_contract`: afirma a recusa com a mensagem "contrato já vencido" e afirma que o caminho com a flag (edição) aceita. Nenhum teste verifica o conteúdo do seletor. O único contato dos testes com `_contracts` é `tests/test_htmx_persistence.py:109`, que o substitui por `lambda: []`.
- Não encontrei, em código, doc ou teste, nenhum uso previsto de "registrar posição histórica" em contrato vencido.

### 4. A mesma lista serve à edição?

Sim, e é aqui que a correção precisa de cuidado:

- `edit_position` (321-330) usa o mesmo template com a posição atual. A opção selecionada depende de `value.contract_id|int == contract.id` (template, linha 36).
- Se o contrato atual da posição já venceu e o filtro o remove, a opção selecionada some. O `<select required>` cai em "Selecione", e a pessoa é obrigada a trocar de contrato para salvar uma edição simples (quantidade, custo, target). Um filtro sem exceção para o contrato atual quebra a edição.
- Hipótese H2 (não verificada em runtime): `update_position` aceita a flag para qualquer contrato, não só para o atual. Isso permite mover uma posição viva para um contrato vencido, o que a doc trata como "nova posição aberta". A flag parece ter sido criada para o contrato atual, mas não se limita a ele.

### 5. Banco local (somente SELECT, só contagens)

- Contratos no total: 6. Contratos já vencidos: 1. Posições apontando para contrato vencido: 0.
- Consistente com o sintoma: ao menos um vencido aparece no seletor.
- Por ter 0 posições em contrato vencido, o caso "posição aberta cujo contrato venceu depois de cadastrada" não aparece nesta cópia. É o cenário em que a edição quebraria com um filtro ingênuo, e pode existir em produção (não verificado).

## Hipóteses

- **H1** (forte): vencido no seletor não é intencional. Sustentada pela doc, pelo teste e pela mensagem explícita da recusa.
- **H2** (a verificar): a edição permite mover posição para contrato vencido. Se for indesejado, deve ser fechado junto com a correção, e é decisão do dono do produto.
- **H3** (menor): `date.today()` (relógio do processo Python) é usado na recusa, enquanto o banco usa `CURRENT_DATE`. Perto da meia-noite podem divergir. O filtro novo deve usar a mesma fonte (`date.today()`) que a recusa.

## Proposta mínima (não aplicada)

- **P1, seletor**: `_contracts(contrato_atual_id: int | None = None)` filtra com `or_(OptionExpiration.exercise_date >= date.today(), OptionContract.id == contrato_atual_id)`. Usar `>=` mantém o mesmo limite da recusa (vence hoje continua válido).
  - `new_position` e os caminhos de erro de `create_position`: sem contrato atual, só vivos.
  - `edit_position` e `update_position`: passam `position.contract_id`, para o contrato atual continuar selecionável.
  - Não usar `disabled` na opção vencida: um `<option disabled selected>` não é enviado, e o `required` barraria a edição.
- **P2, validação da edição** (depende de H2): trocar `permitir_contrato_vencido: bool` por `contrato_atual_id`, aceitando contrato vencido só se `contract_id == position.contract_id`. Assim, editar a posição sem trocar de contrato continua funcionando, e não é possível mover posição viva para vencido.
- **Ajuste colateral**: o stub de `tests/test_htmx_persistence.py:109` (`lambda: []`) precisa aceitar o novo argumento (`lambda *a, **k: []`), senão quebra.
- Fora de escopo: permitir registrar posição histórica. Seria decisão de produto e mudaria a doc.

## Testes que provariam a correção

- **T1, seletor (HTTP, falha hoje)**: logado, criar três vencimentos com datas de exercício ontem, hoje e hoje+30, cada um com um contrato. `GET /options/new`: o contrato de ontem não aparece no HTML; o de hoje e o de hoje+30 aparecem.
- **T2, edição preservada (HTTP, passa hoje, deve continuar passando)**: criar a posição direto no banco, pois o POST recusaria, depois que o contrato venceu. `GET /options/positions/<id>/edit`: o contrato atual aparece, com `selected`. Esse teste fica vermelho se P1 for aplicado sem a exceção do contrato atual.
- **T3, edição não migra para vencido (HTTP, só se P2 for aceito)**: `POST /options/positions/<id>` com `contract_id` de outro contrato vencido retorna 422 com a mensagem da recusa. Com o próprio contrato vencido, a edição é aceita.
- **T4, unitário**: atualizar `test_new_option_position_rejects_expired_contract` para a nova assinatura, mantendo a asserção da recusa.

## Arquivos consultados

- `app/routes/options.py`, `app/templates/option_form.html`
- `docs/planilha-opcoes.md`, `tests/test_audit_priorities.py`, `tests/test_htmx_persistence.py`
- `git show 06f0540`, `git log -S`
