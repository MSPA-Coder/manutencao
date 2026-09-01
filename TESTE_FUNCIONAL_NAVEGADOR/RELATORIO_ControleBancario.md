# Relatório — ControleBancario (CB)

Alvo: http://127.0.0.1:5201. Sessão herdada como `mspa` (administrator, não is_staff).
Início: 2026-08-31.

Regra de ouro observada: acervo real de 714 lançamentos, 10 contas, 3 titulares,
21 categorias. Todo registro de teste usa prefixo `ZZTESTE`.

---

## Bloco 1 — Varredura do menu

Sessão confirmada logo de início: `/dashboard/` (raiz `/`) carregou direto, sem
tela de login, com dados reais (gráficos, índices de saúde financeira). Rodapé
do menu mostra `mspa — administrator` com botão "Sair" (não acionado).

Estrutura do menu lateral batida item a item com o roteiro do prompt:
Dashboard; Movimentação (Lançamentos, Lançamentos n+1, Banking → Importação de
extrato, Conciliação, Comprovantes, Fechamento mensal); Relatórios (Próximos
movimentos, Projeções, Posição por conta, Planejamento anual, Controle
gerencial); Cadastros (Titulares, Instituições, Contas, Categorias);
Configurações (Perfil e tema, Contas em análises, Parâmetros, Banco de dados);
Segurança (Alterar senha, Permissões, Trilha de auditoria). Todas as 22 rotas
listadas no prompt foram abertas e carregaram sem erro (200, título de página
coerente, console limpo — conferido com `read_console_messages onlyErrors`
depois da varredura completa).

Comportamento do menu: submenu de 1º nível (Movimentação) expande/recolhe ao
clicar; submenu aninhado de 2º nível (Banking dentro de Movimentação) também
expande corretamente, mostrando os 4 itens esperados. Navegação direta para uma
URL profunda (`/tables/categories/`) auto-expandiu o grupo pai correto
(Cadastros) e marcou o item ativo (Categorias) em destaque — sem resíduo de
outro grupo aberto. Nenhuma divergência de rótulo encontrada.

Contagens de cadastro conferem com o acervo declarado: 3 titulares (Cláudia,
Esther, Mariano), 7 instituições, 10 contas, 21 categorias (20 "Normal" + 1
"Interna" — Transferência Entre Contas).

**Teste de autorização `/admin/` (item central deste bloco):** acesso direto
por URL redirecionou para `/admin/login/?next=/admin/` (200 OK) exibindo a
tela padrão de login do Django com o aviso "Você está autenticado como mspa,
mas não está autorizado a acessar esta página. Você gostaria de realizar login
com uma conta diferente?". Não foi digitada senha. Item "Administração" também
**não aparece** no menu lateral para `mspa`. Comportamento correto do
`staff_member_required` do Django — registrado como observação, não como
defeito.

### [CB-01] "Posição por conta": coluna Geração de Caixa não fecha por linha com o Saldo Final (falta a transferência interna)
- **Severidade:** Inconsistência
- **Onde:** Relatórios > Posição por conta — `/reports/account-position/`
- **Passos:** 1. Abrir o relatório. 2. Somar "Saldo Inicial" + "Geração de Caixa" de cada linha e comparar com "Saldo Final" exibido.
- **Esperado:** Saldo Inicial + Geração de Caixa = Saldo Final em cada linha (ou uma coluna explicando a diferença).
- **Obtido:** No total geral fecha certinho (R$ 11.056,18 − R$ 3.803,00 = R$ 7.253,18). Mas por conta há linhas que não fecham: Cláudia/Itaú: R$ 13,61 + R$ 1.790,81 = R$ 1.804,42, exibido R$ 390,42 (diferença de R$ 1.414,00); Cláudia/Mercado Pago: R$ 4.057,58 + (− R$ 2.899,93) = R$ 1.157,65, exibido R$ 2.571,65 (diferença de R$ 1.414,00, sinal oposto). A diferença bate com uma transferência interna entre as duas contas que a coluna "Geração de Caixa" deste relatório não contempla (diferente do relatório "Próximos movimentos", que tem coluna própria "Transf. int."). No agregado as duas pontas se cancelam e o total bate, mas por linha o usuário não consegue conferir a conta sem uma coluna de transferências internas.
- **Evidência:** texto da tabela, ver acima; sem erro de console/HTTP envolvido, é conta feita à mão.
- **Vale para os outros sistemas?** não — é específico do modelo de contas/transferências internas do ControleBancario.

Sem erros de console em nenhuma tela visitada neste bloco.

## Bloco 2 — Cadastros (inclusão, alteração, exclusão)

Ciclo de Titular, Instituição, Conta e Categoria com prefixo `ZZTESTE`. Padrão
de UI comum às 4 telas: campo "Novo/Nova" no topo, "Incluir" abre modal
"Confirmar cadastro" (Cadastrar/Cancelar) antes de gravar; cada linha tem
Editar (alterna uma linha oculta com formulário) e Excluir (abre modal
"Excluir X? Esta ação não pode ser desfeita." antes de gravar). Bom padrão de
confirmação, consistente nas 4 telas.

Submissão vazia: campo "Nome" tem `required` e `maxlength=100` no HTML, então o
navegador barra o envio antes de qualquer requisição chegar ao servidor — sem
requisição, sem consumo de recurso. A mensagem é o balão nativo do navegador em
inglês ("Please fill out this field."), não em português. Ver CB-04.

### [CB-02] "Editar" em Cadastros nunca exibe o formulário — bug de CSS, não de lógica
- **Severidade:** Bloqueio
- **Onde:** Cadastros > Titulares / Instituições / Contas — `/tables/owners/`, `/tables/banks/`, `/tables/accounts/` (e provavelmente Categorias, mesmo componente)
- **Passos:** 1. Em qualquer cadastro, clicar no ícone "Editar" de uma linha. 2. Observar que nada muda na tela.
- **Esperado:** A linha de edição (nome, campos do registro) aparece para alteração.
- **Obtido:** O clique dispara corretamente o JS (`data-toggle-edit`, alterna a classe `is-collapsed` no `<tr id="edit-*">` correspondente), mas a linha nunca fica visível. Inspecionei todas as folhas de estilo carregadas: a única regra que casa com `.edit-row` é `.edit-row { display: none; background: rgba(0,0,0,0.02); }` — incondicional. Não existe em nenhum CSS carregado uma regra para `.is-collapsed`, para o estado "aberto", nem para `[data-toggle-edit]`. Ou seja, a marcação/JS de alternância existe, mas o CSS que deveria mostrar a linha nunca foi escrito (ou foi removido). Reproduzido em 3 das 4 telas de cadastro (Titulares `edit-owner-N`, Instituições `edit-institution-N`, Contas `edit-account-N`) — mesmo componente compartilhado, então Categorias quase certamente sofre do mesmo problema.
- Confirmei que o back-end funciona normalmente: preenchi o campo oculto via JS e chamei `form.requestSubmit()` diretamente nos meus 3 registros de teste (titular, conta) — a gravação foi aceita e o valor mudou na listagem (`ZZTESTE Titular` → `ZZTESTE Titular Editado`; saldo da `ZZTESTE Conta` de 1234,56 → 999,99). Ou seja: **nenhum usuário real consegue editar Titulares, Instituições ou Contas pela tela hoje** — o botão existe, parece funcionar (ícone reage), mas não abre nada, e não há nenhuma mensagem de erro indicando o problema.
- **Evidência:** regra CSS `.edit-row { display: none; background: rgba(0, 0, 0, 0.02); }` (única ocorrência de `edit-row` em todas as folhas de estilo carregadas); nenhuma ocorrência de `is-collapsed` em nenhum `<style>`/stylesheet carregado. Sem erro de console (o JS não falha, só não tem CSS para se apoiar).
- **Vale para os outros sistemas?** não — é específico deste componente/CSS do ControleBancario, mas vale muito para as outras 3 telas de Cadastros do próprio sistema (Categorias não testada diretamente, mesmo componente).
- **Atualização (Bloco 3):** o mesmo bug reproduz em **Movimentação > Lançamentos** (`/transactions/`). Clicar "Editar" numa linha de lançamento alterna a classe do `<tr id="tx-edit-N">` de `edit-row` para `edit-row is-collapsed`, mas em ambos os estados o computed `display` é `none` — não existe regra CSS para nenhum dos dois. Ou seja, **também não é possível editar valor/data/descrição de um lançamento pela tela**, ampliando o alcance do bloqueio para a tela mais usada do sistema (o núcleo de lançamentos). Reproduzido em `tx-edit-1355` e `tx-edit-1356`.

### [CB-03] Nome duplicado aceito sem aviso em Titulares e Instituições
- **Severidade:** Defeito
- **Onde:** Cadastros > Titulares — `/tables/owners/`; Cadastros > Instituições — `/tables/banks/`
- **Passos:** 1. Criar `ZZTESTE Titular`. 2. Repetir exatamente o mesmo nome e confirmar no modal "Confirmar cadastro". 3. Repetir o mesmo teste em Instituições com `ZZTESTE Banco`.
- **Esperado:** Bloqueio ou aviso de nome já cadastrado (aqui nome é o único identificador visível ao usuário nas duas telas).
- **Obtido:** Duas linhas idênticas "ZZTESTE Titular" e, separadamente, duas linhas idênticas "ZZTESTE Banco" foram aceitas sem qualquer aviso, nem no modal de confirmação nem depois de gravar. Os duplicados foram excluídos logo em seguida (limpeza feita na hora, sem deixar resíduo).
- **Evidência:** listagem mostrando duas linhas "ZZTESTE Titular" / duas linhas "Banco · ZZTESTE Banco" antes da exclusão do duplicado.
- **Vale para os outros sistemas?** não testado nos outros três, mas é um padrão de validação (ausência de unicidade em cadastro simples) que vale a pena conferir nos outros sistemas também.

