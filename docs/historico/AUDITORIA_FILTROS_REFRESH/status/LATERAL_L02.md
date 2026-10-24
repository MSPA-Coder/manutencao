# L02 — Descrição vazia aceita e transferência criada duas vezes

Data: 09/10/2026. Repositório: `C:/Dev/VSCodeProjects/ControleBancario` (somente leitura; nenhum arquivo do repo alterado; sem commit; sem navegador). Banco consultado só com SELECT.

## Vereditos

| # | Item | Veredito |
|---|------|----------|
| 1a | Descrição vazia aceita pelo servidor | **Indeterminado** (decisão de produto). O código indica desenho opcional; nada escrito no domínio e a tela não diz isso. |
| 1b | Blank descrição quebra telas/relatórios | **Sem quebra encontrada.** Degrada sugestões de conciliação e deixa célula vazia na tabela. |
| 2 | Duplicidade (envio duplo cria 2 grupos) | **Defeito.** Nenhuma proteção no servidor nem no cliente. |

Hipótese principal do item 2 (não reproduzida no banco): duplo envio enquanto a resposta demora. Ver "Estado do banco".

## 1. Descrição

**Fatos**
- `transactions/models.py:218`: `CashFlowEntry.description = CharField(max_length=255, blank=True)`. Blank desde a versão inicial (`git log -S description` aponta só para `e0c9f6d`, release V2.0). Nenhum commit posterior mudou isso.
- `transactions/views.py:129-130`: a validação de campos obrigatórios em `_transaction_request_from_post` lista conta, categoria, tipo, valor e vencimento. Descrição fica de fora.
- `transactions/views.py:146`: `description = (post.get("description") or "").strip()`.
- `transactions/services.py:1110-1111`: o serviço só valida o tamanho máximo, não a presença. Mesma regra para criação e edição (`_validate_common_payload`).
- `templates/transactions/_fields.html:62`: input sem `required`, placeholder "Ex: Supermercado, salário...", sem marca de opcional.
- Contraste: `templates/management/partials/management_content.html:27` rotula o campo como "Opcional". A tela de Lançamentos não faz isso.
- `docs/domain.md`: não define obrigatoriedade da descrição (busca por "obrigat" e "descri" sem regra sobre o campo).
- Testes: nenhum teste cobre descrição vazia nem exige descrição (busca por `description=""` e variantes vazia).

**Consumidores que assumem valor (verificado por leitura)**
- `templates/transactions/_table_body.html:56`: `{{ t.description }}` sem `default:"-"`. A célula fica vazia. `_operations_table.html:79` usa `default:"-"`, então o padrão não é uniforme. `banking/account_detail.html:57` também não tem fallback.
- `reports/services.py:874`: `entry.description.strip() or "Sem descrição"`. O relatório anual já trata vazio. Sinal de que o desenho tolera vazio.
- `bank_statements/classificacao.py:145-146`: `categoria_do_historico` retorna `None` quando a chave é vazia. Sem sugestão, sem erro.
- `bank_statements/fatura.py:184`: a parcela da fatura casa por `description__in=_descricoes(linha)`. Lançamento sem descrição nunca casa com linha de extrato. Degradação da conciliação, não corrupção.
- `bank_statements/reclassificacao.py:260` e `:263`: a chave vazia não entra em `termos`, e `icontains` com termo vazio não é usado. Não encontrei varredura em massa por descrição vazia. Verificado por leitura, sem teste de comportamento.
- Transferências: `transactions/services.py:1188-1192` grava na ponta `"Conta Destino: ..."` / `"Conta Origem: ..."` em vez da descrição digitada. A descrição digitada vai só para `BankOperation.description` (`:1182`). Ou seja, em transferência a descrição vazia não gera lançamento sem descrição.

**Veredito 1a (indeterminado).** O código trata descrição como opcional por construção (model, relatório, texto "Opcional" em outra tela). A ausência de regra no domínio e a tela sem indicação tornam isso uma decisão implícita. Se a decisão for "opcional", o defeito é de UX (célula vazia sem "-", campo sem rótulo). Se a decisão for "obrigatória", o defeito é o serviço aceitar, e o `required` do HTML sozinho não basta, porque o POST passa por fora.

