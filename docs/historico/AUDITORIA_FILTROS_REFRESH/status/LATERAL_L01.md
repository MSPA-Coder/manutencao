# L01 — Desfazer realização grava "vencidos" com vencimento futuro

Data: 09/10/2026. Repositório: `C:/Dev/VSCodeProjects/ControleBancario` (somente leitura; nenhum arquivo do repo alterado; sem commit; sem navegador).

## Veredito

**Defeito.** A escolha de devolver sempre para `STATUS_PENDING` é deliberada e documentada no service. O defeito está no que essa escolha produz: um lançamento com vencimento futuro gravado como `vencidos` não aparece em nenhuma das duas visões que deveriam mostrá-lo ("A vencer" e "Vencidos"). Ele só aparece em "Todos". O próprio diálogo ("voltará para Vencidos") é falso para vencimento futuro.

## Evidência

**1. Caminho da escrita**
- `transactions/views.py:250-275` — `mark_unrealized` chama `unrealize_transaction(...)` e informa "Lançamento retornado para Vencidos." (linha 266).
- `transactions/services.py:306-366` — `unrealize_transaction`. Linhas 335-338 gravam `entry.status = STATUS_PENDING` e limpam `realized_date`/`realized_amount`, sem olhar `due_date`. Linhas 341-344 fazem o mesmo na contraparte de transferência. Linhas 346-353 ajustam o `BankOperation` com `.update(status=STATUS_PENDING)`.
- O docstring (linhas 308-315) justifica: inferir pela data "poderia devolvê-lo como 'a vencer' e escondê-lo da tela onde o usuário acabou de agir". Essa justificativa não se sustenta, porque a própria matriz de listagem esconde o lançamento (ver item 3).

**2. Intenção**
- `docs/domain.md` não registra a regra de desfazer. O único registro é o docstring.
- `git log -S "def unrealize_transaction"` e `-S "escondê-lo"` apontam só para `e0c9f6d` (versão inicial consolidada V2.0, 2026-08-16). A regra "sempre PENDING" é original do sistema.
- `git log -S "voltará para Vencidos"` aponta só para `ef3061e` ("Permite desfazer realização de lançamentos (#93)", 2026-09-25). Esse commit trouxe o botão, o diálogo, a mensagem e os testes de `tests/test_desfazer_realizacao.py`.
- Hipótese (não verificada): a regra foi pensada para o caso de vencimento passado, e o caso futuro não foi considerado.

**3. Regra de status e listagem (o ponto central)**
- `core/domain/finance.py:13-15`: `STATUS_PROJECTED = "a_vencer"`, `STATUS_PENDING = "vencidos"`.
- `reports/services.py:1251-1261` — `_listing_status_q` (usada por `transactions/services.py:1971` e pelo motor de projeções):
  - `VIEW_PROJECTED` ("A vencer", padrão da tela, `transactions/services.py:2146`): `status='a_vencer' AND due_date >= hoje`.
  - `VIEW_PENDING` ("Vencidos"): `(status='vencidos' AND due_date < hoje) OR (status='a_vencer' AND due_date < hoje)`.
  - `VIEW_ALL`: sem filtro.
- `reports/services.py:1047-1061` — `_balance_status_q` segue a mesma matriz para saldo.
- Consequência: `vencidos` com vencimento futuro não casa com nenhum filtro das duas visões.
- Assimetria: a matriz tolera `a_vencer` gravado com vencimento passado (cai em "Vencidos"), mas não tolera `vencidos` gravado com vencimento futuro.
- Regra efetiva publicada: `docs/architecture.md:260-267` e `core/patrimonio.py:326-337` — em aberto com vencimento futuro é `a_vencer`, qualquer que seja o status gravado. `leitura.lancamento` faz o mesmo (`core/migrations/0004_esquema_leitura.py:51`).
- Edição normaliza: `transactions/services.py:824-832` (`_normalize_open_entry_status`) é chamada na gravação (linhas 1085, 1558, 1202, 861). Nenhum caminho de leitura recalcula o status.