### [CB-04] Mensagem de campo obrigatório em inglês
- **Severidade:** Inconsistência
- **Onde:** Todos os campos de texto obrigatórios testados em Cadastros (ex.: Nome do titular) — validação é só HTML5 nativo (`required`)
- **Passos:** 1. Deixar "Nome do titular" vazio. 2. Clicar Incluir.
- **Esperado:** Sistema é todo em pt-BR; mensagem de validação também deveria ser.
- **Obtido:** Balão nativo do navegador: "Please fill out this field." — em inglês, porque a validação depende só do atributo `required` do HTML, sem `title`/mensagem customizada nem verificação JS própria com texto em português.
- **Evidência:** `validationMessage` do campo = "Please fill out this field."
- **Vale para os outros sistemas?** sim, talvez — vale conferir se ConfortoTermico, MegaSena e ControleRendaVariavel também dependem só da validação nativa do navegador (mesma pegada, mensagem no idioma do navegador do usuário, não do sistema).
- **Atualização (Bloco 3):** o mesmo padrão aparece em `/transactions/` no campo Vencimento, que tem `min` amarrado à "Data inicial do sistema" (Configurações > Parâmetros = 2026-01-01). Ao tentar salvar um lançamento com vencimento 01/01/1990, o navegador bloqueou com o balão nativo "Value must be 01/01/2026 or later." — de novo em inglês. Como contraponto, as regras de negócio validadas no servidor (não HTML5) usam **português** corretamente: tentar salvar Valor Total = 0 ou negativo (-10) devolveu o toast "O valor do lançamento deve ser positivo." nos dois casos, em pt-BR. Ou seja, a inconsistência de idioma é especificamente das mensagens nativas do HTML5 (`required`, `min`/`max` de data), não da validação de regra de negócio do próprio sistema.

Registros de teste mantidos propositalmente vivos para o Bloco 3 (dependências):
`ZZTESTE Titular` (id 6), `ZZTESTE Banco` (id 9), `ZZTESTE Conta` (id 12,
saldo 999,99), `ZZTESTE Categoria` (Normal). Serão excluídos ao fim do Bloco 3
(Conta só depois do teste de exclusão bloqueada por lançamento vinculado,
conforme roteiro).

---

## Retomada (3ª tentativa) — Prioridade zero: resíduo distorcendo o dashboard real

Antes de qualquer teste novo desta rodada, o `/dashboard/` apresentava
"Cobertura Média 429,65x" em vez do valor real (~1,13x). Investigação:

1. `/reports/annual-planning/` (titular = Todos, ano 2026) mostrou a anomalia:
   coluna Sep/26 com "Total Receitas +R$ 100.018.378,09" contra ~R$18-64 mil
   nos demais meses — um desvio de exatamente ~R$ 100.000.000,00.
2. Localizado em `/transactions/?mode=todos&period=2026-09`: lançamento
   **id 1354**, Receita, categoria `ZZTESTE Categoria`, descrição "ZZTESTE
   Valor Grande", vencimento 19/09/2026, valor **+R$ 99.999.999,99** — resíduo
   do teste de "valor muito grande" do roteiro do Bloco 3, não limpo antes da
   interrupção da sessão anterior.
3. Excluído pela tela (botão Excluir da linha, modal de confirmação). Dashboard
   conferido em seguida: Cobertura Média voltou a **1,13x**. Planejamento
   anual confirmado limpo (Sep/26 realinhado aos demais meses).
4. Usei a Trilha de Auditoria (`/settings/audit-log/?entity_name=cash_flow_entry&action=create&created_on=2026-08-31`)
   para conferir se sobrava mais algum resíduo: a sessão anterior criou
   exatamente **16 lançamentos** (`cash_flow_entry` ids 1339-1354, todos entre
   02:37:59 e 02:58:39 do dia 31/08/2026) e havia registro de **delete** para
   apenas 15 deles. O id que faltava, **1353** ("ZZTESTE Data Futuro", Despesa,
   -R$25,00, conta `ZZTESTE Conta`, vencimento 31/12/2099 — exatamente o
   lançamento de "data futura distante" citado no `STATUS_CB.md`), foi
   localizado em `/transactions/?mode=todos&account_id=12&period=2099-12` e
   excluído do mesmo jeito. Conferido de novo na trilha: os 16 ids criados têm
   agora os 16 deletes correspondentes — nenhum `cash_flow_entry` de teste
   restante.