**Proposta (1a), não aplicada**
- Se obrigatória: em `transactions/views.py:129-130` incluir `post.get("description")` na checagem (ou validar no serviço, `services.py:1110`, para cobrir edição e outros chamadores). Adicionar `required` em `_fields.html:62`. Para transferência, validar a descrição digitada (vai para `BankOperation`).
- Se opcional: rotular "Opcional" em `_fields.html:61-62` (igual à tela de gestão), e trocar `{{ t.description }}` por `{{ t.description|default:"-" }}` em `_table_body.html:56` e `banking/account_detail.html:57`.

**Teste proposto (1a)**
- Se obrigatória: `django_db`, POST de criação sem `description` e com `description="   "`; esperado: `ValueError` ou resposta de erro, e contagem de `CashFlowEntry` inalterada. Hoje: grava.
- Se opcional: teste de render da tabela com descrição vazia mostrando "-", e teste de que `categoria_do_historico("")` e a sugestão de fatura não casam lançamento sem descrição.

## 2. Duplicidade e reenvio

**Servidor**
- `transactions/views.py:287-314` (`_transaction_new_post`): não há token de idempotência nem checagem antes da gravação. `create_transaction_batch` (`services.py:1117`, `@db_transaction.atomic`) grava sem checar se o mesmo lançamento já existe.
- A checagem existe, mas só depois do commit: `views.py:304-310` chama `possible_duplicates_for_created_entries` (`services.py:1275-1294`) e apenas emite `messages.warning` ("Atenção: existem movimentos semelhantes..."). Não bloqueia nem pede confirmação. Compara conta, tipo, valor e vencimento, e para transferência só olha a ponta de origem.
- Não há unicidade no banco: `operation_key` usa `uuid4` (`services.py:1180`), e `CashFlowEntry` não tem `UniqueConstraint` de negócio (a única `UniqueConstraint` do módulo, `transactions/models.py:365`, é de `AccountMonthClose`). Duas gravações viram dois grupos.
- A serialização por `_lock_accounts` (`services.py:1157`) impede corrida na saldo, mas não impede duas criações válidas em sequência.
- Sem teste: nenhum teste cobre `possible_duplicates_for_created_entries` nem o aviso (busca por "semelhante", "duplicidade" em `tests/` vazia).
- Referência do projeto irmão: `ControleRendaVariavel/app/routes/options.py:278-279` e `positions.py:537` checam duplicata **antes** de gravar e devolvem o formulário com aviso, a menos que `confirm_duplicate=1`. O aviso (`option_form.html:14-18`) diz "se você clicou duas vezes em Salvar, cancele". No CB o mesmo aviso chega depois da gravação.

**Cliente**
- `templates/transactions/index.html:85`: formulário "Novo lançamento" é POST de página inteira (sem `hx-post`), `keep_entry_form_open=1`.
- `index.html:91-95`: o botão Salvar tem `data-sa-confirmar` e **não** é desabilitado no envio.
- Fluxo: clique → `sharedauth-ui.js` (`.venv/Lib/site-packages/sharedauth/ui/estatico/sharedauth-ui.js:344-380`) intercepta na captura, abre o modal, e ao confirmar chama `form.requestSubmit(alvo)` (`:354-366`). Enquanto a resposta não chega, o botão continua habilitado. Um novo clique (ou Enter) abre o modal de novo e dispara outro POST.
- `static/js/core/application.js:167-170`: a trava `data-submitting` vale só para `[data-global-currency-form]`. O formulário de lançamento não tem.
- `static/js/transactions.js:262-310` (`_initEditScopeConfirm`): tem um guarda próprio, mas só para o formulário de edição com `operation_scope`. Retorna cedo no formulário novo (`:266-270`).
- Feedback: não há indicador de carregamento no formulário (o único `htmx-indicator` de upload está em `banking/imports.html:43`). Depois do POST, `views.py:316-323` reabre o card com `new_account_id`, `new_entry_type`, `new_status` e `new_due_date`, mas **não** devolve descrição, valor nem categoria. O usuário vê um formulário limpo, com a mensagem de sucesso só no topo (`templates/base.html:41`, flash). Isso favorece reenviar.