**4. Banco local (somente SELECT, 09/10/2026, `leitura.hoje()` = 2026-10-09)**
- `leitura.lancamento` para id 1382: `status_gravado=vencidos`, `status=a_vencer`, `vencimento=2026-11-09`, `realizado_em` vazio, `valor_previsto=187.00`.
- Filtro de listagem reproduzido em SQL para o id 1382: "A vencer" = 0 linhas; "Vencidos" = 0 linhas; "Todos" = 1 linha. Ou seja, o lançamento some da tela de onde foi desfeito.
- Distribuição `status_gravado` x `status` em todo o banco local: `a_vencer|a_vencer` 175; `a_vencer|vencidos` 8 (envelhecidos, esperado e já tratados pela matriz); `realizado` 1535; `vencidos|vencidos` 5; `vencidos|a_vencer` 1 (só o 1382). Com o banco local de teste, o 1382 é o único caso do tipo, mas o defeito se reproduz a cada desfazer de lançamento com vencimento futuro.
- Nota: a tabela física é `cash_flow_entry` (`transactions/models.py:258`); a consulta direta a `transactions_cashflowentry` falhou por nome, sem efeito.

**5. Testes**
- `tests/test_desfazer_realizacao.py:61` usa `due_date=date.today()` (hoje), e `:76` e `:95-96` afirmam `("vencidos", None, None)`. O teste fixa o valor gravado e não verifica listagem. Com vencimento = hoje, a regra efetiva dá `a_vencer`, então o teste também pina o defeito.
- Nenhum teste cobre `list_transactions_for_view` ou `_listing_status_q` com `vencidos` de vencimento futuro (busca em `tests/`).
- `tests/test_audit_atomicity_repairs.py:83` afirma `STATUS_PENDING` após desfazer, mas com `due_date=2026-09-10` (passado). Continua válido sob qualquer proposta abaixo.
- `tests/test_patrimonio_autenticacao_e_v4.py:270-307` já fixa a regra efetiva ("o status gravado envelhece"), mas só para leitura, não para o caminho de desfazer.

**6. Outros caminhos com o mesmo problema**
- Desfazer conciliação: `bank_statements/reconciliation.py:600-616` (`undo_reconciliation`) chama `unrealize_transaction` (linha 612). Herda o defeito.
- Desfazer importação: `bank_statements/reconciliation.py:620-` (`undo_statement_import`) usa `undo_reconciliation` linha a linha. Herda o defeito.
- Reabrir mês: `transactions/services.py:439` (`reopen_month`) não altera status nas linhas 439-475 (checado). Sem o defeito.
- Editar vencimento: a gravação normaliza (`transactions/services.py:1085`, `1558`). Corrige-se só quando alguém salva; nada corrige sozinho. Sem o defeito direto, mas o registro fica errado até a próxima gravação.
- Status da operação (`BankOperation`): `transactions/services.py:1017-1033` (`_sync_bank_operation_status`) e a escrita direta em `transactions/services.py:351-353` gravam `vencidos` pelo grupo sem olhar a data. Mesmo padrão, em outra entidade. Não verifiquei em qual tela o status da operação é lido; é um ponto a checar.
- Projeção recorrente (`transactions/middleware.py`): não escreve status; cria pelos services normalizados. Sem o defeito.

**7. Texto do diálogo**
- `templates/transactions/index.html:147`: "O lançamento deixará de compor o saldo realizado e voltará para Vencidos." Fica falso para vencimento futuro.
- `transactions/views.py:266`: "Realização desfeita. Lançamento retornado para Vencidos."
- `transactions/services.py:363`: resumo de auditoria "Lançamento retornado para vencidos."

## Caminhos afetados