5. **Achado sobre o próprio mecanismo de distorção:** a hipótese inicial (um
   lançamento de data distante como 2099-12 entrando no cálculo de "6 meses
   antes e depois" do dashboard) **não se confirmou** — o lançamento de
   2099-12 (id 1353, R$25,00) é pequeno demais e distante demais para poder
   mover a agulha, e de fato não aparecia no card de Cobertura Média. O culpado
   real foi um lançamento de **valor absurdamente grande dentro da janela
   normal (mês seguinte ao atual)**: como o dashboard, o planejamento anual e o
   saldo corrente somam tudo sem qualquer limite/alçada ou destaque de outlier,
   um único valor de R$ 99.999.999,99 dominou por completo os agregados de um
   sistema com 714 lançamentos reais na casa das dezenas de milhares. Acumula
   como observação de robustez para o Bloco 5 (Relatórios) e Bloco 3 (teste de
   valor "muito grande"): não há teto de valor nem alerta de outlier em nenhum
   agregado observado.

### [CB-05] Trilha de auditoria não registra o usuário em `create`/`delete` de lançamentos (`cash_flow_entry`)
- **Severidade:** Defeito
- **Onde:** Segurança > Trilha de auditoria — `/settings/audit-log/`; eventos de entidade `cash_flow_entry`
- **Passos:** 1. Criar ou excluir um lançamento (qualquer). 2. Abrir a Trilha de Auditoria e filtrar por `entity_name=cash_flow_entry`.
- **Esperado:** Coluna "Usuário" preenchida com quem fez a ação (como ocorre em outras entidades).
- **Obtido:** Coluna "Usuário" aparece como `-` em **todos** os 32 eventos `create`/`delete` de `cash_flow_entry` conferidos (os 16 criados e os 16 excluídos nesta limpeza, incluindo os 2 excluídos por mim agora mesmo, sessão autenticada como `mspa`). Confirmado que o mecanismo de auditoria funciona corretamente para outras entidades no mesmo período: filtrando por `user_name=mspa` aparecem, por exemplo, vários `account_month_close` (`close`/`reopen`) corretamente atribuídos a `mspa` com data/hora. Ou seja, o campo usuário é gravado para fechamento mensal mas não para lançamentos — falha específica do rastro de `cash_flow_entry`.
- **Evidência:** linhas da trilha, ex.: `31/08/2026 07:17:40 - cash_flow_entry 1354 delete` (usuário = `-`) vs. `16/08/2026 00:19:26 mspa account_month_close 40 reopen` (usuário = `mspa`).
- **Vale para os outros sistemas?** não testado — é específico da implementação de auditoria deste sistema, mas o padrão ("alguma entidade não registra o autor") vale a pena conferir nos outros três.
- **Nota:** revisitar no Bloco 6 para conferir também a coluna IP nesses mesmos eventos (cliente vs. gateway Docker) e se o padrão se repete em outras entidades (`entry_attachment`, `bank_operation`).

## Bloco 3 — Lançamentos (o núcleo)

Total de lançamentos no início do bloco (após a limpeza de prioridade zero):
714 reais + 0 ZZTESTE (confirmado por auditoria, ver acima). Conta de teste:
`ZZTESTE Conta` (id 12, saldo inicial 999,99), `ZZTESTE Conta 2` (id 13, saldo
inicial 500,00), ambas já existentes de uma tentativa anterior.

**Lançamento simples:** criados receita "ZZTESTE Receita Simples" (+R$300,00,
31/08/2026) e despesa "ZZTESTE Despesa Simples" (-R$150,00, 31/08/2026), ambos
em `ZZTESTE Conta`/`ZZTESTE Categoria`. Saldo final conferido (999,99+300-150=
1.149,99, bate). **Editar valor e data:** confirmado que o mesmo bug do CB-02
(CSS `.edit-row{display:none}` sem contrapartida para o estado aberto) também
atinge a edição de **lançamentos**, não só os 4 cadastros — o clique em
"Editar" alterna a classe (`edit-row` → `edit-row is-collapsed`) mas a linha
nunca aparece (`display: none` nos dois estados). Ampliei o CB-02 para
registrar isso (ver adiante). **Marcar como realizado:** funcionou (dois
modais de confirmação em cascata — "Marcar como Realizado" com data/valor
pré-preenchidos, depois "Confirmar realização" — toast de sucesso). **Desmarcar:**
não existe nenhum controle na tela para desfazer a realização (o botão
"Realizar" simplesmente desaparece da linha depois de realizado; não surge
"desfazer" nem outro ícone em seu lugar) — não há como testar "desmarcar" por
não existir a função. **Excluir:** funcionou (modal de confirmação, toast de
sucesso), removi a despesa de teste ao final desse sub-bloco.

**Nota sobre a Trilha de Auditoria:** a ação `realize` (marcar como realizado)
**não gerou nenhum evento** na trilha para o lançamento 1356 — só aparece o
`create` original. Isso soma-se ao CB-05 (usuário não registrado): aqui é pior,
a ação inteira não é auditada, embora "realize" conste como opção válida no
filtro "Ação" da própria tela de auditoria.

### [CB-06] Parcelamento "Dividir valor" perde R$ 0,01 — soma das parcelas não fecha com o valor total
- **Severidade:** Defeito
- **Onde:** Movimentação > Lançamentos — criação com Parcelas > 1 e Modo de cálculo = "Dividir valor" (`calc_mode=divide`)
- **Passos:** 1. Novo lançamento: Despesa, `ZZTESTE Conta`, `ZZTESTE Categoria`, descrição "ZZTESTE Parcelado", Valor Total R$ 100,00, Parcelas = 3, Modo de cálculo = "Dividir valor", vencimento 31/08/2026. 2. Salvar. 3. Conferir as 3 parcelas geradas (uma por mês).
- **Esperado:** As 3 parcelas devem somar exatamente R$ 100,00 — prática usual é a última parcela absorver o resto da divisão (ex.: R$ 33,33 + R$ 33,33 + R$ 34,34, ou 33,34+33,33+33,33).
- **Obtido:** As 3 parcelas vieram **R$ 33,33 cada** (1/3 em 31/08/2026, 2/3 em 30/09/2026 — a data ajustou corretamente o dia por não existir 31/09 —, 3/3 em 31/10/2026), somando **R$ 99,99**. Falta R$ 0,01 sem qualquer ajuste na última parcela nem aviso ao usuário. As datas de vencimento avançando mês a mês com ajuste de fim de mês funcionaram corretamente — o defeito é só no valor.
- **Evidência:** telas de agosto/setembro/outubro/2026 filtradas por `account_id=12`, cada uma mostrando uma parcela de R$ 33,33; 33,33×3 = 99,99 ≠ 100,00.
- **Vale para os outros sistemas?** não diretamente (é o único com parcelamento financeiro assim), mas o padrão "divisão sem ajuste do resto na última parcela" é o tipo de bug a conferir em qualquer rateio dos outros três sistemas.

### [CB-07] Escopo ausente ou inválido assume silenciosamente "apagar o grupo inteiro"
- **Severidade:** Defeito (padrão de falha inseguro em exclusão de dado financeiro)
- **Onde:** Movimentação > Lançamentos — modal de exclusão de um lançamento parcelado; campo "Escopo" com opções "Somente este registro" / "Todos os registros do grupo" / "Este registro e os próximos"
- **Passos:** 1. Com o parcelamento de 3x do CB-06 já criado (ids 1357/1358/1359 — 1/3 em ago, 2/3 em set, 3/3 em out), abrir a parcela 2/3 (30/09/2026) e clicar em Excluir. 2. No modal "Confirmar exclusão", o campo "Escopo" já vem com **"Somente este registro" pré-selecionado** (comportamento padrão, não alterei nada). 3. Clicar "Confirmar exclusão".
- **Esperado:** apenas a parcela 2/3 (id do meio) é excluída; as parcelas 1/3 (agosto) e 3/3 (outubro) continuam existindo.
- **Obtido no teste automatizado:** as 3 parcelas foram excluídas simultaneamente. A Trilha de Auditoria registrou os ids 1357, 1358 e 1359 no mesmo segundo. Esse sintoma não prova falha no clique humano: o agente provavelmente alterou `select.value` sem disparar o evento `change`, deixando o campo submetido com o valor anterior.
- **Evidência:** Trilha de auditoria (`/settings/audit-log/?entity_name=cash_flow_entry&action=delete&created_on=2026-08-31`): linhas `31/08/2026 07:35:55 - cash_flow_entry 1359 delete`, `...1358 delete`, `...1357 delete`, todas no mesmo timestamp; `/transactions/?account_id=12&period=2026-08` e `período=2026-10` confirmados vazios logo após.
- **Vale para os outros sistemas?** não — específico do modelo de parcelamento do ControleBancario. Mas é um achado de alta severidade: um usuário real querendo apagar só uma parcela (ex.: para corrigir um lançamento duplicado) apagaria sem aviso o plano inteiro, incluindo parcelas já pagas/realizadas em meses passados, sem nenhuma forma de desfazer.
- **Correção da causa-raiz:** o `<select id="deleteScopeSelect">` visível não tem `name` de propósito. Um `<input type="hidden" name="operation_scope">` carrega o valor ao servidor, espelhado por um listener de `change` religado em `DOMContentLoaded`, `htmx:afterSwap` e `htmx:load` (`static/js/transactions.js:69-125` e `:225-262`; `templates/transactions/index.html:145-155`). Para clique humano, esse caminho funciona. O defeito confirmado está em `transactions/views.py:67`: `_normalize_operation_scope` devolve `OPERATION_SCOPE_ALL` quando o escopo chega ausente, inválido ou corrompido. Assim, qualquer falha do JS ou cliente sem o script transforma silenciosamente uma exclusão pontual em exclusão do grupo inteiro. O padrão seguro é recusar a requisição ou cair em `single`. A simplificação recomendada é dar `name="operation_scope"` ao próprio select visível, eliminar o hidden/espelhamento e inverter o fallback para o lado seguro.

**Lançamento recorrente:** criado "ZZTESTE Recorrente" (Despesa, R$50,00,
31/08/2026, checkbox "Recorrente mensal"). Ao salvar, o sistema materializou
imediatamente **7 lançamentos reais** no banco (ids 1360-1366, mesmo segundo na
Trilha de Auditoria) — não é projeção virtual, são registros `cash_flow_entry`
de verdade, um por mês, do mês corrente até 6 meses à frente (31/08/2026 até
28/02/2027 — a data do dia 31 foi corretamente ajustada para o último dia dos
meses mais curtos: 30/09, 30/11, 28/02). O horizonte de 6 meses bate com o
parâmetro "Horizonte de projeção (meses)" = 6 visto em Configurações >
Parâmetros. **Rodar a projeção manual** (`/settings/recurring-projection/run/`,
botão "Executar Projeção Agora" em `/settings/`): **não executei** — a tela não
oferece nenhum jeito de restringir a execução a um registro específico, é um
botão único e global (campos ocultos `horizon_months=6`, `run_day=28`, sem
parâmetro de escopo), que reprojetaria recorrências de todas as contas reais.
Registrado como não executado por ser destrutivo/global, conforme a regra do
roteiro. De passagem, aproveitei a tela para anotar os valores originais de
Configurações > Parâmetros (úteis para o Bloco 6): senha mínima 15
caracteres, 0 maiúsculas/números/especiais exigidos; bloqueio de login 5
tentativas / 1 minuto; horizonte de recorrência 6 meses, dia de execução 28;
data inicial do sistema 2026-01-01; última execução da projeção 06/08/2026
21:22:25.

**Transferência interna:** criada usando `ZZTESTE Conta` (12, origem) →
`ZZTESTE Conta 2` (13, destino), categoria "Transferência Entre Contas",
R$200,00. Confirmado o par débito/crédito: conta 12 registrou "Despesa,
Transferência Entre Contas, Conta Destino: ... Conta 2, -R$200,00"; conta 13
registrou automaticamente "Receita, Transferência Entre Contas, Conta Origem:
... Conta, +R$200,00". Saldos batem (12: 999,99+300-50-200=1.049,99; 13:
500+200=700,00). **Observação:** a descrição digitada por mim
("ZZTESTE Transferencia") foi **descartada e substituída** pela descrição
automática "Conta Destino: ..."/"Conta Origem: ..." — o campo Descrição não
tem efeito nas transferências internas (não é um defeito grave, mas vale
registrar: o campo aceita texto e o modal de confirmação nem avisa que ele
será ignorado). **Exclusão de uma perna:** exclui a perna "Despesa" da conta
12 (id 1367, sem opção de escopo no modal — `data-delete-supports-scope=false`)
e confirmei que a perna "Receita" da conta 13 **foi excluída junto,
automaticamente**, sem exigir uma segunda ação — comportamento correto e
consistente (contraste direto com o CB-07: aqui a cascata é feita certo).

**Lançamentos n+1** (`/operations/`): tela de **consulta/agrupamento**, não de
edição. Agrupa por operação (recorrência, parcelamento ou transferência
interna) usando um `operation_id`/UUID, mostrando início, fim, quantidade de
ocorrências e valor total da série — ex.: minha recorrência apareceu como
"ZZTESTE Recorrente ... 31/08/2026 → 28/02/2027, Qtde. 7, R$ 350,00, Status
A_vencer". Duas ações por linha: "Ver operação" (reaplica o filtro
`operation_id` na própria tela) e "Ver lançamentos" (abre `/transactions/` com
`?operation_id=...`, listando as 7 ocorrências individuais de qualquer conta,
sem exigir filtro de conta). Contrato: é um índice/relatório de navegação
sobre as mesmas linhas de `cash_flow_entry`; toda ação real (editar, excluir,
realizar) continua acontecendo em `/transactions/`.

### [CB-08] Coluna "Saldo" e cartões de resumo não fecham ao filtrar lançamentos por `operation_id`
- **Severidade:** Inconsistência
- **Onde:** Movimentação > Lançamentos n+1 > "Ver lançamentos" — `/transactions/?operation_id=<uuid>`
- **Passos:** 1. Em `/operations/`, clicar "Ver lançamentos" na linha da recorrência "ZZTESTE Recorrente" (7 ocorrências de -R$50,00, 31/08/2026 a 28/02/2027). 2. Observar a coluna "Saldo" de cada uma das 7 linhas e os cartões Saldo Inicial/Despesas/Saldo Final no topo.
- **Esperado:** A coluna "Saldo" deveria mostrar o saldo corrente da conta após cada ocorrência (decrescendo R$50,00 a cada linha, já que são 7 meses consecutivos); Saldo Inicial + Despesas deveria fechar com Saldo Final da mesma tela.
- **Obtido:** A coluna "Saldo" mostra **o mesmo valor fixo em todas as 7 linhas** (+ R$ 8.733,17), em vez de decrescer mês a mês. Os cartões mostraram Saldo Inicial + R$ 9.053,17, Despesas - R$ 350,00 (esse valor bate: 7 × R$50,00), mas Saldo Final + R$ 8.733,17 — e 9.053,17 − 350,00 = 8.703,17, **não** 8.733,17 (diferença de R$ 30,00). Nenhum desses três números (9.053,17 / 8.733,17) corresponde ao saldo real da `ZZTESTE Conta` nessa janela (que deveria orbitar perto de R$ 649,99 = 999,99 − 7×50,00, já que nenhum outro lançamento da conta de teste está nesse intervalo). Isso sugere que os cartões de resumo, quando a tela é acessada via `operation_id` (sem filtro explícito de conta na URL), calculam a partir de algum contexto de conta diferente do da operação filtrada — possivelmente o filtro de conta persistido na sessão de outra navegação — em vez de recalcular para as linhas efetivamente exibidas.
- **Evidência:** texto da tela: `Saldo Inicial + R$ 9.053,17`, `Despesas - R$ 350,00`, `Saldo Final + R$ 8.733,17`; as 7 linhas de 31/08/2026 a 28/02/2027 todas com a mesma célula "Saldo" = `+ R$ 8.733,17`.
- **Vale para os outros sistemas?** não — específico deste relatório cruzado (`operation_id`) do ControleBancario.

