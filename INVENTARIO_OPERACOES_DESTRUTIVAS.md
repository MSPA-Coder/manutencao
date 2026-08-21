# Inventário de operações que mudam estado — os quatro aplicativos

Levantado em 2026-08-21. Entregável da **Fase 0b** de
[PLANO_SINAL_E_DEFEITOS.md](PLANO_SINAL_E_DEFEITOS.md), e lista de trabalho da
Fase 9 (adoção da confirmação comum).

---

## 1. Por que este documento existe

A Fase 0b tinha sido dada por concluída com uma *medição*: quatro mecanismos
de confirmação diferentes, ~79 rotas que mutam estado, 92 funções com nome de
exclusão ou alteração. Números não são inventário. Sem saber **qual** rota,
**em qual arquivo**, **com ou sem** confirmação e **reversível ou não**, a
regra que o plano adotou — *irreversível pede, reversível não pede* — não tem
como ser aplicada, e a Fase 9 não tem sobre o que trabalhar.

Este documento é a lista que faltava.

---

## 2. Método e critério

Leitura de código, um levantamento independente por projeto. Para cada rota
que escreve no banco, foi rastreado o caminho da view até o SQL, e do botão no
template até a rota.

O critério de reversibilidade é deliberadamente do ponto de vista do
**usuário**, não do banco:

- **Reversível** — dá para desfazer sozinho pela interface, sem restaurar
  backup. Editar um campo (pode editar de volta), marcar um sinalizador,
  criar um registro que também dá para excluir.
- **Irreversível** — o dado sai e só volta por restauração de backup. Excluir,
  apagar em cascata, sobrescrever histórico, recalcular por cima do anterior.

Na dúvida, classificado como irreversível e a dúvida anotada.

Uma consequência que aparece várias vezes abaixo e não é óbvia: **criar** um
registro conta como irreversível quando o projeto não tem rota para excluí-lo.
Não é um problema de confirmação, é uma funcionalidade que falta — e está
separado como tal.

---

## 3. Panorama

| Projeto | Operações que mutam estado | Com confirmação | Mecanismo |
|---|---:|---:|---|
| ControleBancario | 50 | 9 | `data-confirm` → modal próprio |
| ControleRendaVariavel | 41 | 13 | `hx-confirm` (HTMX → `window.confirm`) |
| ConfortoTermico | 23 | 5 | `confirm()` nativo |
| MegaSena | 10 | 2 | `hx-confirm` (+ caminho redundante) |

**Correção ao levantamento anterior.** O plano registrava o MegaSena como
tendo "os três mecanismos misturados, 2 + 2 + 3". Está errado. São dois
mecanismos redundantes cobrindo **os mesmos dois botões**: `hx-confirm` em
`users/_table.html:26` e `settings/index.html:38`, e um caminho por
`data-confirm-message` em `base.js:59` que a própria guarda de `base.js:58`
pula quando o `hx-confirm` está presente. O resto do aplicativo não confirma
nada. O número real de operações protegidas é 2, não 7.

---

## 4. Os casos graves

Irreversível **e** sem confirmação nenhuma. A Fase 0b previa corrigir estes
imediatamente, sem esperar o bloco 2, com o mecanismo que cada projeto já tem.

| # | Projeto | Operação | O que se perde | Situação |
|---|---|---|---|---|
| 1 | CRV | Encerrar posição (ação e opção) | extrato de movimentos apagado em cascata; sobra resumo sem preço nem custo | corrigido em 2026-08-21 |
| 2 | CRV | Editar posição trocando a carteira para "Simulada" | extrato inteiro apagado como efeito colateral de um "Salvar" comum | corrigido em 2026-08-21 |
| 3 | CRV | Atualizar cotações (período / desde a abertura) | sobrescreve preços já gravados, inclusive lançamentos manuais | corrigido em 2026-08-21 |
| 4 | Bancário | Editar parcelado com escopo "este e os próximos" | apaga e recria o bloco; comprovantes anexados somem por `CASCADE` | corrigido em 2026-08-21 |
| 5 | MegaSena | Importar planilha (arquivo e link) | sobrescreve prêmios, ganhadores e data de concursos já cadastrados | corrigido em 2026-08-21 |
| 6 | ConfortoTermico | `POST /api/reset` | apaga a série temporal inteira com trava só no navegador | corrigido em 2026-08-21 |