- `transactions/services.py:306-366` (`unrealize_transaction`) — origem única da escrita; corrigir aqui cobre a tela, a conciliação e a importação.
- `transactions/services.py:346-353` (`BankOperation`), `transactions/services.py:1017-1033` (`_sync_bank_operation_status`) — mesmo padrão, verificar.
- `reports/services.py:1047-1061` e `1251-1261` — matriz de saldo e listagem (só muda se a opção B abaixo for escolhida).
- `templates/transactions/index.html:147`, `transactions/views.py:266`, `transactions/services.py:363` — textos.
- `tests/test_desfazer_realizacao.py` — expectativas de status (linhas 76, 95-96) e fixture de data.

## Proposta de correção (não aplicada)

**Opção A (recomendada, mínima):** no `unrealize_transaction`, gravar o status que a própria regra de normalização daria, em vez de `STATUS_PENDING` fixo:
- `entry.status = _normalize_open_entry_status(STATUS_PENDING, entry.due_date)`; o mesmo para a contraparte.
- Vencimento passado: `vencidos`. Vencimento hoje ou futuro: `a_vencer`.
- Ajustar o `BankOperation` com o mesmo critério (derivar do status dos lançamentos, como `_sync_bank_operation_status` já faz, ou aplicar a normalização ao grupo).
- Texto do diálogo: "O lançamento deixará de compor o saldo realizado e voltará para A vencer (ou para Vencidos, se o vencimento já passou)." Mesma mudança na mensagem de sucesso e no resumo de auditoria.
- Atualizar o docstring: a justificativa atual ("escondê-lo") deixa de valer e deve ser substituída pela regra de normalização.
- Efeito: grava sempre o status efetivo; a leitura, o saldo e a listagem concordam. Não exige mudar a matriz.

**Opção B (alternativa, mais ampla):** manter `vencidos` gravado e estender a matriz para aceitar `vencidos` com vencimento futuro nas visões "A vencer" e "Vencidos", em `reports/services.py:1047-1061` e `1251-1261`. Descartada como primeira escolha: deixa o status gravado divergente da regra efetiva publicada (`leitura.lancamento`, snapshot v4 `effective_status`) e exige mudar quatro ramos da matriz.

## Teste proposto (comportamento, não texto)

Em `tests/test_desfazer_realizacao.py` (ou arquivo novo ao lado), parametrizado por vencimento:

1. Criar um lançamento realizado com `due_date = hoje + 30 dias`, desfazer pelo service (e um caso pela view `mark_unrealized`).
   - Afirmar que ele aparece em `list_transactions_for_view(view_mode=VIEW_PROJECTED, ...)` (A vencer) e não em `VIEW_PENDING`.
   - Afirmar que `leitura`/`effective` (ou `status_efetivo`) dá `a_vencer`, e que o status gravado coincide com ele.
2. Mesmo teste com `due_date = hoje - 30 dias`: deve aparecer em `VIEW_PENDING` e o status gravado deve ser `vencidos`.
3. Caso de borda `due_date = hoje`: deve aparecer em `VIEW_PROJECTED`.
4. Caminho de conciliação: desfazer uma conciliação de linha de extrato com vencimento futuro e afirmar o mesmo resultado de listagem.

Esses testes medem o que o usuário vê (em qual lista o lançamento aparece), não o texto do status. Os testes atuais em `tests/test_desfazer_realizacao.py:76` e `:95-96` (que usam hoje como vencimento) precisarão de nova expectativa, porque hoje passa a dar `a_vencer` pela regra nova. Essa mudança é de regra de domínio e deve ser decidida pelo mantenedor antes de ajustar o teste.

## Pontos em aberto (hipóteses, não verificadas)

- Não rodei a suíte (`quality` ou venv) para confirmar a reprodução por teste; a conclusão sobre a listagem vem da leitura da matriz e da reprodução em SQL do filtro, não de execução do Django.
- Não verifiquei em qual tela o status de `BankOperation` é exibido nem se ele alimenta alguma listagem.
- A decisão entre Opção A e B cabe ao mantenedor. A recomendação da Opção A segue a regra publicada (`docs/architecture.md:260-267`).