**Filtros da listagem:** `account_id`, `period`, `mode` e `owner_id` funcionam
como parâmetro de URL (testado `owner_id=6` filtrando as duas contas do
`ZZTESTE Titular` simultaneamente: Saldo Inicial R$1.499,99 = 999,99+500,00,
bate). **`entry_type` e `category_id` como parâmetro de URL direto não
filtram** a listagem (a página recarrega normalmente mas mostra todos os tipos
e categorias) — só funcionam através do próprio dropdown na tela (que dispara
HTMX com algum outro mecanismo). Registrado como inconsistência menor: dois
filtros da mesma tela, dois comportamentos diferentes para o mesmo padrão de
URL. Onde os filtros efetivamente aplicaram, os cartões de resumo sempre
fecharam com a soma da tabela filtrada (conferido à mão em vários pontos deste
bloco).

**Datas:** 29/02 em 2026 (não bissexto) — o `<input type="date">` simplesmente
não aceita a data (fica vazio, `checkValidity()` acusa "Please fill out this
field."), então nem chega a ser uma decisão do sistema, é bloqueio nativo do
navegador. Data no passado distante (01/01/1990) — bloqueada por um `min`
amarrado à "Data inicial do sistema" (2026-01-01, ver Configurações >
Parâmetros), balão nativo em inglês (ver atualização do CB-04 acima). Data no
futuro distante (31/12/2099) — aceita sem restrição (foi o próprio caso do
lançamento residual da limpeza de prioridade zero). Campo vazio — bloqueado
pelo `required` nativo.

**Valores:** zero e negativo — aceitos pelo campo HTML5 (não tem `min`), mas
**rejeitados no servidor** com toast em português "O valor do lançamento deve
ser positivo." nos dois casos (validação de negócio correta, camada dupla:
fraca no HTML, sólida no servidor). Muito grande — já teve sua própria seção
acima (o incidente da Prioridade Zero, R$99.999.999,99 aceito sem teto nem
alerta). Centavos — presentes em quase todos os testes deste bloco (33,33,
250,00 etc.), sem problema de arredondamento exceto o já registrado no CB-06.
Vírgula como separador decimal — não testável isoladamente: o campo é
`<input type="number">`, o navegador já impede digitar vírgula.

**Limpeza do bloco:** excluí `ZZTESTE Receita Simples` (id 1356, já realizada)
individualmente, e ao tentar excluir só a ocorrência de agosto de `ZZTESTE
Recorrente` acabei confirmando de novo o CB-07 (ver acima): a exclusão de uma
única ocorrência apagou as 7 de uma vez (ids 1360-1366), o que também serviu
de limpeza da recorrência inteira. Total de lançamentos criados nesta rodada
de testes (Bloco 3): 30 `cash_flow_entry` (ids 1339-1368 — simples, editados,
3 parcelas, 7 ocorrências de recorrência, par de transferência, e os
descartados por validação de valor/data que nunca chegaram a gravar). Trilha
de Auditoria conferida ao final: **30 `create` e 30 `delete`** para
`cash_flow_entry` no dia, todos com os mesmos ids — nenhum residual. Os 714
lançamentos reais permanecem intocados (nenhum dos ids das ações deste bloco
cai fora da faixa 1339-1368). `ZZTESTE Conta` e `ZZTESTE Conta 2` voltaram ao
saldo estático (999,99 e 500,00) sem nenhum lançamento pendente. Dashboard
reconferido ao final do bloco: Cobertura Média segue em 1,13x.

## Bloco 4 — Banking

**Limitação de ferramenta (afeta 3 dos 4 itens deste bloco):** as ferramentas
de navegador disponíveis nesta sessão (`Claude_Browser`) não têm nenhuma ação
de upload de arquivo — `form_input` num `<input type="file">` falha com
`InvalidStateError` (navegador bloqueia setar `.value` por segurança) e não há
ação equivalente a "escolher arquivo" para abrir o seletor nativo do SO. Isso
bloqueia qualquer teste que dependa de enviar um arquivo real:

- **Importação de extrato** (`/banking/imports/`): **não executado**. Descrevo
  o contrato observado na tela: aceita CSV (cabeçalhos `data`/`date`,
  `descrição`/`descricao`/`historico`/`description`, `valor`/`amount`),
  OFX/OFC/QFX (padrão bancário) e PDF (só corretoras homologadas). "Valores
  negativos são despesas; positivos são receitas" — dito explicitamente na
  tela. Preparei um CSV sintético (`zzteste_extrato.csv`, 2 linhas, valores
  -45,90 e 120,00, ambas com descrição `ZZTESTE...`) no scratchpad, mas não
  há como anexá-lo pela automação disponível. Não testado: status do lote,
  arquivo malformado, formato não suportado, arquivo vazio, reimportação do
  mesmo arquivo (duplica ou detecta).
- **Conciliação** (`/banking/reconciliation/`): tela consultada mas **não
  exercida** — "Linhas de extrato pendentes de conciliação: Nenhuma linha
  pendente" (não há nada para conciliar sem uma importação nova, que depende
  do item acima). A seção "Últimas conciliações" mostra histórico real (com
  botão "Desfazer" por linha) que **não toquei**, por ser dado real. Não
  testado: conciliar, criar lançamento a partir de linha, conciliação em lote
  e desfazer, ignorar linha.
- **Comprovantes** (`/banking/attachments/`): tela consultada — "Comprovantes
  recentes: Nenhum comprovante anexado" (zero anexos em todo o sistema, real
  ou de teste). **Não testado**: anexar, baixar, conferir nome/tipo, arquivo
  grande demais, tipo não permitido. Tentei localizar a rota de download por
  tentativa direta de URL (`/banking/attachments/1/download/`) para ao menos
  checar o padrão de autorização — voltou 404 (rota incorreta, não há como
  descobrir a rota certa sem um anexo real para inspecionar o link gerado).
  **Não foi possível conferir se o download de comprovante de outro usuário é
  barrado**, item explicitamente pedido no roteiro — registrado como não
  executado pela mesma limitação de ferramenta.

**Fechamento mensal** (`/settings/monthly-close/`) — **executado com
sucesso**, este item não depende de upload:
- Todas as contas reais já têm meses fechados/reabertos no histórico
  (mai-dez/2026); `ZZTESTE Conta` estava com zero lançamentos, então
  qualquer mês nela é seguro — usei 08/2026 (mês corrente).
- **Fechar:** selecionei `ZZTESTE Conta`, mês 8, ano 2026, confirmei no modal
  "Confirmar fechamento mensal". Resultado: linha nova em "Fechamentos
  recentes" com Status "Fechado", Saldo Fechado R$999,99 (bate com o saldo
  real da conta, que não tinha lançamento nenhum nesse mês).
- **Efeito no mês fechado:** tentei criar um lançamento de teste com
  vencimento 15/08/2026 na `ZZTESTE Conta` — **bloqueado corretamente**, toast
  em português: "Há um mês fechado no período para a conta ZZTESTE Conta.".
  Nenhum lançamento foi criado (confirmado pela listagem continuando vazia).
- **Reabrir:** botão "Reabrir" exige campo "Motivo" (obrigatório,
  `maxlength=255`) antes de habilitar o submit; preenchi "ZZTESTE teste de
  fechamento mensal (Bloco 4)" e confirmei no modal "Confirmar reabertura
  mensal". Resultado: Status voltou para "Reaberto", motivo gravado e exibido
  na lista.
- **Repeti a criação do lançamento de teste** (mesmos dados) após a
  reabertura — **aceito normalmente** desta vez, confirmando o ciclo completo
  fechar→bloquear→reabrir→liberar funciona ponta a ponta. Lançamento de teste
  excluído em seguida (limpeza).
- **Conclusão:** fechamento mensal está bem implementado — validação correta,
  mensagem em português, exige motivo auditável para reabrir, e o registro de
  fechamento por si só (`account_month_close`) é uma das poucas entidades cuja
  trilha de auditoria registra o usuário corretamente (ver CB-05).

Total de lançamentos reais: verificado por auditoria (não por contagem bruta,
que a tela `/settings/database/` limita a 50 linhas sem total exibido) que
nenhum evento `create`/`delete`/`update` de `cash_flow_entry` fora do range
1339-1354 ocorreu hoje — os 714 lançamentos reais do acervo não foram tocados
nesta limpeza. Baseline para o Bloco 3 a partir daqui: acervo real limpo, os 4
cadastros `ZZTESTE` (Titular id 6, Banco id 9, Categoria, Conta id 12 saldo
999,99) mantidos, e também **`ZZTESTE Conta 2` (id 13, saldo 500,00)** — já
criada por mim/sessão anterior, mantida de propósito para o teste de
transferência interna do Bloco 3.

## Retomada (4ª tentativa) — conclusão do Bloco 4

Sessão nova, mesma aba dedicada (`tabId` próprio), cookie de `mspa` ainda
válido — sem tela de login. Verificações de baseline antes de continuar:
dashboard com Cobertura Média **1,13x** (igual ao fechamento do Bloco 3, sem
resíduo), e `/settings/monthly-close/` confirmando que o fechamento mensal da
`ZZTESTE Conta` testado na tentativa anterior está exatamente como deixado —
`08/2026`, Status **Reaberto**, motivo "ZZTESTE teste de fechamento mensal
(Bloco 4)" — ou seja, aquele teste (fechar → bloquear edição → reabrir →
liberar edição → excluir lançamento de prova) já está concluído e limpo; não
foi repetido.

**Conciliação** (`/banking/reconciliation/`): reconferido — "Nenhuma linha
pendente de conciliação" continua vazio (inalterado desde a tentativa
anterior), porque não há como popular linhas de extrato sem importação, que
depende de upload de arquivo — indisponível nas ferramentas desta sessão (ver
abaixo). "Últimas conciliações" mostra só histórico real (com botão
"Desfazer" por linha), não tocado. **Conciliar, criar lançamento a partir de
linha, conciliação em lote, desfazer e ignorar seguem não executados**, mesma
causa raiz (sem linha de extrato de teste para operar).

**Comprovantes** — encontrada a rota real de download, que a tentativa
anterior não tinha localizado:

### [CB-09] Rota de download de comprovante localizada; teste de autorização cross-user permanece inconclusivo por falta de qualquer anexo no acervo
- **Severidade:** Observação
- **Onde:** Movimentação > Banking > Comprovantes — `GET /banking/attachment/<id>/download/`
- **Passos:** 1. Inspecionei o HTML de `/banking/attachments/` e achei o formulário de upload real: `action="/banking/attachment/"` (singular), `hx-post` igual, campo `entry_id` (número do movimento) + `attachment_file` (`accept=".pdf,.png,.jpg,.jpeg,.webp,.csv,.txt"`). 2. A tentativa anterior havia testado `/banking/attachments/1/download/` (plural) e recebido 404 de rota inexistente — registrado como "rota incorreta". 3. Testei por `fetch()` (mesma aba, mesma sessão) o padrão singular: `GET /banking/attachment/1/download/` e `.../999999/download/`.
- **Esperado:** acesso a um comprovante inexistente ou de outro usuário deve ser barrado de forma clara e, idealmente, sem diferenciar "não existe" de "existe mas não é seu" (evita enumeração de IDs).
- **Obtido:** rota real confirmada — `GET /banking/attachment/<id>/download/`. Para qualquer id testado (1, 999999), o servidor devolve redirect para `/banking/attachments/` (`fetch` com `redirect:'manual'` → `type: "opaqueredirect"`; com `redirect:'follow'` → `finalUrl` = `/banking/attachments/`, status final 200) com mensagem flash em português: `{"mensagem": "Anexo não encontrado.", "severidade": "warning"}`. Não devolve arquivo, não vaza se o id existe. Como o sistema inteiro (dados reais e de teste) tem **zero comprovantes anexados** em qualquer conta ("Comprovantes recentes: Nenhum comprovante anexado" — confirmado antes e depois desta rodada) e a ferramenta de automação desta sessão não expõe upload de arquivo local (sem ação "escolher arquivo"; `form_input` em `<input type="file">` falha com `InvalidStateError`), **não foi possível criar um anexo de teste** e repetir a chamada com um id que de fato exista e pertença a outro usuário. Ou seja: confirmo que a rota não vaza existência de id (sinal positivo), mas a barreira de autorização propriamente dita (dono vs. não-dono de um anexo real) **continua não exercida de fato** — acumula ao mesmo bloqueio de ferramenta já registrado para Importação.
- **Evidência:** `data-sa-avisos='[{"mensagem": "Anexo não encontrado.", "severidade": "warning"}]'` no HTML pós-redirect; upload form `action="/banking/attachment/" enctype="multipart/form-data" hx-post="/banking/attachment/"`.
- **Vale para os outros sistemas?** não testado, mas o padrão (mensagem genérica sem diferenciar "não existe" de "não autorizado") é boa prática a conferir em qualquer rota de download por id dos outros três sistemas.

**Importação de extrato:** sem mudança em relação à tentativa anterior —
continua **não executado** pela mesma limitação de ferramenta (sem ação de
upload). Contrato da tela já descrito permanece válido.

**Fechamento mensal:** já concluído na tentativa anterior (ver acima),
reconferido nesta retomada sem repetir a escrita — estado final confirmado
como **Reaberto**, sem lançamento de teste pendente.

**Conclusão do Bloco 4:** dos 4 itens do roteiro, 1 executado por completo com
sucesso (Fechamento mensal), 1 parcialmente esclarecido nesta retomada
(Comprovantes — rota e comportamento de "não encontrado" confirmados; teste de
autorização cross-user inconclusivo) e 2 bloqueados integralmente por
limitação de ferramenta (Importação de extrato, Conciliação — esta última
depende da primeira). Nenhum dado real tocado. Totais reconferidos:
dashboard 1,13x, nenhum `cash_flow_entry` fora da faixa já auditada nos blocos
anteriores.

## Bloco 5 — Relatórios

Bateria de leitura sobre os 714 lançamentos reais, com um ciclo de escrita
isolado em Controle gerencial (tags/projetos/orçamento).

**Próximos movimentos:** conferido à mão o fechamento aritmético do card TOTAL
e de cada conta: Saldo Inicial + Entradas + Saídas + Transf. int. = Saldo
Final em todas as linhas (ex.: Esther R$0,09 + R$6.273,35 − R$6.273,00 =
R$0,44, bate exatamente). "Menor saldo" corretamente calculado como mínimo
corrente da janela, não apenas início/fim. Nenhuma divergência encontrada —
ao contrário do CB-01 (Posição por conta), este relatório tem coluna própria
de transferência interna e fecha certinho por linha.

**Projeções:** running balance mês a mês confere exatamente com a soma
acumulada de Geração de Caixa em ambos os modos testados. Comportamento do
filtro "Ano calendário" vs "Janela móvel" e o tratamento de ano sem dado
(2020, calendário) testados em Planejamento anual — ver adiante — mas o
próprio relatório de Projeções revelou o achado mais forte do bloco:

### [CB-10] "Projeções": o Saldo do mês corrente (parcialmente decorrido) muda de valor conforme o filtro "Modo", e a diferença nunca é explicada por nenhuma coluna visível
- **Severidade:** Defeito
- **Onde:** Relatórios > Projeções — `/reports/projections/`
- **Passos:** 1. Abrir com `mode=a_vencer` (filtro padrão da tela) e anotar a linha de agosto/2026 (mês corrente, parcialmente decorrido). 2. Reabrir a mesma URL com `mode=todos`. 3. Comparar a coluna Saldo de agosto/2026 e a de setembro/2026 nos dois modos.
- **Esperado:** o saldo projetado de um mês é um fato do mundo real (quanto dinheiro haverá na conta), não deveria depender de qual filtro de status o usuário escolheu para exibir a tabela — mudar o "Modo" deveria só mudar quais linhas de detalhe aparecem, não o valor final da coluna Saldo.
- **Obtido:** com `mode=a_vencer`, agosto/2026 mostra Despesas −R$270,00, Geração de Caixa −R$270,00, A Vencer −R$270,00, **Saldo +R$5.552,01**. Com `mode=todos`, agosto/2026 mostra Receitas +R$56.887,60, Despesas −R$64.075,36, Geração de Caixa −R$7.187,76 (Realizado −R$5.347,49 + A Vencer −R$1.840,27), **Saldo +R$3.981,74** — mais de R$1.570,27 de diferença para o **mesmo mês real**. Pior: essa diferença não é consequência simples de "modo mostra menos coisa" — reconstruindo a cadeia mês a mês dentro do próprio modo `todos`, **a tabela não fecha com ela mesma**: Saldo de agosto (R$3.981,74) + Geração de Caixa de setembro (+R$4.450,55) deveria dar R$8.432,29, mas a própria tabela mostra Saldo de setembro = **R$10.002,56** (exatamente R$1.570,27 a mais — o mesmo desvio). Ou seja, o valor efetivamente usado como base para projetar setembro em diante é o saldo calculado pelo caminho `a_vencer` (R$5.552,01), mesmo quando a tela está exibindo o modo `todos` — a linha do mês corrente mostra um número, mas a progressão real usa outro, silenciosamente.
- **Evidência:** `/reports/projections/?mode=a_vencer&start_month=2026-02&end_month=2027-02&detail=complete` vs. `...&mode=todos&...` (mesmos parâmetros, só o modo muda); linhas de agosto e setembro/2026 coladas acima nesta seção.
- **Vale para os outros sistemas?** não testado, mas o padrão ("um total que aparece na tela não é o mesmo total usado internamente para o cálculo seguinte") é o tipo de bug a testar em qualquer relatório com projeção acumulada dos outros três sistemas.

**Posição por conta:** reconferido com os números atuais (acervo cresceu desde
o Bloco 1) — o padrão do CB-01 persiste de forma idêntica: total geral fecha
(R$12.056,17 − R$3.803,00 = R$8.253,17), mas linhas individuais com
transferência interna no período não fecham (mesma causa-raiz já registrada,
sem necessidade de novo achado).

**Planejamento anual:** documento `ControleBancario/docs/annual-planning-report.md`
lido antes de testar. Conferência rigorosa do "Contrato de cálculo" contra a
tela, mês de referência 08/2026, layout "Ano calendário":
- Colunas de mês (consolidado): `Geração de Caixa = Total Receitas + Total Despesas`
  confere em **todos os 12 meses** (ex.: Mar/26: R$38.387,79 − R$76.868,98 =
  −R$38.481,19, bate exato).