O **#2 é o pior do conjunto**, e não pelo tamanho do estrago: é destruição de
histórico com aparência de edição rotineira. O usuário escolhe uma carteira num
`<select>`, clica em Salvar e recebe "Posição atualizada." Nada na tela
distingue esse clique de qualquer outra edição.

O **#6 é de natureza diferente** dos outros cinco — não é ausência de
confirmação, é confirmação que só existe no navegador. Havia duas rotas
apagando exatamente o mesmo dado, uma exigindo texto digitado e validado no
servidor, a outra confiando num `confirm()` de front. Proteção que só existe
no cliente não é proteção.

### Grave adjacente, não corrigido aqui

**MegaSena — criar usuário é permanente.** Não existe rota de exclusão de
usuário, só desativação; o nome fica ocupado para sempre. Isso não se resolve
com confirmação — falta funcionalidade. Fica na seção 6.

---

## 5. Achados colaterais

Coisas que apareceram no caminho e não são falta de confirmação.

**Bancário — uma trava de segurança que nunca dispara.** A view de projeção
recorrente (`core/views.py:558-568`) checa `confirm_current_month` para avisar
que a projeção já rodou no mês. O template
(`templates/settings/index.html:87`) manda esse campo **fixo em `value="on"`**,
num campo oculto. O aviso, portanto, é inalcançável. É a mesma família do
`/health` que devolvia `"ok"` fixo: a verificação existe no código, está
escrita corretamente, e não pode reprovar.

**Bancário — três rotas POST órfãs.** `transactions:cancel_entry`,
`transactions:close_month` e `transactions:reopen_month`
(`transactions/urls.py:19,28-29`) mudam estado e nenhum template as aciona; as
telas usam o caminho equivalente em `core:`. São superfície acessível por
requisição direta sem tela correspondente — dívida a remover ou a assumir.

**Bancário — "ignorar linha de extrato" não tem como ser desfeito.** A
conciliação tem "Desfazer"; ignorar não tem. A confirmação existe, o caminho de
volta não.

**ConfortoTermico — um bloco inteiro da aba Sistema é invisível.** O botão
"Limpar histórico" (`btn-limpar`, `templates/index.html:235`) nasce com a classe
`oculto`, que é `display: none !important`. O `app.js` o **move** para a seção
de histórico da aba Sistema, mas nem `moverCampo` nem `moverCheck` removem a
classe, e nada mais no projeto a remove. O mesmo vale para `cfg-sons`,
`cfg-emails` e `wrap-email-destino` — este último só é revelado por um
`change` no `cfg-emails`, que é um checkbox que ninguém consegue marcar.