**Veredito 2: defeito.** Não há proteção em nenhuma camada. O cliente permite reenvio durante a espera, e o servidor aceita os dois envios como lançamentos distintos.

**Hipótese (não verificada) do caso observado:** o primeiro "Salvar" gravou, a página demorou ou pareceu não responder, o usuário clicou de novo e o segundo POST criou o segundo grupo. Se for isso, a segunda resposta teria trazido o aviso "movimentos semelhantes ... #<id do primeiro grupo>" (`views.py:307-310`). Esse aviso é o sinal para conferir na tela do caso real.

**Proposta mínima (2), não aplicada**
1. Cliente: marcar o formulário novo (ex.: `data-single-submit` em `index.html:85`) e estender a guarda de `application.js:167-170` para ele. No submit: `form.dataset.submitting='1'`, desabilitar o botão e trocar o texto para "Salvando...". A guarda roda no evento `submit`, que só dispara depois da confirmação do modal, então cancelar não bloqueia o formulário.
2. Servidor (idempotência): hidden `submit_token` (uuid4) gerado a cada render do formulário em `index.html:85`. Em `_transaction_new_post`, antes de `create_transaction_batch`, reservar com `django.core.cache.cache.add(f"tx-submit:{user.pk}:{token}", 1, timeout=600)`. Se `add` devolver `False`, responder com aviso "Este lançamento já foi enviado" sem gravar. `add` é atômico no backend de cache. Não verifiquei o backend configurado em `financeiro/settings.py`; se for um backend por processo, a reserva precisa ir para o banco.
3. Opcional, depois: trocar o aviso pós-gravação por checagem antes da gravação com `confirm_duplicate`, como no ControleRendaVariavel. Muda o fluxo de UX; não é necessário para o caso de envio duplo.
4. Opcional: no reabrir do card (`views.py:316-323`), manter valor e descrição para o usuário ver o que acabou de gravar.

**Teste proposto (2)**
- `django_db`, camada de view: POST duas vezes com o mesmo `submit_token` → uma `BankOperation` e um grupo de entradas; a segunda resposta traz o aviso e não cria nada. Hoje: dois grupos.
- `django_db`, camada de serviço: `create_transaction_batch` com a mesma requisição reservada duas vezes → a segunda falha. Hoje: sem erro.
- Cliente: sentinela de leitura de `application.js` e `index.html` (padrão de `tests/test_financial_mutations.py:359`). É fraco, porque nenhum teste executa o navegador (`docs/TESTES.md`, T6). O comportamento do botão fica com verificação manual na tela, não automatizada.

## Estado do banco local (somente leitura)

- `cash_flow_entry` com descrição vazia: 1 linha em toda a base (id 904, conta 3, despesa 29,30, criada em 05/05/2026). Não é do caso relatado.
- Conta 20 (cartão, citada no caso 1): 608 lançamentos, nenhum com descrição vazia, e nenhum criado em 09/10. O caso 1 não aparece no banco: foi apagado, editado depois, ou não foi gravado. Não consigo confirmar pelo banco.
- Transferências criadas em 09/10: uma única operação, `bank_operation` id 740 (`internal_transfer`, `installment_total=1`, descrição "[AUD-B1b] R047 transf", criada 13:00:15), com as entradas 3868 (conta 8, despesa) e 3869 (conta 9, receita), vencimento 20/11/2026. Não há segundo grupo, e nenhuma transferência parcelada do caso 2. O caso 2 não está reproduzido no banco. A operação 740 é de teste de outro agente, então não serve como evidência do caso.
- Outras operações de 09/10: 737 (parcelado, "[AUD-B1b] R005 parcelado", 12:34) e as entradas de conta 8. Também de outro agente.

## Limites

- Não usei navegador, então não vi a tela, o modal nem a resposta de rede do caso real.
- Não executei a suíte de testes: a suíte depende do Docker `quality` para a camada com banco.
- As hipóteses do item 2 e a conclusão sobre o caso 1 estão marcadas como hipótese ou indeterminadas acima. O veredito de defeito do item 2 vem do código, não de reprodução.