- Colunas de titular (mês de referência): `Saldo Previsto/Final = Saldo Atual/Inicial + Geração de Caixa + Movimentações Internas`
  confere para Cláudia, Esther, Mariano e ZZTESTE Titular — inclusive o caso
  documentado no próprio contrato ("no mês de referência, Movimentações
  Internas inclui também transferências já realizadas"): Esther tinha
  Geração de Caixa em branco (zero a_vencer) mas Movimentações Internas
  −R$6.274,00 mesmo assim compôs o saldo (R$0,74 − R$6.274,00 = −R$6.273,26,
  bate).
- Encadeamento entre meses: `Saldo Atual/Inicial` do mês N = `Saldo Previsto/Final` do mês N−1, confirmado em toda a linha do ano.
- **Janela móvel (13 meses):** `?layout=rolling` gerou exatamente 6 meses antes (Fev a Jul/26) + mês de referência (Ago/26) + 6 meses depois (Set/26 a Fev/27) = 13 colunas, conforme o contrato.
- **Ano sem dado (2020):** `?layout=calendar&reference_month=2020-08` não quebrou — linhas de Geração/Receitas/Despesas/Movimentações em branco, Saldo Atual/Final constante em R$25.266,05 (saldo real corrente, sem lançamento em 2020 para alterá-lo) e mensagem amigável "Nenhum dado encontrado para os filtros selecionados." em vez de tabela vazia sem explicação.
- **Conclusão:** nenhuma divergência entre o contrato documentado e o comportamento observado — é o relatório mais bem coberto por documentação própria dos cinco testados neste bloco, e o único onde bati o contrato ponto a ponto sem achar nada. Registro como observação positiva.

**Controle gerencial** (`/management/`): ciclo criar tag/projeto → vincular a
lançamento de teste → conferir reflexo → apagar.

- Criado lançamento de teste "ZZTESTE Gerencial" (id 1369, Despesa R$25,00,
  `ZZTESTE Conta`/`ZZTESTE Categoria`, vencimento 31/08/2026). Criados
  "ZZTESTE Tag" e "ZZTESTE Projeto" (a criação do projeto falhou
  silenciosamente na primeira tentativa — sem toast de erro, sem o registro
  aparecer no dropdown — e funcionou normalmente na segunda, com os mesmos
  dados; não investiguei a fundo por ser custo x benefício baixo, mas registro
  que **uma tentativa de salvar projeto pode não produzir feedback nenhum de
  falha nem de sucesso**, obrigando o usuário a conferir o dropdown para saber
  se funcionou).
- Vinculei tag e projeto ao id 1369 (pela tela, com modal de confirmação
  "Confirmar vínculo" em ambos). Ao conferir o resultado em
  `/management/?account_id=12` ("Movimentos classificados recentemente"), a
  lista voltava **vazia** — e ao investigar, descobri pela Trilha de Auditoria
  que o **lançamento 1369 tinha sido excluído** (`cash_flow_entry 1369 delete`
  às 08:00:40, cerca de 3 minutos depois da criação às 07:57:29), sem que eu
  tivesse clicado em nenhum "Excluir" — a tela de Painel gerencial nem tem
  botão de exclusão de lançamento. Ver CB-11 abaixo.
- Repeti o teste do zero com um segundo lançamento (id 1370, mesmos dados,
  desta vez criado por POST direto ao endpoint real `/transaction/` para
  eliminar qualquer dúvida sobre o clique) e repeti vincular tag e projeto
  também por POST direto aos endpoints reais (`/management/assign-tag/`,
  `/management/assign-project/`, descobertos inspecionando os formulários da
  própria tela). **Desta vez funcionou perfeitamente**: id 1370 permaneceu
  vivo, `/management/?account_id=12` passou a mostrar
  `#1370 ... ZZTESTE Gerencial 2 ... ZZTESTE Projeto ... ZZTESTE Tag` depois de
  cada vínculo, confirmando que o mecanismo de vínculo em si funciona e é
  refletido corretamente na tela quando o lançamento sobrevive. Não consegui
  reproduzir o sumiço do id 1369 numa segunda tentativa idêntica.
- **Orçamento mensal:** criei orçamento `ZZTESTE Titular` / `ZZTESTE
  Categoria` / 08/2026 / R$100,00 — refletido corretamente em "Orçado x
  realizado no mês" (Orçado R$100,00, Realizado em branco porque o lançamento
  de teste nunca foi marcado como Realizado, Diferença +R$100,00 — matemática
  correta para o estado real dos dados).
- **Limpeza:** id 1370 excluído pela rota real (`/transaction/delete/1370/`).
  Tag, Projeto e Orçamento **não têm nenhuma função de exclusão na tela nem
  endpoint correspondente** (inspecionei todos os `<form>` da página: só
  existem `tag/`, `project/`, `budget/`, `assign-tag/`, `assign-project/` —
  nenhum "delete"/"remove"). Zerei o orçamento (`planned_amount=0`, aceito),
  mas a linha em si continua listada com Orçado/Realizado/Diferença em branco
  — não desaparece. `ZZTESTE Tag` e `ZZTESTE Projeto` ficam definitivamente
  como resíduo, registrados na limpeza final do STATUS.

### [CB-11] Lançamento de teste (id 1369) excluído sem nenhuma ação explícita de exclusão, durante o fluxo de vincular tag/projeto no Painel gerencial — não reproduzido de forma confiável
- **Severidade:** Bloqueio (risco de perda de dado financeiro, mas achado não determinístico)
- **Onde:** Movimentação > Lançamentos (criação) + Relatórios > Controle gerencial (`/management/`) — vínculo de tag/projeto ao lançamento 1369
- **Passos:** 1. Criar lançamento de teste (id 1369) pela tela `/transactions/`. 2. Ir a `/management/`, criar tag e projeto de teste. 3. Preencher "ID do movimento" = 1369 e vincular a tag (modal "Confirmar vínculo" → confirmar). 4. Conferir o lançamento depois.
- **Esperado:** o lançamento 1369 continua existindo, agora com a tag associada.
- **Obtido:** o lançamento 1369 deixou de existir. A Trilha de Auditoria mostra `cash_flow_entry 1369 create` às 07:57:29 e `cash_flow_entry 1369 delete` às 08:00:40 — sem nenhum evento de exclusão iniciado por mim (a tela de Painel gerencial não tem nenhum botão "Excluir lançamento"; a única ação destrutiva disponível ali é sobre tag/projeto/orçamento, não sobre o `cash_flow_entry`). Entre a criação e a exclusão, as únicas ações realizadas foram: criar tag (sucesso), tentar criar projeto (falhou silenciosamente), preencher os dois formulários de vínculo com `entry_id=1369`, e clicar "Vincular" só no formulário da tag (com confirmação). **Não consegui reproduzir**: repeti a sequência do zero com um segundo lançamento (id 1370) e os mesmos vínculos de tag e projeto, desta vez sem qualquer anomalia — o id 1370 sobreviveu normalmente aos dois vínculos.
- **Evidência:** Trilha de auditoria filtrada por `entity_name=cash_flow_entry&created_on=2026-08-31`, linhas `cash_flow_entry 1369 create` (07:57:29) e `cash_flow_entry 1369 delete` (08:00:40); nenhuma outra ação de qualquer entidade registrada nesse intervalo de 3 minutos além das descritas.
- **Vale para os outros sistemas?** não aplicável (funcionalidade específica deste sistema), mas o padrão — uma tela de classificação/anexação acabar apagando o registro-alvo — é grave o suficiente para valer um teste dedicado nos outros três se eles tiverem telas equivalentes de "vincular metadado a um registro existente".
- **Nota:** não escalo para "reproduzido e confirmado" porque a segunda tentativa idêntica não reproduziu o problema; friso que o dado afetado era exclusivamente de teste (id 1369, `ZZTESTE Conta`) e os 714 lançamentos reais não foram tocados. Registro como achado sério porém não-determinístico — meritório de atenção do mantenedor, não de alarme imediato.

### [CB-12] "Movimentos classificados recentemente" (Painel gerencial) exibe despesa com sinal de "+"
- **Severidade:** Inconsistência
- **Onde:** Relatórios > Controle gerencial — `/management/`, tabela "Movimentos classificados recentemente", coluna "Valor"
- **Passos:** 1. Vincular tag/projeto a um lançamento do tipo Despesa (id 1370, −R$30,00). 2. Comparar a coluna "Valor" nesta tabela com a mesma linha em `/transactions/`.
- **Esperado:** despesa exibida com sinal negativo, como em toda outra tela do sistema (`/transactions/`, `/reports/upcoming-movements/`, `/reports/projections/` etc., todas usam "− R$" para despesa).
- **Obtido:** a linha aparece como `+ R$ 30,00` nesta tabela especificamente, enquanto `/transactions/` mostra corretamente `- R$ 30,00` para o mesmo lançamento.
- **Evidência:** `#1370\t31/08/2026\tZZTESTE Titular / ZZTESTE Conta\tZZTESTE Gerencial 2\t+ R$ 30,00\tZZTESTE Projeto\tZZTESTE Tag` (Painel gerencial) vs. `31/08/2026\tDespesa\tZZTESTE Categoria\tZZTESTE Gerencial 2\t-\t- R$ 30,00\t+ R$ 969,99` (`/transactions/`).
- **Vale para os outros sistemas?** não — específico da formatação desta tabela do ControleBancario.

**Melhoria (não numerada):** Tags, Projetos e Orçamentos criados em Controle
gerencial não têm nenhuma forma de exclusão pela tela (nem endpoint
`delete`/`remove` nos formulários inspecionados) — um usuário real que crie um
projeto ou tag por engano, ou que não precise mais dele, fica sem saída
exceto renomear/reutilizar. Orçamento pelo menos pode ser zerado
(`planned_amount=0`), mas a linha continua listada.

## Bloco 6 — Configurações e Segurança (interrompido por incidente de sessão — ver CB-15)

**Perfil e tema:** tema original `emerald`. Troquei para `dark` — aplicação
imediata (`data-theme` no `<html>`), confirmada persistente navegando para
outra tela. Restaurado para `emerald` ao final, confirmado. "Registros antes
do scroll" = 20, não alterado (não fazia parte do escopo do teste). Nenhuma
divergência.

**Contas em análises:** estado original conferido primeiro por precaução —
`get_page_text` não mostra estado de checkbox, então só a leitura do DOM via
JS revelou que **4 contas reais já vêm marcadas** como ocultas (Cláudia/C6,
Mariano/Genial, Mariano/SCP XP, Mariano/XP, ambas colunas Dashboard e
Projeções) — configuração deliberada pré-existente do mantenedor, não
tocada. Testei só na `ZZTESTE Conta`: marquei "Ocultar no Dashboard", salvei
(persistiu), desmarquei, salvei de novo — as 4 contas reais permaneceram
exatamente como estavam nos dois saves. Mecanismo funciona corretamente.

**Parâmetros:** valores originais reconferidos, idênticos aos anotados no
Bloco 3 (min_length 15, uppercase/numbers/special 0, max_failures 5,
lock_minutes 1, horizon_months 6, run_day 28, system_start_date 2026-01-01).