Que é defeito e não padrão, prova-se por comparação: os outros campos movidos
pela mesma função (`cfg-intervalo-leitura`, `cfg-ponto-orvalho`, `cfg-altitude`)
**não** têm `oculto`. A classe ali significa "escondido", não "aguardando ser
movido". E o gate de permissão deste projeto é `{% if "sistema" in
areas_permitidas %}` no template, não CSS.

Consequência para o caso grave 6: **`/api/reset` não tem interface hoje** — só é
alcançável por chamada direta. A trava de servidor que entrou em 2026-08-21 é,
portanto, a única proteção que existe, e não uma segunda camada.

Deliberadamente **não corrigido**: revelar `cfg-emails` pode fazer o sistema
começar a enviar e-mail sem que o SMTP tenha sido conferido, e revelar
`btn-limpar` acrescenta à interface um botão que apaga a série temporal inteira.
Ambos são decisão de produto do mantenedor, não conserto óbvio.

**ConfortoTermico — um GET que escreve.** `GET
/api/dados-entrada/configuracoes` (`app/dados_entrada_rotas.py:25` →
`dados_entrada_db.py:88-97`) faz INSERT/UPDATE em `configuracoes_zona`. GET
deve ser seguro por contrato; qualquer prefetch de navegador, robô ou sonda de
monitoração escreve no banco ao passar por ali. O efeito é idempotente, então
não é perda de dado — é contrato quebrado, e vale arrumar antes que alguém
construa em cima.

**ConfortoTermico — excluir zona deixa leitura órfã.** A cascata apaga
equipamentos, controle e agregados, mas `leituras` usa `ON DELETE SET NULL`
(`migrations/versions/20260803_0001_baseline.py:24-31`). A série bruta
sobrevive sem referência de zona. Provavelmente deliberado — vale registrar,
porque parece perda e não é.

**CRV — guarda de duplicata em vez de confirmação.** Criar posição responde
409 com um `confirm_duplicate` para reenvio, em vez de perguntar antes. Não
conta como confirmação pelo critério deste inventário, mas mitiga clique duplo
e merece ficar como está.

---

## 6. O que fica para a Fase 9

Nada abaixo é grave. É o trabalho normal de adoção quando o componente comum
existir.

1. **Regra a aplicar em tudo:** irreversível pede, reversível não pede.
   Confirmar tudo treina o usuário a clicar "sim" sem ler, e aí a confirmação
   deixa de proteger. Várias linhas marcadas "NÃO / sim" abaixo devem
   permanecer sem confirmação — não são pendências.
2. **Bancário:** trocar os 9 `data-confirm` pelo componente comum; acertar a
   inconsistência do "Conciliar" por linha (o em lote confirma, o individual
   não); decidir o destino das três rotas órfãs; consertar o
   `confirm_current_month` fixo.
3. **CRV:** trocar os 13 `hx-confirm`. Atenção ao ponto já registrado no plano —
   o HTMX cancela a requisição pelo retorno do `confirm`, e com modal a
   confirmação é assíncrona (`htmx:confirm` com `evt.preventDefault()`).
4. **ConfortoTermico:** unificar os `confirm()`; padronizar a exigência de
   digitar "APAGAR" nas duas rotas de destruição total; arrumar o GET que
   escreve.
5. **MegaSena:** é onde há menos a migrar e mais a acrescentar — só dois botões
   confirmam hoje. Avaliar exclusão de usuário e de lote de apostas, que hoje
   não existem.
6. **Ícone por severidade** em tudo o que ficar: exclusão e sobrescrita são
   "perigo"; desativar e ignorar são "atenção".

---

## 7. As tabelas

Convenção: **Confirma** diz o mecanismo ou `NÃO`. **Rev.** é reversível pela
interface, sem backup.

### 7.1 ControleBancario — 50 operações, 9 confirmam

| # | Operação | Arquivo:linha | Confirma | Rev. |
|---|---|---|---|---|
| 1 | Criar titular | `accounts/views.py:50` | NÃO | sim |
| 2 | Editar titular | `accounts/views.py:63` | NÃO | sim |
| 3 | Excluir titular | `accounts/views.py:77` | `data-confirm` | NÃO |
| 4 | Trocar a própria senha | `accounts/views.py:134` | NÃO | sim |
| 5 | Criar instituição | `banking/views.py:44` | NÃO | sim |
| 6 | Editar instituição | `banking/views.py:57` | NÃO | sim |
| 7 | Excluir instituição | `banking/views.py:75` | `data-confirm` | NÃO |
| 8 | Criar conta | `banking/views.py:120` | NÃO | sim |
| 9 | Editar conta | `banking/views.py:139` | NÃO | sim |
| 10 | Excluir conta | `banking/views.py:160` | `data-confirm` | NÃO |
| 11 | Importar extrato | `bank_statements/views.py:42` | NÃO | sim¹ |
| 12 | Conciliar linha (individual) | `bank_statements/views.py:102` | **NÃO** | sim |
| 13 | Criar lançamento a partir de linha | `bank_statements/views.py:121` | `data-confirm` | sim |
| 14 | Ações em lote (conciliar/criar/ignorar) | `bank_statements/views.py:140` | `data-confirm` ×3 | parcial² |
| 15 | Desfazer conciliação | `bank_statements/views.py:175` | `data-confirm` | sim |
| 16 | Anexar comprovante | `bank_statements/views.py:214` | NÃO | sim¹ |
| 17 | Ignorar linha de extrato | `bank_statements/views.py:255` | `data-confirm` | **NÃO** |
| 18 | Excluir usuário | `core/views.py:101` | `data-confirm` | NÃO |
| 19 | Editar usuário | `core/views.py:114` | NÃO | sim |
| 20 | Criar usuário | `core/views.py:138` | NÃO | sim |
| 21 | Salvar permissões funcionais | `core/views.py:159` | NÃO | sim |
| 22 | Salvar acessos por titular | `core/views.py:176` | NÃO | sim |
| 23 | Aplicar perfil rápido | `core/views.py:200` | NÃO | sim |
| 24 | Atualizar tema | `core/views.py:256` | NÃO | sim |
| 25 | Atualizar scroll de tabelas | `core/views.py:265` | NÃO | sim |
| 26 | Visibilidade de contas | `core/views.py:279` | NÃO | sim |
| 27 | Fechar mês (Configurações) | `core/views.py:383` | NÃO | sim |
| 28 | Reabrir mês (Configurações) | `core/views.py:405` | NÃO | sim |
| 29 | Health check do banco | `core/views.py:439` | NÃO | n/a |
| 30 | Otimizar banco (VACUUM ANALYZE) | `core/views.py:454` | NÃO | n/a |
| 31 | Política de senha | `core/views.py:497` | NÃO | sim |
| 32 | Política de bloqueio de login | `core/views.py:519` | NÃO | sim |
| 33 | Config. de projeção recorrente | `core/views.py:538` | NÃO | sim |
| 34 | Executar projeção agora | `core/views.py:558` | trava morta³ | sim |
| 35 | Realizar lançamento | `transactions/views.py:158` | NÃO | sim |
| 36 | Cancelar lançamento | `transactions/views.py:191` | NÃO | sim⁴ |
| 37 | Criar lançamento | `transactions/views.py:213` | NÃO | sim |
| 38 | Editar lançamento (single/all) | `transactions/views.py:260` | NÃO | sim |
| 39 | **Editar "este e os próximos"** | `transactions/services.py:1038` | **corrigido** | **NÃO** |
| 40 | Excluir lançamento | `transactions/views.py:301` | modal próprio | NÃO |
| 41 | Fechar mês (Transações) | `transactions/views.py:328` | NÃO | sim⁴ |
| 42 | Reabrir mês (Transações) | `transactions/views.py:355` | NÃO | sim⁴ |
| 43 | Criar categoria | `transactions/views.py:394` | NÃO | sim |
| 44 | Editar categoria | `transactions/views.py:407` | NÃO | sim |
| 45 | Excluir categoria | `transactions/views.py:421` | `data-confirm` | NÃO |
| 46 | Criar tag | `management/views.py:65` | NÃO | sim |
| 47 | Criar projeto/centro de custo | `management/views.py:77` | NÃO | sim |
| 48 | Salvar orçamento mensal | `management/views.py:89` | NÃO | sim |
| 49 | Vincular tag a lançamento | `management/views.py:114` | NÃO | sim |
| 50 | Vincular projeto a lançamento | `management/views.py:126` | NÃO | sim |

¹ Não há rota para excluir o lote importado nem o anexo — só "ignorar".
² Conciliar e criar são reversíveis; **ignorar não tem desfazer**.
³ `confirm_current_month` vem fixo do template; a checagem nunca reprova.
⁴ Rota órfã: nenhum template a aciona hoje.

### 7.2 ControleRendaVariavel — 41 operações, 13 confirmam

| # | Operação | Arquivo:linha | Confirma | Rev. |
|---|---|---|---|---|
| 1 | Criar posição (ação) | `routes/positions.py:225` | guarda de duplicata | sim |
| 2 | **Editar posição (ação)** | `routes/positions.py:296` | **corrigido**¹ | **NÃO**¹ |
| 3 | Excluir posição (ação) | `routes/positions.py:338` | `hx-confirm` | NÃO |
| 4 | **Encerrar posição (ação)** | `routes/positions.py:370` | **corrigido** | **NÃO** |
| 5 | Criar posição (opção) | `routes/options.py:244` | guarda de duplicata | sim |
| 6 | **Editar posição (opção)** | `routes/options.py:313` | **corrigido**¹ | **NÃO**¹ |
| 7 | Excluir posição (opção) | `routes/options.py:340` | `hx-confirm` | NÃO |
| 8 | **Encerrar posição (opção)** | `routes/options.py:371` | **corrigido** | **NÃO** |
| 9 | Criar vencimento de opção | `routes/options.py:427` | NÃO | sim |
| 10 | Excluir vencimento | `routes/options.py:450` | `hx-confirm` | NÃO |
| 11 | Editar vencimento | `routes/options.py:462` | NÃO | sim |
| 12 | Criar contrato de opção | `routes/options.py:482` | NÃO | sim |
| 13 | Excluir contrato | `routes/options.py:515` | `hx-confirm` | NÃO |
| 14 | Editar contrato | `routes/options.py:527` | NÃO | sim |
| 15 | Criar transação | `routes/transactions.py:270` | NÃO | sim |
| 16 | Editar transação | `routes/transactions.py:355` | NÃO | sim |
| 17 | Desfazer encerramento parcial | `routes/transactions.py:385` | `hx-confirm` | NÃO² |
| 18 | Excluir transação fechada | `routes/transactions.py:385` | `hx-confirm` | NÃO |
| 19 | Criar renda/provento | `routes/dividends.py:179` | NÃO | sim |
| 20 | Editar renda | `routes/dividends.py:210` | NÃO | sim |
| 21 | Excluir renda | `routes/dividends.py:231` | `hx-confirm` | NÃO |
| 22 | Criar corretora | `routes/tables.py:50` | NÃO | sim |
| 23 | Editar corretora | `routes/tables.py:74` | NÃO | sim |
| 24 | Excluir corretora | `routes/tables.py:101` | `hx-confirm` | NÃO |
| 25 | Criar ticker | `routes/tables.py:118` | NÃO | sim |
| 26 | Editar ticker | `routes/tables.py:136` | NÃO | sim |
| 27 | Excluir ticker | `routes/tables.py:164` | `hx-confirm` | NÃO |
| 28 | Criar carteira | `routes/tables.py:266` | NÃO | sim |
| 29 | Editar carteira | `routes/tables.py:308` | NÃO | sim |
| 30 | Excluir carteira | `routes/tables.py:351` | `hx-confirm` | NÃO |
| 31 | Associar ticker à carteira | `routes/tables.py:369` | NÃO | sim |
| 32 | Desassociar ticker | `routes/tables.py:390` | `hx-confirm` | sim |
| 33 | Lançar cotação manual | `routes/quotes.py:141` | NÃO | sim |
| 34 | **Atualizar cotações do período** | `routes/quotes.py:168` | **corrigido** | **NÃO** |
| 35 | **Atualizar cotações desde a abertura** | `routes/quotes.py:208` | **corrigido** | **NÃO** |
| 36 | Excluir cotação por data | `routes/quotes.py:240` | `hx-confirm` | NÃO³ |
| 37 | Salvar configurações | `routes/settings.py:131` | NÃO | sim |
| 38 | Refresh do coletor | `routes/settings.py:193` | NÃO | sim |
| 39 | Ligar/desligar coletor RTD | `routes/partials.py:51` | NÃO | sim⁴ |
| 40 | Ingestão do agente Windows | `routes/collector_agent.py:148` | n/a⁵ | sim |
| 41 | Registrar falha do agente | `routes/collector_agent.py:267` | n/a⁵ | sim |

¹ O caso geral de edição é reversível; o ramo "trocar para carteira Simulada"
apaga o extrato via `discard_simulation_history`. A confirmação acrescentada é
condicional a esse ramo, exatamente para não pedir confirmação numa edição
comum.
² Tecnicamente reexecuta `replay_movements` sobre a cadeia inteira; o propósito
é restaurar, mas recalcula histórico.
³ Só recuperável se a data ainda existir no Yahoo. Cotação lançada à mão que
divirja da fonte não volta.
⁴ Não é gravação no Postgres — controla processo externo.
⁵ API máquina-a-máquina com token, sem interface.

### 7.3 ConfortoTermico — 23 operações, 5 confirmam

| # | Operação | Arquivo:linha | Confirma | Rev. |
|---|---|---|---|---|
| 1 | Login registra último acesso | `app/auth.py:460` | NÃO | sim |
| 2 | Criar usuário | `app/auth.py:496` | NÃO | sim |
| 3 | Editar usuário | `app/auth.py:531` | NÃO | sim |
| 4 | Excluir usuário | `app/auth.py:588` | `confirm()` | NÃO |
| 5 | Sincronizar config. de zona (**GET que escreve**) | `app/dados_entrada_rotas.py:25` | NÃO | sim |
| 6 | Salvar config. de zona | `app/dados_entrada_rotas.py:38` | NÃO | sim |
| 7 | Gerar dados sintéticos | `app/dados_entrada_rotas.py:53` | NÃO | sim |
| 8 | Excluir medições geradas | `app/dados_entrada_rotas.py:99` | `confirm()` + "APAGAR" | NÃO |
| 9 | Copiar sintéticos para o histórico | `app/dados_entrada_rotas.py:113` | `confirm()` | NÃO⁶ |
| 10 | Apagar histórico real | `app/dados_entrada_rotas.py:132` | `confirm()` + "APAGAR" servidor | NÃO |
| 11 | Salvar configurações do sistema | `app/ict/administracao.py:73` | NÃO | sim |
| 12 | **`POST /api/reset`** | `app/ict/administracao.py:88` | **corrigido** | **NÃO** |
| 13 | Consolidar histórico (todas) | `app/ict/administracao.py:56` | NÃO | sim |
| 14 | Consolidar histórico (uma zona) | `app/rotas_comuns.py:189` | NÃO | sim |
| 15 | Criar zona | `app/ict/administracao.py:104` | NÃO | sim |
| 16 | Atualizar zona | `app/ict/administracao.py:121` | NÃO | sim |
| 17 | Excluir zona (cascata) | `app/ict/administracao.py:133` | `confirm()` | NÃO⁷ |
| 18 | Criar equipamento | `app/ict/administracao.py:142` | NÃO | sim |
| 19 | Atualizar equipamento | `app/ict/administracao.py:153` | NÃO | sim |
| 20 | Excluir equipamento | `app/ict/administracao.py:169` | `confirm()` | NÃO |
| 21 | Calcular zona (grava leitura) | `app/ict/operacao.py:14` | NÃO | NÃO⁸ |
| 22 | Alterar modo/controle da zona | `app/ict/operacao.py:23` | NÃO | sim |
| 23 | Comandar atuador | `app/ict/operacao.py:32` | `confirm()` só ao ligar | sim |

⁶ Não há como remover só as leituras copiadas; sairiam junto com o histórico.
⁷ Cascata em equipamentos, controle e agregados; `leituras` fica órfã via
`ON DELETE SET NULL`.
⁸ Leitura individual não pode ser removida seletivamente. Não há botão que a
perca por acidente além do reset geral.

### 7.4 MegaSena — 10 operações, 2 confirmam

| # | Operação | Arquivo:linha | Confirma | Rev. |
|---|---|---|---|---|
| 1 | Gravar apostas geradas | `app/web/bets.py:295` | NÃO | NÃO⁹ |
| 2 | Gravar fechamento matemático | `app/web/bets.py:295` | NÃO | NÃO⁹ |
| 3 | **Importar planilha (upload)** | `app/web/contests.py:65` | **corrigido** | **NÃO** |
| 4 | **Importar planilha (link)** | `app/web/contests.py:91` | **corrigido** | **NÃO** |
| 5 | Salvar configurações | `app/web/settings.py:26` | NÃO | sim |
| 6 | Reiniciar base | `app/web/settings.py:44` | `hx-confirm` | NÃO |
| 7 | Criar usuário | `app/web/users.py:51` | NÃO | NÃO⁹ |
| 8 | Redefinir senha | `app/web/users.py:63` | NÃO | sim |
| 9 | Desativar usuário | `app/web/users.py:74` | `hx-confirm` | sim |
| 10 | Reativar usuário | `app/web/users.py:74` | NÃO | sim |

⁹ Irreversível por falta de rota de exclusão, não por destruir dado. A única
forma de remover é "Reiniciar base", que apaga tudo. É funcionalidade que
falta — ver seção 6.
