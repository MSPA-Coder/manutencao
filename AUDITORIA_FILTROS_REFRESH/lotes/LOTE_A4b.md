# Lote A4b (CB) — continuação do A4: só as telas 10 a 12

Base: http://127.0.0.1:5201/

**Território:**
- Conciliação e Reclassificação: **conta 8**, só linhas e lançamentos dessa conta.
- Atualizar saldo: uma das aplicações **16, 17, 18, 19 ou 24**.

Aqui você **pode** operar sobre registros existentes da conta 8, desde que
desfaça cada operação logo em seguida. Os dados são de teste, e o banco inteiro
será restaurado de uma cópia ao fim deste lote. Mesmo assim, desfaça e registre o
que não conseguir desfazer.

**Não** entre em Permissões, Configurações nem Tabelas: já foram cobertas.

Leia antes `PROTOCOLO.md`.

## Notas

- Este lote roda **sozinho**, depois que A1, A2 e A3 terminaram: mexe em cadastros que os outros usam.
- **Escrita financeira (só neste lote, porque roda sozinho; dados locais de teste):** em Conciliação, filtre a **conta 8** e opere só em linhas dessa conta: conciliar, desfazer a conciliação, ignorar, criar lançamento a partir da linha (depois exclua o lançamento criado em Lançamentos) e ação em lote com 2 linhas (depois desfaça). Em Reclassificação, filtre a conta 8, reclassifique **um** lançamento para outra categoria e, em seguida, devolva-o à categoria original. Se pedir para autorizar a reabertura de um mês fechado, autorize: os dados são de teste. Em Atualizar saldo, lance a diferença numa aplicação (contas 16 a 19 ou 24) e depois exclua o lançamento gerado. Meça cada passo com a sonda.
- Gerencial: o executor A2 deixou um orçamento de teste (categoria Outros, 09/2026) sem prefixo. Retire-o pela tela de Gestão (titular Maridito) e meça a operação.
- Tabelas: aplique o filtro da tabela (titular, instituição, tipo), role, e então crie, edite e exclua a sua entidade. Também edite em linha, se houver.
- Configurações gerais (política de senha, bloqueio, projeção recorrente): **leia o valor atual, salve o MESMO valor** e meça a resposta. Não mude política.
- Permissões: selecione outro usuário no filtro, marque e desmarque uma permissão e devolva o estado original. Confira se o usuário selecionado continua selecionado.
- Banco de dados: verificação de saúde pode rodar; **otimizar não**. Registre só a existência.

## Casos

### 10. `banking/reconciliation/`
- filtros detectados: nenhum no template (procure na tela)
- **10.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **10.1** operação `bank_statements:bulk_action_lines` (2 controles); resposta prevista: redirect-sem-query
- **10.2** operação `bank_statements:reconcile`; resposta prevista: redirect-sem-query
- **10.3** operação `bank_statements:create_entry_from_line`; resposta prevista: redirect-sem-query
- **10.4** operação `bank_statements:ignore_line`; resposta prevista: redirect-sem-query
- **10.5** operação `bank_statements:undo_reconciliation`; resposta prevista: redirect-sem-query
- **10.X** outras operações visíveis na tela e não listadas acima: teste e registre como `10.X<n>`.

### 11. `banking/reclassification/`
- filtros detectados: conta, de, ate, categoria, banco, texto, importados
- **11.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **11.1** operação `bank_statements:reclassificacao` (2 controles); resposta prevista: redirect+query
- **11.X** outras operações visíveis na tela e não listadas acima: teste e registre como `11.X<n>`.

### 12. `banking/balance/`
- filtros detectados: nenhum no template (procure na tela)
- **12.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **12.1** operação `bank_statements:atualizar_saldo` (2 controles); resposta prevista: redirect+query?
- **12.X** outras operações visíveis na tela e não listadas acima: teste e registre como `12.X<n>`.