### [CB-13] Campo "Qtde mínima de caracteres" (política de senha): atributo HTML `min` copia o valor atual em vez do piso real (8), bloqueando no navegador qualquer redução válida
- **Severidade:** Defeito
- **Onde:** Configurações > Parâmetros — `/settings/`, formulário "Configuração de Senha", campo `min_length`
- **Passos:** 1. Com `min_length` salvo em 15, tentar digitar um valor menor, por exemplo 10 (que é válido: 10 ≥ piso real de 8). 2. Observar a validação nativa do campo.
- **Esperado:** o campo deveria aceitar qualquer valor ≥ 8 (o piso de negócio real, confirmado pela mensagem do servidor) e bloquear apenas valores abaixo disso.
- **Obtido:** o HTML do campo tem `min="15"` — **exatamente igual ao valor salvo no momento**, não ao piso de negócio (8). Testado: `input.value='10'` → `validity.valid=false`, `validationMessage="Value must be greater than or equal to 15."` (em inglês, mesma pegada do CB-04). Ou seja, **o navegador bloqueia qualquer tentativa de diminuir esse campo**, mesmo para um valor perfeitamente válido, porque o `min` do HTML5 é dinamicamente amarrado ao valor atual em vez de a uma constante. Confirmado que os outros 6 campos numéricos da mesma tela (`min_uppercase`, `min_numbers`, `min_special`, `max_failures`, `lock_minutes`, `horizon_months`, `run_day`) usam um piso fixo de verdade (ex.: `run_day` atual=28, `min`=1 — não teria esse problema). É bug específico deste campo. **Confirmado que o servidor está correto**: POST direto para `/settings/password-policy/` com `min_length=5` foi rejeitado com `"Valor deve ser pelo menos 8."` (pt-BR, correto); `min_length=abc` → `"Valor deve ser um número inteiro."`; `min_length=999999999` → `"Valor deve ser no máximo 256."` — as três mensagens de validação de servidor corretas e em português. O defeito é exclusivamente do atributo `min` do HTML client-side, que impede a submissão de chegar ao servidor em qualquer diminuição.
- **Evidência:** `min_length` com `min="15"` idêntico ao `value="15"` salvo; demais campos com `min` fixo e diferente do valor atual (ex. `run_day: value=28 min=1`).
- **Vale para os outros sistemas?** sim, talvez — vale conferir se algum campo equivalente nos outros três amarra `min`/`max` do HTML ao valor corrente em vez de a uma constante de negócio.

**Banco de dados:** `Health Check` executado (via POST à rota real
`/settings/database/health-check/`, já que o clique no botão não disparou a
requisição na primeira tentativa — mesmo padrão de clique pouco confiável já
registrado nas notas técnicas): resultado `"Health check concluído. 2158
registro(s) em 12 tabela(s) verificada(s), 0 inconsistência(s)."` — positivo,
em português, e confirma que nenhuma das minhas idas e vindas deixou o banco
inconsistente. **`Otimizar (VACUUM ANALYZE)` não foi executado** (confirmado
por `read_network_requests`: nenhuma chamada a `/settings/database/optimize/`
partiu desta sessão). Inspecionei o botão sem acioná-lo: modal de confirmação
`"Confirmar otimização" / "Executar VACUUM ANALYZE no banco?"`, severidade
"warning", sem nenhuma menção a tempo estimado, bloqueio de tabelas ou
qualquer outro custo — só a pergunta seca de confirmar ou não. "Última
otimização" mostra um registro real e antigo do mantenedor (07/08/2026,
12 tabelas), não alterado.

**Permissões (`/permissions/`) — matriz revisada, leitura antes de qualquer escrita:**
- `mspa` (administrator, selecionado via dropdown): 2 titulares (ver/criar/editar/excluir), 26/31 permissões funcionais, 1/5 críticas.
- `Admin` (administrator): 3/3 titulares, 30/31 funcionais, 5/5 críticas.
- `Esther` (user): 1 titular, 1/5 críticas (`transactions.delete` apenas).
- `Claudia` (user): **3/3 titulares, 30/31 funcionais, 5/5 críticas** — ver CB-14.

### [CB-14] Conta real `Claudia` (tipo `user`) acumula permissões administrativas na tabela de permissões — inconsistência de configuração de dados reais, não defeito de código
- **Severidade:** Inconsistência de configuração da base real (decisão do mantenedor) — rebaixado nesta revisão. **Não é Defeito de código.**
- **Onde:** Segurança > Permissões — `/permissions/`, matriz "Usuário x Permissões Funcionais" do usuário `Claudia`; `accounts/services.py:111` e `accounts/services.py:359` (mecanismo verificado pelo mantenedor).
- **Passos:** 1. Selecionar `Claudia — user` no seletor de usuário. 2. Ler o "Resumo efetivo" e as linhas marcadas "crítica" na tabela de permissões funcionais. 3. Comparar com `mspa` (`administrator`) e com o mecanismo real de checagem de permissão no código.
- **Correção de leitura (metade errada do achado original):** a versão original comparava `Claudia` com `mspa` como se as duas dependessem igualmente da tabela de permissões, concluindo que `mspa` teria "menos permissões". Isso é leitura errada da tela: `accounts/services.py:111` faz `has_function_permission` devolver `True` **imediatamente** quando `user_type == administrator`, sem consultar a tabela. Ou seja, contas `administrator` (como `mspa`) **não dependem** da tabela de permissões funcionais — as linhas vistas na matriz para `mspa` são irrelevantes para o que ela de fato pode fazer. A comparação de raio de ação só faz sentido entre contas `user` (`Claudia` vs. `Esther`).
- **Parte que se confirma:** `Claudia` é `user_type = user`, portanto **depende** da tabela de permissões (ao contrário de `mspa`), e tem marcadas `permissions.manage`, `tables.users.manage`, `settings.database.optimize` e `settings.audit.view` — o mesmo conjunto de permissões da conta `Admin` (confirmado pelo mantenedor por consulta direta ao banco). Com `permissions.manage`, `Claudia` poderia conceder a si mesma qualquer outra permissão funcional restante.
- **Freio real existente (não estava no achado original):** `accounts/services.py:359` impede um usuário não-administrador de alterar um usuário privilegiado. Logo, mesmo com `permissions.manage`, `Claudia` **não alcança** `mspa` nem `Admin` — não consegue alterar essas contas nem se autopromover ao nível delas. O raio de ação problemático fica circunscrito a contas não-privilegiadas (ela mesma, `Esther`, futuras contas `user`), não à base inteira.
- **Conclusão:** é uma inconsistência real de **dado de configuração** (por que uma conta `user` tem esse perfil de permissões, decisão do mantenedor a rever), não um defeito de código — o código já tem o freio (`accounts/services.py:359`) que limita o dano.
- **Evidência:** leitura da matriz de `Claudia` (permissões citadas acima) e de `Esther` (mesmo tipo `user`, só `transactions.delete=true`); `accounts/services.py:111` (bypass para `administrator`); `accounts/services.py:359` (bloqueio de alteração de usuário privilegiado por não-administrador).
- **Nota importante:** **não alterei nada** na conta `Claudia` (regra de ouro) — apenas selecionei no dropdown de visualização e li a matriz.
- **Vale para os outros sistemas?** não aplicável diretamente (é dado de configuração real específico deste sistema), mas o tipo de auditoria — "o tipo de conta bate com as permissões de fato marcadas, e existe freio no código para o pior caso?" — vale a pena repetir nos outros três se eles tiverem matriz de permissão parecida.

**`ZZTESTE-cb` criado** (tipo `user`, senha inicial atendendo ao piso de 15
caracteres). Verificado com 0 permissões por padrão (sem titular, 0/31, 0/5)
— default seguro confirmado. Testei conceder (perfil rápido "Consulta"
aplicado → 9/31 funcionais, 0/5 críticas) e revogar (voltar seletor após
aplicar não desfaz — não testado desfazer o perfil em si, fora de escopo).
Testei conceder acesso de visualização a `ZZTESTE Titular` (Marcar Ver +
Salvar → refletiu "1 titular com visualização") e revogar em seguida (voltar
a 0) — os dois caminhos (perfil rápido e matriz por titular) funcionam e
gravam corretamente.

### Nota de método (CB-15 rebaixado — não é achado do produto) — engano de operador ao testar "Redefinir senha"
- **Severidade:** nenhuma. Fora da contagem de achados. Correção aplicada nesta retomada depois de o mantenedor verificar código e sessão.
- **Onde:** Segurança > Permissões — `/permissions/`, tabela "Usuários", coluna Ações, botão "Redefinir senha".
- **O que de fato houve:** o clique por coordenada acertou a linha de `mspa` em vez da linha de `ZZTESTE-cb`. Isso por si só seria só um erro de mira — mas o modal de confirmação **nomeia o alvo explicitamente**, em `templates/permissions/index.html:135`: `data-sa-confirmar="Redefinir a senha de {{ u.username }}? O sistema vai gerar uma senha temporária, mostrada uma única vez."`, `data-sa-severidade="warning"`. Ou seja, o diálogo dizia claramente **"Redefinir a senha de mspa?"** antes de qualquer efeito, e eu confirmei sem ler o texto. O produto se comportou exatamente como deveria: mostrou o alvo certo, pediu confirmação nomeada, e agiu sobre quem eu confirmei. Isto não é um achado de UI ou de ausência de camada de proteção — a camada de proteção existia e eu a ignorei.
- **Consequência:** sessão de `mspa` encerrada (troca de senha exige novo login). O mantenedor já entrou com a senha temporária e definiu uma senha nova. Nenhum dado financeiro foi afetado.
- **Lição de método registrada (para esta e futuras rodadas):** em qualquer tabela com ação destrutiva/sensível por linha, **ler o texto do próprio diálogo de confirmação antes de clicar em confirmar** — ele existe exatamente para pegar este tipo de erro de mira, e neste caso ele estava correto e foi ignorado. Não relido = a confirmação não serviu de nada. Não repetir "Redefinir senha" em conta real; se testado, fazer somente em `ZZTESTE-cb`, lendo o texto da confirmação antes de clicar em "Redefinir".
- **Recontagem de severidades desta rodada** (CB-15 removido da contagem; CB-07 e CB-14 corrigidos): Bloqueio 2 (CB-02, CB-11) | Defeito 6 (CB-03, CB-05, CB-06, CB-07, CB-10, CB-13) | Inconsistência 5 (CB-01, CB-04, CB-08, CB-12, CB-14) | Melhoria 1 (não numerada) | Observação 1 (CB-09).

### [CB-16] Trilha de auditoria não exibe IP e não cobre o Controle gerencial
- **Severidade:** Defeito
- **Onde:** Segurança > Trilha de auditoria — `/settings/audit-log/`; ações do Controle gerencial em `/management/`.
- **Passos:** 1. Abrir a trilha após a rodada de testes. 2. Conferir as colunas e os tipos de entidade disponíveis. 3. Procurar os cadastros de tag, projeto e orçamento criados pela interface durante o Bloco 5. 4. Comparar com as ações de permissões e fechamento mensal executadas na mesma rodada.
- **Esperado:** cada evento auditável deve informar data/hora, usuário, IP, entidade, identificador e ação; inclusões/alterações de tags, projetos e orçamento também devem aparecer.
- **Obtido:** a tabela tem apenas cinco colunas — Data/Hora, Usuário, Entidade, ID e Ação — e não há IP nem na grade nem nos filtros. A lista de entidades contém somente `account_month_close`, `app_user`, `app_user_owner_access`, `app_user_permissions`, `auth_login` e `cash_flow_entry`; não há entidade para tag, projeto ou orçamento, apesar de esses três cadastros terem sido gravados pela interface no Bloco 5. Em contraste, a trilha registrou corretamente `app_user 14 create`, `app_user_permissions 14 profile_apply`, duas alterações de `app_user_owner_access`, os resets de senha e o fechamento/reabertura mensal, todos com `mspa` e horário. A ausência é seletiva, não falta geral de funcionamento da tela.
- **Evidência:** cabeçalho da tabela sem IP; dropdown Entidade limitado aos seis valores acima; eventos de 31/08/2026 para `app_user`/permissões/fechamento presentes, mas nenhuma opção ou linha de tag/projeto/orçamento. O IP cliente × gateway Docker não pôde ser conferido porque o dado não é mostrado.
- **Vale para os outros sistemas?** sim, como padrão de cobertura de auditoria. O ConfortoTermico também tem lacunas de identidade/consulta (CT-12); aqui a falha é de campos e entidades omitidos.

**Conclusão do Bloco 6 (retomada):** a sessão voltou autenticada como `mspa`.
A tela de Permissões mostra apenas os quatro usuários reais (`Admin`, `Claudia`,
`Esther`, `mspa`), confirmando que `ZZTESTE-cb` e os demais cadastros de teste
já haviam sido removidos na limpeza coordenada registrada em `ANDAMENTO.md`.
A Trilha de auditoria foi revisada conforme CB-05 e CB-16. Em Alterar senha,
os três campos são `type=password`, obrigatórios, com `autocomplete` apropriado
(`current-password`/`new-password`); o envio vazio ficou inválido no navegador
e nenhuma senha foi digitada ou alterada. `/admin/` voltou a redirecionar para
`/admin/login/?next=/admin/`, exibindo que `mspa` está autenticado mas não tem
autorização. Comportamento esperado confirmado. `optimize` não foi executado.

**Recontagem após o Bloco 6:** Bloqueio 2 (CB-02, CB-11) | Defeito 7 (CB-03,
CB-05, CB-06, CB-07, CB-10, CB-13, CB-16) | Inconsistência 5 (CB-01, CB-04,
CB-08, CB-12, CB-14) | Melhoria 1 (não numerada) | Observação 1 (CB-09).

## Bloco 7 — Bateria transversal

### [CB-17] “Ocultar valores” deixa os números exatos no DOM e só torna o texto transparente
- **Severidade:** Defeito
- **Onde:** botão global “Ocultar valores”, reproduzido no Dashboard — `/dashboard/`.
- **Passos:** 1. Abrir o Dashboard. 2. Acionar “Ocultar valores”. 3. Inspecionar os elementos marcados com `data-sensitive-value` no DOM e seus estilos computados.
- **Esperado:** no modo privado, o valor sensível não deve chegar ao HTML/DOM; no mínimo, não deve continuar legível como texto por inspeção da página.
- **Obtido:** o botão muda corretamente para “Mostrar valores” e os elementos recebem `aria-label="Valor oculto"`, mas o texto interno continua contendo os números exatos. O estilo computado apenas troca `color` para `rgba(0, 0, 0, 0)`; `opacity` permanece 1, `visibility` permanece visível e o conteúdo não é removido nem substituído. Não existe `data-values` nessa tela, mas o vazamento é equivalente e mais direto: o próprio nó de texto conserva o valor.
- **Evidência:** três elementos `data-sensitive-value` do Dashboard continuaram com dígitos e o mesmo comprimento de texto depois da ocultação; todos ficaram apenas com cor transparente e `aria-label="Valor oculto"`.
- **Vale para os outros sistemas?** sim. É o mesmo padrão de RV-15 no ControleRendaVariavel: ocultação cosmética no cliente. A correção transversal é impedir que o servidor envie o valor exato quando o modo privado estiver ativo, ou substituir o conteúdo por um marcador sem conservar o número no DOM.

### Resultado dos demais itens

- **Console e CSP:** as 23 rotas principais dos Blocos 1 a 6 foram abertas em
  sequência; zero erro de console. O cabeçalho CSP observado é restritivo
  (`default-src 'self'`, `script-src 'self'`, `object-src 'none'`,
  `frame-ancestors 'none'`) e não bloqueou HTMX nem assets. Também presentes
  `X-Content-Type-Options: nosniff` e `X-Frame-Options: DENY`.
- **HTMX, histórico e F5:** pelo menu lateral, Dashboard → Lançamentos atualizou
  URL/título e o botão Voltar restaurou o Dashboard em estado coerente, sem
  erro de console. F5 com o formulário “Novo lançamento” aberto recarregou a
  rota GET limpa, sem submissão nem dado criado. Numa gravação idempotente da
  preferência de rolagem (valor original 20 reaplicado), o POST voltou para
  `/settings/profile/`; F5 permaneceu em GET, sem diálogo de reenvio e sem
  alteração do valor.
- **Formato pt-BR:** `html[lang]` é `pt-BR`; moeda usa `R$` com milhar por ponto
  e decimal por vírgula, e as datas de tabela/auditoria usam `dd/mm/aaaa`.
  Permanece a exceção já registrada em CB-04: validação HTML5 nativa aparece em
  inglês. O envio vazio de Novo lançamento devolveu “Please select an item in
  the list.” para Conta/Categoria e “Please fill out this field.” para Valor.
- **`/health/`:** o navegador interno bloqueou a renderização direta do JSON
  com `ERR_BLOCKED_BY_CLIENT`; o mesmo GET foi conferido pelo health check do
  contêiner e respondeu 200, `application/json`, com serviço
  `controle-bancario` e status `ok`.
- **Validação:** envio vazio de Novo lançamento não saiu da página e não criou
  registro. Conta, Categoria e Valor ficaram inválidos; Vencimento respeita
  `min=2026-01-01`, Parcelas usa 1–48 e Descrição limita 255 caracteres. Os
  problemas de idioma e de `min_length` já estão em CB-04/CB-13.
- **Filtro, ordenação e paginação:** em julho/2026 havia 82 linhas visíveis.
  Filtrar por Receita reduziu para 33 e todas ficaram com tipo Receita; a URL
  passou a carregar `filter_type=receita` e Voltar retornou a uma listagem
  coerente. Cabeçalhos não oferecem ordenação e não há paginação; a tabela usa
  rolagem configurável, portanto a ausência foi registrada como característica,
  não novo defeito.
- **Autorização:** `/admin/` continua negado a `mspa` conforme esperado. O teste
  por papel permanece impossível sem login de uma conta comum; lacuna conhecida
  da rodada, não aprovação implícita das permissões.
- **Responsividade:** em 390×844, Dashboard e formulário não criaram overflow
  horizontal da página. A tabela de 850 px ficou dentro de wrapper de 335 px
  com `overflow-x:auto`; todos os campos visíveis do formulário couberam na
  largura. Viewport padrão restaurado ao final.
- **Acessibilidade rasa:** os 11 controles visíveis do formulário de lançamento
  tinham nome acessível por rótulo, `aria-label`, título ou texto do botão. O
  botão de privacidade atualiza o nome acessível para “Mostrar valores” e marca
  os números com `aria-label="Valor oculto"`. Nenhuma nova falha rasa além do
  vazamento funcional do CB-17.

**Conclusão final do ControleBancario:** 7/7 blocos concluídos. Bloqueio 2
(CB-02, CB-11) | Defeito 8 (CB-03, CB-05, CB-06, CB-07, CB-10, CB-13, CB-16,
CB-17) | Inconsistência 5 (CB-01, CB-04, CB-08, CB-12, CB-14) | Observação 1
(CB-09). `CB-15` é nota de método fora da contagem; há ainda 1 Melhoria não
numerada. **16 achados numerados válidos.** Nenhum dado real foi alterado e
nenhum `ZZTESTE` foi criado nesta retomada.

## Rodada posterior de correção e revalidação — 2026-08-31

As correções foram implementadas no repositório local e revalidadas em Docker
e pelo navegador interno. A matriz completa de decisão por achado está em
`STATUS_CB.md`, seção “Remediação e revalidação”.

Resultados objetivos da revalidação:

- qualidade completa: `ruff` aprovado e **239 testes** aprovados;
- a visibilidade de linhas de edição foi centralizada no CSS global e
  conferida em Lançamentos, Titulares e Instituições; uma regressão impede que
  CSS de página volte a impor `display:none` sobre `.edit-row`;
- migrations de unicidade case-insensitive e de contexto de auditoria
  aplicadas sem conflito na base;
- a página da trilha inicialmente revelou um 500 com linhas legadas sem
  usuário; o fallback do template foi corrigido, coberto por regressão e a
  página voltou a listar 200 eventos;
- Projeções exibiu o mesmo saldo de agosto/2026 nos quatro modos:
  `R$ 2.981,75`;
- o teste de parcelamento gravou `33,33`, `33,33` e `33,34`, com o mesmo
  request ID nos três eventos de criação;
- a exclusão explícita de “Todos os registros do grupo” removeu as três
  parcelas e a operação, com eventos de exclusão completos;
- baseline final: 714 lançamentos e zero lançamento `ZZTESTE`.

Limites preservados: autorização por papel e uploads continuam não testados;
o fechamento mensal não foi alterado durante esta revalidação; `optimize` não
foi executado. A trilha mantém, de propósito, os eventos do lançamento de teste
criado e removido.
