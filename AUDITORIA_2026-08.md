# Auditoria dos sistemas — agosto/2026

Documento de decisão. Cada achado é numerado e independente: você aceita,
recusa ou adia um por um na tabela da seção 11, e a refatoração implementa
somente o que for aceito.

## 1. Escopo e método

**Base auditada:** o último commit local (`main`) de cada repositório, em
28/08/2026. Não foi consultado o GitHub nem o VPS; não foi executado nenhum
teste, build ou contêiner. Nenhum arquivo dos projetos foi alterado.

| Repositório | Commit base | Python versionado | Arquivos versionados |
|---|---|---|---|
| ConfortoTermico | 26/08 11:56 | 11.463 linhas | 109 |
| ControleBancario | 28/08 08:53 | 14.299 linhas | 233 |
| ControleRendaVariavel | 24/08 23:41 | 14.996 linhas | 162 |
| MegaSena | 24/08 22:17 | 4.756 linhas | 115 |
| BackupRestore | 22/08 12:17 | 3.374 linhas | 36 |
| SharedAuth | 22/08 10:26 | 1.676 linhas | 34 |

**Fora do escopo por decisão sua:** `_manutencao` (infraestrutura do VPS).
**Fora do escopo por não serem repositórios:** `CodexTemp`, `ComissaoDBR`,
`PlaybookVendas`.

**Divergência entre disco e commit.** BackupRestore tem três arquivos não
commitados (`agendamento.py`, `extract_backup.py`, `tests/test_agendamento.py`)
e dois modificados (`.gitignore`, `README.md`). Eles não entraram na auditoria.
Ver [H7](#h7--trabalho-não-commitado-no-backuprestore).

**O que foi examinado:** fábricas de aplicação e configuração dos quatro apps;
os módulos do SharedAuth e sua carta de contratos (`AGENTS.md`); todo o
inventário de parâmetros de query; SQL construído dinamicamente; primitivas
perigosas (`eval`, `exec`, `pickle`, `shell=True`); validação de `next=`;
comparação de tokens; ciclo de vida de sessão e cookies; faixas de dependência;
workflows de CI; endurecimento dos Compose; carga de JavaScript próprio;
padrões de consulta ao banco; e arquivos versionados indevidamente.

## 2. Veredito geral

A avaliação que você fez dos seus sistemas se confirma. Isto não é um conjunto
com problemas de segurança abertos, e a auditoria não encontrou nenhuma
vulnerabilidade explorável remotamente.

O que sustenta essa leitura, verificado item a item:

- **Nenhuma injeção de SQL.** Todos os 12 pontos de SQL construído com f-string
  usam nome de tabela ou coluna de lista fixa ou whitelist, com o motivo
  escrito no ponto da chamada.
- **Nenhum `eval`, `exec`, `pickle.load`, `yaml.load` ou `shell=True`** em
  qualquer um dos seis repositórios.
- **Nenhum segredo, log, cache, banco ou artefato de build versionado.**
- **`next=` validado contra open redirect nos quatro apps**, cada um com
  tratamento explícito de percent-encoding aninhado e barra invertida.
- **Comparação de token sempre com `hmac.compare_digest`** (CRV e Conforto).
- **Compose endurecido de forma consistente nos quatro:** `read_only`,
  `cap_drop`, `no-new-privileges`, `mem_limit`, `user` não-root, porta do
  Postgres publicada só em `127.0.0.1`, segredos por arquivo, healthcheck.
- **CI equivalente nos seis repositórios**, com action fixada por SHA,
  `pip-audit` e varredura de imagem.
- **Eager loading bem usado** — 14 módulos do Django com
  `select_related`/`prefetch_related`, 5 do CRV com `joinedload`/`selectinload`.
  Nenhum N+1 óbvio em caminho quente.

Os achados abaixo são, portanto, refinamentos. Nenhum deles é uma emergência.
O de maior consequência é o [S1](#s1--cookie-lembrar-me-de-365-dias-em-dois-apps),
e ele é uma configuração de uma linha.

## 3. Legenda

- **Impacto** — Alto / Médio / Baixo: o quanto muda na prática.
- **Esforço** — P (até uma hora) / M (meio dia) / G (um dia ou mais).
- **Risco** — Baixo / Médio / Alto: chance de a mudança quebrar algo.

Sua instrução de não deixar os sistemas mais complicados é tratada como
recomendação, não como limite: onde uma proposta aumenta a sofisticação, o
custo está escrito e a decisão é sua.

### Revalidação de 28/08 — documentação não é lei

Depois da primeira versão deste relatório você observou, com razão, que pode
ter autorizado ou escrito coisas que impõem limitação sem essa intenção, e
liberou a implementação de soluções ótimas ainda que algum documento as
restrinja.

A auditoria foi reexaminada sob essa premissa. Todo ponto em que a
recomendação original deferia a um comentário no código, a um docstring ou aos
critérios de entrada do `SharedAuth/AGENTS.md` foi rejulgado pelo mérito.

**Resultado:** seis itens novos ([S8](#s8--fechar-img-src-data-nos-dois-apps),
[S9](#s9--conforto_testing-desliga-o-rate-limit-em-qualquer-ambiente),
[A7](#a7--ler_flag-leitura-de-booleano-de-ambiente),
[A8](#a8--montar_url_postgres-em-python-puro),
[A9](#a9--requer_papel-o-decorator-de-admin-escrito-duas-vezes),
[H9](#h9--comentário-obsoleto-no-confortotermico)) e uma recomendação
reforçada ([U1](#u1--estado-de-interface-na-barra-do-crv)). Cinco conclusões
foram reexaminadas e **mantidas**, porque se apoiavam em mérito técnico e não
em documentação — estão listadas em
[§12](#12-o-que-a-revalidação-reexaminou-e-manteve).

---

## 4. Segurança

### S1 — Cookie "lembrar-me" de 365 dias em dois apps

**Impacto: Alto · Esforço: P · Risco: Baixo**

ControleRendaVariavel ([auth.py:56](ControleRendaVariavel/app/routes/auth.py))
e MegaSena ([auth.py:74](MegaSena/app/web/auth.py)) chamam
`login_user(user, remember=True)` incondicionalmente — não é uma caixa que a
pessoa marca, é o comportamento padrão de todo login.

O `REMEMBER_COOKIE_DURATION` do Flask-Login vale **365 dias** por padrão, e
nenhum dos dois o redefine. O `sharedauth.session.configurar_sessao` fixa
`REMEMBER_COOKIE_HTTPONLY`, `SAMESITE` e `SECURE`
([session.py:37-39](SharedAuth/sharedauth/session.py)), mas não a duração.

Consequência concreta: nos dois aplicativos que guardam dados financeiros
pessoais, um cookie de autenticação copiado de um navegador continua valendo
por um ano, e não existe expiração por inatividade. Para comparação:
ConfortoTermico usa 12 horas
([app_factory.py:260](ConfortoTermico/app/app_factory.py)) e ControleBancario
usa 24 horas (`SESSION_COOKIE_AGE`).

**Recomendação:** acrescentar `duracao_lembrete_horas` a
`sharedauth.session.configurar_sessao` (ver [A2](#a2--configurar_sessao-decide-a-duração-do-lembrar-me))
e adotá-la nos dois apps. Sugestão de valor: 12 horas no CRV (alinha com o
Conforto) e 24 horas no MegaSena — ou o que você preferir; o ponto é existir
um teto.

### S2 — Sem expiração de sessão por inatividade nos mesmos dois apps

**Impacto: Médio · Esforço: P · Risco: Baixo**

Consequência do mesmo desenho: CRV e MegaSena não definem
`permanent_session_lifetime` (o parâmetro `duracao_horas` de
`configurar_sessao` fica em `None`), então o cookie de sessão vive enquanto o
navegador estiver aberto e o de "lembrar-me" cobre o resto. Uma aba esquecida
aberta permanece autenticada indefinidamente.

**Recomendação:** resolver junto com S1, passando `duracao_horas` na mesma
chamada. É a mesma linha de código.

### S3 — BackupRestore aceita POST de qualquer origem

**Impacto: Médio · Esforço: P · Risco: Baixo**

[`web.py`](BackupRestore/web.py) tem três rotas POST — `/projeto/<slug>/backup`
(linha 212), `/artefato/<id>/fixar` (223) e `/restaurar/<id>` (266) — sem
verificação de CSRF, sem login e sem checagem de `Origin`. É deliberado e está
documentado no cabeçalho do arquivo ("Escuta só em 127.0.0.1. Sem login, como o
resto do escopo").

O que a decisão de escutar em loopback **não** cobre: enquanto `web.py` estiver
rodando, qualquer página aberta no seu navegador pode enviar um POST de
formulário para `http://127.0.0.1:5401/...` sem precisar ler a resposta. Isso
dispara backups em série ou alterna a marca de "fixado" em artefatos.

O raio de explosão é pequeno e verificado: a restauração só aceita o contêiner
sandbox e o banco `ensaio_<slug>` fixos, sem escolha pela interface
([restaurar.py](BackupRestore/restaurar.py)). Nada de produção é tocado.

**Recomendação:** um `before_request` de ~10 linhas recusando POST cujo
`Origin` não seja `http://127.0.0.1:5401`. Não vale trazer Flask-WTF para cá —
exigiria `SECRET_KEY` num utilitário que hoje não tem nenhuma.

### S4 — `_load_user` do CRV derruba a requisição com id não numérico

**Impacto: Baixo · Esforço: P · Risco: Baixo**

[`app/__init__.py:81`](ControleRendaVariavel/app/__init__.py) faz
`db.session.get(User, int(user_id))` sem guarda. Um `user_id` não numérico
levanta `ValueError` e vira 500. O MegaSena tem exatamente a mesma função com
`try/except (TypeError, ValueError)`
([`app/__init__.py:202-206`](MegaSena/app/__init__.py)).

Não é uma vulnerabilidade: o cookie de sessão é assinado, então não há como um
terceiro colocar lixo ali. É robustez, e é uma linha de convergência com o
irmão.

### S5 — ConfortoTermico não usa o limiter compartilhado

**Impacto: Médio · Esforço: P · Risco: Médio**

Os outros dois apps Flask chamam `sharedauth.ratelimit.iniciar_limiter`. O
ConfortoTermico monta o seu próprio
([app_factory.py:84-93](ConfortoTermico/app/app_factory.py)) porque precisa de
coisas que a função compartilhada não oferece: `default_limits`, `storage_uri`,
`strategy` e `enabled`.

O efeito não é teórico. O comentário longo em `app_factory.py:265-290` registra
que este app já perdeu proteção real por divergir do padrão dos irmãos, e o
histórico do arquivo mostra três regressões da mesma família (limite decorado e
nunca aplicado). Cada ponto onde um app sai do contrato comum é um lugar onde a
correção feita nos outros não chega.

**Recomendação:** ampliar `iniciar_limiter` (ver [A3](#a3--iniciar_limiter-aceita-a-política-do-consumidor))
e trazer o Conforto de volta. O risco é Médio porque mexer em rate limit de uma
app com polling de 3 segundos exige validar em produção antes de considerar
concluído.

### S6 — Contador de rate limit é por processo, com dois workers

**Impacto: Médio · Esforço: M · Risco: Médio**

CRV e MegaSena rodam gunicorn com `--workers 2` e armazenamento
`memory://`. O contador do Flask-Limiter é por processo: um limite de "10 por
minuto" no login vale, na prática, até 20 por minuto, e as contagens não são
coerentes entre os workers.

Isto **já está documentado e mitigado** para o login: o `AGENTS.md` do
SharedAuth diz explicitamente que `memory://` não é proteção completa de
produção, e o nginx do VPS limita `POST /login` na borda (confirmado no
`README.md` do `_manutencao`).

O que a mitigação de borda **não** cobre são os outros limites: o polling do
heartbeat do CRV (`120 per minute`), as rotas do agente coletor e os limites
por rota do Conforto. Nenhum deles é crítico.

**Recomendação:** registrar como aceito e não agir agora. Um Redis só para isto
é exatamente o tipo de sofisticação que os sistemas não pedem. Reavaliar se um
dia a topologia mudar.

### S7 — CRV e MegaSena não têm trilha de auditoria

**Impacto: Médio · Esforço: G · Risco: Baixo**

ConfortoTermico tem [`app/audit_log.py`](ConfortoTermico/app/audit_log.py) e o
ControleBancario tem tabela `audit_log` com registro em dez módulos. CRV e
MegaSena não têm nada: quem entrou, quem mudou uma posição, quem desativou um
usuário — não fica registrado em lugar nenhum.

Isto é fronteira: pode ser lido como funcionalidade nova, e você disse que não
há prioridade para funcionalidades novas. Fica listado porque é a única
assimetria de segurança relevante entre os quatro, e porque o CRV é
multiusuário com dado financeiro pessoal.

**Recomendação:** decisão sua. Se aceitar, a persistência fica em cada app (a
carta do SharedAuth proíbe persistência na biblioteca) e só o contrato de
sanitização é compartilhado — ver [A5](#a5--sanitizar_log-anti-injeção-em-log).

*Nota da revalidação:* este item continua adiado, mas não por causa da
documentação — e sim porque você disse que não há prioridade para
funcionalidade nova, e uma trilha de auditoria é funcionalidade nova.

**Decisão de 28/08 — MegaSena está fora, definitivamente.** O mantenedor
determinou que o MegaSena não precisa de rastreabilidade: é um sistema simples
e as ações não precisam ser auditáveis. Não é adiamento, é recusa; não
reabrir.

O item permanece aberto **somente para o ControleRendaVariavel**, onde o
argumento era mais forte (multiusuário, dado financeiro pessoal). Se um dia
for aceito só lá, [A5](#a5--sanitizar_log-anti-injeção-em-log) passaria a ter
dois consumidores (Conforto e CRV) e valeria a pena.

### S8 — Fechar `img-src data:` nos dois apps

**Impacto: Médio · Esforço: P · Risco: Baixo · (achado da revalidação)**

MegaSena ([core/security.py:29](MegaSena/app/core/security.py)) e
ControleBancario ([core/security.py:31](ControleBancario/core/security.py))
abrem a CSP com `montar_csp(imagens_data_uri=True)`. Os dois documentam a
exceção com cuidado exemplar, e o motivo é o mesmo nos dois: o favicon é um
SVG embutido direto no `<link rel="icon">`.

- [MegaSena base.html:7](MegaSena/app/templates/base.html) — círculo verde em SVG
- [ControleBancario base.html:9](ControleBancario/templates/base.html) — quadrado azul com "₿"

Verifiquei que **é a única ocorrência de data URI em cada projeto**. (Os
`data:` que aparecem em `dashboard.js` do ControleBancario são chaves de
objeto do Chart.js, não URIs.)

Era exatamente o tipo de exceção que a documentação justificava tão bem que
parava a discussão. Pelo mérito: gravar cada favicon como `favicon.svg`
estático e apontar o `<link>` para ele elimina a necessidade da folga, e a CSP
dos dois apps passa a ser a fechada — `img-src 'self'`, igual à do
ConfortoTermico e à do CRV.

**Recomendação:** fechar. O ganho é pequeno mas real, e o custo é dois
arquivos e duas linhas. Depois disso, `imagens_data_uri` fica sem nenhum
consumidor e o parâmetro pode ser mantido na biblioteca sem uso ou removido
numa versão futura — sugiro manter, é uma folga barata de existir.

### S9 — `CONFORTO_TESTING` desliga o rate limit em qualquer ambiente

**Impacto: Médio · Esforço: P · Risco: Baixo · (achado da revalidação)**

[app_factory.py:208](ConfortoTermico/app/app_factory.py) faz
`app.testing = _ler_bool_env("CONFORTO_TESTING", False)`. Definir essa
variável no ambiente tem dois efeitos que vão além de "marcar que é teste":

1. **desliga o rate limiter inteiro** — `_criar_limiter` usa
   `enabled=not app.testing` ([app_factory.py:92](ConfortoTermico/app/app_factory.py)),
   então a proteção de força bruta do login e todos os limites por rota somem;
2. **permite subir sem `SECRET_KEY`** — `_ambiente_permite_gerar_chave`
   aceita `CONFORTO_TESTING` como sinal de "não é produção"
   ([auth.py:178](ConfortoTermico/app/auth.py)), e a aplicação gera uma chave
   efêmera em vez de falhar.

O comentário no código diz que a variável "não é definida em produção/Docker",
e conferi que de fato não está em nenhum Compose. Mas é precisamente uma
garantia por documentação: nada no código impede que ela seja definida, e o
efeito de defini-la por engano é silencioso — o app sobe normalmente, sem
rate limit e possivelmente com chave descartável.

**Recomendação:** recusar a combinação explicitamente. Se `CONFORTO_TESTING`
estiver ligada, exigir também `CONFORTO_DEVELOPMENT` e host de loopback — é a
mesma trava que `_validar_debug` já aplica ao `CONFORTO_DEBUG`
([app_factory.py:171-180](ConfortoTermico/app/app_factory.py)), reaproveitada.
O padrão já existe no arquivo; falta aplicá-lo ao segundo interruptor.

---

## 5. Parâmetros na barra de endereço

Você pediu classificação caso a caso. O inventário abaixo é completo: todo
parâmetro lido do query string nos quatro apps, com o veredito.

### Como cada app chega a ter parâmetro na barra

| App | Mecanismo | O que de fato aparece na barra |
|---|---|---|
| ConfortoTermico | Nenhum. Sem HTMX, sem `pushState`. Os parâmetros só existem em chamadas `/api/` feitas por JS. | **Nada.** A barra fica limpa. |
| MegaSena | `hx-push-url="true"` em duas telas ([contests/_results.html](MegaSena/app/templates/contests/_results.html), [dashboard/_content.html](MegaSena/app/templates/dashboard/_content.html)) | Só filtros de verdade. |
| ControleRendaVariavel | `hx-push-url="true"` em **8 templates** | Filtros **e** estado de interface. |
| ControleBancario | `history.pushState` na navegação AJAX própria ([application.js:584-587, 672](ControleBancario/static/js/core/application.js)) | Filtros **e** estado de interface. |

### Inventário classificado

**Legenda da coluna Veredito:** `filtro` = seleção de dados, faz sentido ser
compartilhável e sobreviver ao F5 — manter; `identificador` = aponta um
registro, equivalente a um caminho — manter; `navegação` = mecânica de login —
manter; `estado de UI` = só descreve como a tela está desenhada — candidato a
sair.

#### ControleRendaVariavel

| Parâmetro | Onde | O que carrega | Veredito |
|---|---|---|---|
| `expanded` | [positions.py:133](ControleRendaVariavel/app/routes/positions.py), [options.py:113](ControleRendaVariavel/app/routes/options.py) | ids das linhas com extrato aberto | **estado de UI** |
| `expanded_tickers` | [dividends.py:94](ControleRendaVariavel/app/routes/dividends.py) | ids de ativos abertos no drill-down | **estado de UI** |
| `expanded_years` | [dividends.py:95](ControleRendaVariavel/app/routes/dividends.py) | pares "ano-moeda" abertos | **estado de UI** |
| `group_by_broker` | [positions.py:164](ControleRendaVariavel/app/routes/positions.py) | agrupar a grade por corretora | **estado de UI** |
| `broker` | dividends.py:93, helpers.py:84 | filtro por corretora | filtro |
| `portfolio_id` | helpers.py:80, tables.py:278 | filtro por carteira | filtro |
| `portfolio` | performance.py:52 | qual carteira no relatório | filtro |
| `period` | performance.py:51 | janela do relatório | filtro |
| `return_days` | positions.py:166 | janela de retorno | filtro |
| `status` | transactions.py:201 | filtro de situação | filtro |
| `benchmark_ticker_id` | performance.py:122, quotes.py:143 | referência de comparação | filtro |
| `ticker_id` | quotes.py:142 | ativo consultado | identificador |
| `next` | auth.py:58 | destino pós-login | navegação |

#### ControleBancario

| Parâmetro | Onde | O que carrega | Veredito |
|---|---|---|---|
| `filters_open` | [reports/views.py:212](ControleBancario/reports/views.py) | painel de filtros aberto ou fechado | **estado de UI** |
| `show_descriptions` | reports/views.py:191 | mostrar coluna de descrição | **estado de UI** |
| `show_entries` | transactions/views.py:392 | mostrar lançamentos | **estado de UI** |
| `detail`, `layout` | core/views.py | recorte visual da tela | **estado de UI** |
| `mode` | dashboard/views.py:67, reports/views.py (4×) | projetado / realizado / todos | filtro |
| `filter_type`, `filter_status`, `filter_year`, `filter_month`, `filter_owner_id`, `filter_institution_id`, `filter_account_id` | banking/, core/views.py | filtros do painel | filtro |
| `start`, `end`, `start_date`, `end_date`, `start_month`, `end_month`, `month`, `year`, `period`, `reference_month` | reports/, transactions/ | recorte temporal | filtro |
| `page`, `page_size` | core/views.py | paginação | filtro |
| `line_id`, `attachment_id`, `operation_id`, `entity_id`, `account_id`, `owner_id`, `institution_id`, `user_id` | bank_statements/, core/, banking/ | registro alvo | identificador |
| `table_name`, `entity_name`, `user_name`, `created_on`, `operation_type`, `action`, `status` | core/views.py (administração) | seleção nas telas de manutenção | filtro |
| `next` | accounts/views.py:97 | destino pós-login | navegação |

#### MegaSena

| Parâmetro | Onde | O que carrega | Veredito |
|---|---|---|---|
| `page`, `winners_only`, `consecutive_count`, `even_count` | [contests.py:21-24](MegaSena/app/web/contests.py) | filtros e paginação de concursos | filtro |
| `count` | dashboard.py:43 | quantos itens no painel | filtro |
| `quantity`, `amount`, `closure_numbers`, `target_percentage` e os filtros de geração | bets.py:130-226, 451 | estado do formulário de geração | filtro — **e não vai para a barra**: essas rotas são fragmentos HTMX sem `hx-push-url` |
| `next` | auth.py:30 | destino pós-login | navegação |

#### ConfortoTermico

| Parâmetro | Onde | O que carrega | Veredito |
|---|---|---|---|
| `indice`, `status`, `zona_id`, `valor_referencia`, `data_inicio`, `data_fim` | [rotas_comuns.py:18-50, 154-158](ConfortoTermico/app/rotas_comuns.py) | filtros de consulta em `/api/` | filtro — nunca aparece na barra |
| `execucao_id` | dados_entrada_rotas.py:76 | execução consultada | identificador |

Vale registrar o cuidado que já existe aqui: cada parâmetro passa por
`_parametro_inteiro`/`_parametro_float`/`_parametro_data`, que devolvem 400 com
mensagem específica em vez de aceitar lixo. É o tratamento mais rigoroso dos
quatro.

### U1 — Estado de interface na barra do CRV

**⚠️ CORRIGIDO EM 28/08 — a afirmação central deste achado estava errada.**

**O que eu afirmei:** que `expanded`, `expanded_tickers`, `expanded_years` e
`group_by_broker` apareciam na barra de endereços por causa do
`hx-push-url="true"` em oito templates, produzindo URLs como
`?broker=XP&expanded_tickers=12,47&expanded_years=2025-BRL`.

**O que é verdade:** os três primeiros **nunca chegam à barra**. Verificado ao
começar a implementação:

- os botões de `+` usam `hx-get` e **não** têm `hx-push-url` próprio
  ([portfolio_results.html:33](ControleRendaVariavel/app/templates/partials/portfolio_results.html),
  [dividends_results.html:38](ControleRendaVariavel/app/templates/partials/dividends_results.html));
- o htmx resolve `hx-push-url` por **ancestral**, e esses botões não são
  descendentes do formulário de filtro: em
  [base.html:222-231](ControleRendaVariavel/app/templates/base.html) o
  `header_controls` (onde vive o formulário) e o `content` (onde vive a tabela)
  são irmãos;
- as URLs de toggle são consumidas **exclusivamente** em `hx-get`, nunca em
  `href` — confirmado por busca em todos os templates e no JS.

Ou seja: esses parâmetros viajam apenas na requisição do fragmento. A barra
nunca os vê, e um F5 não os preserva — o que o docstring de
[dividends.py:69-77](ControleRendaVariavel/app/routes/dividends.py) sempre
disse, corretamente: o estado está lá para sobreviver à **troca do fragmento**,
não ao recarregamento da página.

**O que de fato aparece na barra** é exatamente o conjunto de campos dentro de
cada formulário que empurra a URL:

| Tela | Campos que vão para a barra |
|---|---|
| `/` (carteira) | `portfolio_id`, `broker`, `group_by_broker`, `return_days` |
| `/transactions` | `portfolio_id`, `broker`, `status` |
| `/performance` | `portfolio_id`, `portfolio`, `broker`, `period`, `benchmark_ticker_id` |
| `/dividends` | `broker` |
| `/options` | `portfolio_id`, `broker` |
| `/quotes` | `ticker_id`, `benchmark_ticker_id` |

São filtros — seleção de dados, não desenho de tela. É o caso em que a URL
paga o que custa: F5, favorito e link continuam funcionando.

**O que foi feito (Fase 4):** trocar `hx-push-url` por `hx-replace-url` nas
oito ocorrências. O gatilho desses formulários é `change`, então cada mexida
num select virava uma entrada de histórico e o botão "voltar" desfazia filtro
por filtro em vez de sair da tela. Com `replace`, a URL continua refletindo o
filtro e o histórico volta a ter uma entrada por tela.

**O que NÃO foi feito, e por quê:** esvaziar a barra de vez exigiria mover os
filtros para a sessão. Isso custa o que a URL hoje entrega de graça — link
compartilhável, favorito, F5 — e faz duas abas da mesma tela disputarem o mesmo
estado. Com a premissa corrigida, esse passo deixou de ser "tirar sujeira de
interface da URL" e passou a ser "tirar filtros da URL", que é outra decisão.
**Fica em aberto para o mantenedor.**

`group_by_broker` é o único campo pushado que é mais desenho que filtro. Ficou
onde está: ele mora no formulário junto dos filtros, e "carteira agrupada por
corretora" é um estado que faz sentido guardar num favorito.

### U2 — Estado de interface na barra do ControleBancario

**Impacto: Médio · Esforço: M · Risco: Médio**

Mesmo problema, mecanismo diferente: a navegação AJAX própria
([application.js:584-587](ControleBancario/static/js/core/application.js))
empurra a URL da resposta para o histórico a cada navegação, incluindo
`filters_open=1&show_descriptions=1`.

Aqui há um caminho melhor que remendar o JS: esses parâmetros desaparecem
naturalmente se o item [H1](#h1--dois-mecanismos-de-navegação-convivendo-no-controlebancario)
for aceito, porque o controle sobre o que vai para a barra passa a ser um
atributo por elemento em vez de uma regra global no `application.js`.

**Recomendação:** decidir U2 junto com H1, não separado.

### U3 — MegaSena e ConfortoTermico: nada a fazer

Registrado para fechar o inventário. A barra do MegaSena mostra só filtros
legítimos de concursos; a do ConfortoTermico não mostra nada. O estado do
formulário de geração de apostas do MegaSena, que seria o candidato natural a
poluir, viaja em requisições de fragmento que não empurram URL.

---

## 6. Evolução do SharedAuth

Todas as propostas abaixo foram testadas contra os quatro critérios de entrada
da carta em [`SharedAuth/AGENTS.md`](SharedAuth/AGENTS.md): necessidade
concreta em pelo menos dois consumidores; contrato coeso e testável
isoladamente; núcleo neutro de framework ou integração em extra explícito; sem
dependência de banco ou de domínio.

### A1 — `sharedauth.secrets`: segredo por arquivo

**Impacto: Alto · Esforço: M · Risco: Baixo · Critérios: 4/4**

Existem hoje **quatro implementações independentes** da mesma ideia — ler um
segredo de um arquivo montado pelo Compose, recusando ausente e vazio:

| App | Função | Arquivo |
|---|---|---|
| ConfortoTermico | `read_compose_secret` | [app/secret_files.py](ConfortoTermico/app/secret_files.py) |
| ControleRendaVariavel | `read_secret_file`, `environment_value`, `project_secret_value` | [app/secret_files.py](ControleRendaVariavel/app/secret_files.py) |
| MegaSena | `_ler_segredo_por_arquivo` | [app/\_\_init\_\_.py:60](MegaSena/app/__init__.py) |
| ControleBancario | `_read_required_secret` | [financeiro/settings.py:16](ControleBancario/financeiro/settings.py) |

Dois deles até compartilham o nome de arquivo (`secret_files.py`) e divergiram
mesmo assim. As diferenças são reais e cada uma tem motivo:

- o Conforto **exige** que o caminho seja exatamente `/run/secrets/<nome>` —
  a checagem mais rígida das quatro, e a única que impede `*_FILE` de virar
  seletor arbitrário de arquivo;
- o CRV aceita caminho livre porque o agente RTD no Windows lê de `.secrets/`
  fora do Docker;
- o Django tem o interruptor `REQUIRE_FILE_SECRETS` para separar Compose de
  execução local;
- o MegaSena aceita variável direta como compatibilidade com execução manual.

Este é Python puro, sem banco, sem domínio, testável sozinho, com quatro
consumidores. É o candidato mais forte do relatório.

**Recomendação:** um módulo com uma função e parâmetros explícitos —
`ler_segredo(nome, *, diretorio_esperado=None, aceitar_variavel=False)` — onde
cada app declara sua política em vez de reimplementá-la. A checagem estrita do
Conforto vira o padrão; quem precisa de folga pede por nome.

### A2 — `configurar_sessao` decide a duração do "lembrar-me"

**Impacto: Alto · Esforço: P · Risco: Baixo · Critérios: 4/4**

O módulo [`session.py`](SharedAuth/sharedauth/session.py) já fixa
`REMEMBER_COOKIE_HTTPONLY`, `SAMESITE` e `SECURE`. Falta o único que decide por
quanto tempo o cookie vale, e é justamente o que está em 365 dias
([S1](#s1--cookie-lembrar-me-de-365-dias-em-dois-apps)).

Acrescentar `duracao_lembrete_horas` é dentro do contrato existente do módulo,
não uma responsabilidade nova. Resolve S1 e S2 na fonte, para os dois
consumidores de uma vez.

### A3 — `iniciar_limiter` aceita a política do consumidor

**Impacto: Médio · Esforço: P · Risco: Baixo · Critérios: 4/4**

Hoje [`ratelimit.py`](SharedAuth/sharedauth/ratelimit.py) só faz
`Limiter(key_func=get_remote_address)` + `init_app`. O ConfortoTermico precisa
de `default_limits`, `storage_uri`, `strategy` e `enabled`, e por isso monta o
seu próprio ([S5](#s5--confortotermico-não-usa-o-limiter-compartilhado)).

Passar esses quatro como parâmetros opcionais mantém o padrão fechado para
quem não pede nada e traz o terceiro app de volta ao contrato comum. A carta
continua respeitada: a biblioteca não decide backend operacional, só deixa o
consumidor declarar o dele.

### A4 — `aplicar_limite`: encapsular a reatribuição de `view_functions`

**Impacto: Alto · Esforço: P · Risco: Baixo · Critérios: 4/4**

Este padrão aparece em **três apps, seis vezes**:

```python
app.view_functions[endpoint] = limiter.limit(...)(app.view_functions[endpoint])
```

- ConfortoTermico: [app_factory.py:369, 393, 419](ConfortoTermico/app/app_factory.py)
- MegaSena: [\_\_init\_\_.py:220](MegaSena/app/__init__.py)
- ControleRendaVariavel: [\_\_init\_\_.py:210, 217](ControleRendaVariavel/app/__init__.py)

E é a armadilha mais cara do conjunto. `RouteLimit.__call__` devolve uma função
**nova**; descartar o retorno deixa o limite decorado e nunca aplicado.
Os comentários no código registram que isso já aconteceu de verdade **três
vezes**: no login do MegaSena, no polling do dashboard do Conforto (rodando com
20/min em vez de 60/min, provavelmente gerando 429 em produção) e na isenção do
health do coletor. O MegaSena inclusive tem um teste dedicado
([tests/test_rate_limit.py](MegaSena/tests/test_rate_limit.py)) só para guardar
essa reatribuição.

Uma função `aplicar_limite(app, endpoint, limite, **kwargs)` e uma
`isentar_limite(app, endpoint)` tornam o erro impossível de cometer, e são
testáveis isoladamente. Três consumidores, seis pontos de uso, três regressões
históricas — passa nos critérios com folga.

**Observação verificada:** o mesmo cuidado **não** se aplica a
`csrf.exempt(app.view_functions[...])` em
[CRV `__init__.py:224`](ControleRendaVariavel/app/__init__.py). O
`CSRFProtect.exempt` do Flask-WTF registra a view por referência e devolve a
mesma função; descartar o retorno ali está correto. Nada a mudar.

### A5 — `sanitizar_log`: anti-injeção em log

**Impacto: Baixo · Esforço: P · Risco: Baixo · Critérios: 3/4**

`sanitizar_log` existe só no ConfortoTermico
([auth.py:124](ConfortoTermico/app/auth.py)). É Python puro, coeso e testável.

Falha no critério 1 hoje: só há **um** consumidor concreto. Passa a fazer
sentido se [S7](#s7--crv-e-megasena-não-têm-trilha-de-auditoria) for aceito,
porque aí nascem dois consumidores novos.

**Recomendação:** não mover agora. Reavaliar se S7 for aceito.

### A7 — `ler_flag`: leitura de booleano de ambiente

**Impacto: Médio · Esforço: P · Risco: Baixo · (achado da revalidação)**

Três implementações da mesma leitura, com comportamentos diferentes:

| App | Função | Valor inválido |
|---|---|---|
| MegaSena | `_environment_flag` ([\_\_init\_\_.py:47](MegaSena/app/__init__.py)) | levanta `RuntimeError` |
| ConfortoTermico | `_ler_bool_env` / `_coagir_bool` ([app_factory.py:117-141](ConfortoTermico/app/app_factory.py)) | usa o padrão em silêncio |
| ControleBancario | comparação direta com `'true'` (settings.py, 4×) | usa o padrão em silêncio |

Na primeira versão eu recusei este item citando a carta do SharedAuth, que
rejeita "a tentativa de uniformizar regras diferentes" como critério de
entrada. Pelo mérito, a leitura é outra: as regras não precisam ser
uniformizadas, precisam ser **parametrizadas**.

Uma função `ler_flag(nome, *, padrao=False, estrito=True)` no núcleo em Python
puro deixa cada consumidor declarar o que faz com valor inválido, em vez de
reescrever o parser. O MegaSena passa `estrito=True`, os outros dois
`estrito=False`, e todos param de ter a sua cópia.

O ganho real não é a linha economizada: é que o comportamento estrito — falhar
alto num `CONFORTO_TESTING=sim, por favor` em vez de silenciosamente tratar
como `False` — passa a estar disponível para quem quiser, num arquivo só, com
teste. Isso conversa diretamente com [S9](#s9--conforto_testing-desliga-o-rate-limit-em-qualquer-ambiente).

### A8 — `montar_url_postgres` em Python puro

**Impacto: Médio · Esforço: P · Risco: Baixo · (achado da revalidação)**

Três formas de montar a mesma string de conexão a partir de host, porta,
usuário, banco e senha:

- CRV: `build_postgres_url` ([secret_files.py](ControleRendaVariavel/app/secret_files.py)) — Python puro, com `urllib.parse.quote`
- MegaSena: `URL.create` do SQLAlchemy ([\_\_init\_\_.py:96](MegaSena/app/__init__.py))
- ConfortoTermico: `URL.create` do SQLAlchemy ([db_backend.py:47](ConfortoTermico/app/db_backend.py))

Recusei este item na primeira versão com o argumento de que traria SQLAlchemy
para um núcleo que hoje tem `dependencies = []`. **O argumento não se
sustenta:** o CRV já faz exatamente isso sem SQLAlchemy nenhum, com
`quote(..., safe='')`. A versão em Python puro serve os três consumidores sem
acrescentar dependência alguma.

A outra objeção — a carta proíbe "persistência" na biblioteca — também não se
aplica sob exame: montar uma string de conexão não é persistir nada. Não há
sessão, engine, modelo nem migração envolvidos; é formatação de texto com
escape correto.

**Cuidado obrigatório na implementação:** o escape de senha não é
cosmético. Uma senha com `@`, `/` ou `:` sem `quote(..., safe='')` produz uma
URL que aponta para outro host, ou que falha de um jeito que expõe parte do
segredo na mensagem de erro. O teste do contrato precisa cobrir esses três
caracteres.

### A9 — `requer_papel`: o decorator de admin escrito duas vezes

**Impacto: Baixo · Esforço: P · Risco: Baixo · (achado da revalidação)**

`requer_admin` no CRV
([authorization.py:21](ControleRendaVariavel/app/authorization.py)) e
`admin_required` no MegaSena
([web/users.py:29](MegaSena/app/web/users.py)) são a mesma verificação binária
escrita duas vezes: decorator de view, `abort(403)`, com a mesma justificativa
(não redirecionar para o login quem já está autenticado).

*Correção de 28/08:* a primeira versão citava `_require_admin` em
`accounts/service.py:146` como o par do MegaSena. Está errado — aquela é uma
guarda de **camada de serviço**, que recebe o ator explicitamente e levanta
`UserManagementError`. Ela é legitimamente diferente e **não** entra neste
item; fica onde está. O par correto é o decorator de view em `web/users.py`.

Na primeira versão isso foi absorvido pelo item genérico "autorização está
fora da carta". Separando o caso concreto do princípio: o binário
admin/não-admin é um contrato coeso, testável, sem banco e com dois
consumidores — passa nos critérios sem precisar de nenhuma dispensa.

`sharedauth.access.requer_papel(verificar_papel)` recebe do consumidor a
função que decide, e a biblioteca só cuida da mecânica de recusa (403 em HTML,
JSON em API, `HX-Redirect` em HTMX — que ela já sabe fazer em `requer_login`).
Nenhum modelo de papel entra na biblioteca.

### A6 — O que eu não moveria para o SharedAuth

Registrado para você poder discordar com o motivo à vista. Esta lista encolheu
na revalidação: `montar_url_postgres` virou [A8](#a8--montar_url_postgres-em-python-puro)
e o parsing de booleano virou [A7](#a7--ler_flag-leitura-de-booleano-de-ambiente).
Sobrou um item:

- **Autorização rica.** ConfortoTermico tem perfis com áreas por endpoint;
  ControleBancario tem permissões por proprietário. São modelos genuinamente
  diferentes, não cópias divergentes de um só — o do Conforto decide por área
  de tela, o do Django decide por titular de conta, e nenhum dos dois é caso
  particular do outro. Unificá-los produziria uma abstração que ninguém pediu
  e que teria de ser desfeita na primeira regra nova.

  **Esta recusa é de mérito, não de documentação.** Mantida depois da
  revalidação. O pedaço que *é* comum foi extraído em
  [A9](#a9--requer_papel-o-decorator-de-admin-escrito-duas-vezes).

---

## 7. Higiene e simplificação

### H1 — Dois mecanismos de navegação convivendo no ControleBancario

**Impacto: Alto · Esforço: G · Risco: Médio**

O projeto tem HTMX instalado (`django-htmx` nas dependências,
`htmx.min.js` versionado, `HtmxMiddleware` no MIDDLEWARE) e o usa em **18**
atributos de template. Ao lado disso, mantém
[`static/js/core/application.js`](ControleBancario/static/js/core/application.js)
com **969 linhas** de navegação AJAX própria: `fetch`, troca de `#appMain`,
`pushState`, sincronização de cabeçalho, de sidebar e de mensagens flash,
re-execução de scripts, controle de scroll e aborto de requisição concorrente.

É a reimplementação manual do que o HTMX já faz — e é a origem do
[U2](#u2--estado-de-interface-na-barra-do-controlebancario).

O contraste dentro do próprio conjunto mede o custo:

| App | HTMX (atributos) | JS próprio (linhas, sem vendor) |
|---|---|---|
| MegaSena | 34 | **97** |
| ControleRendaVariavel | 71 | 713 (dos quais 503 são gráficos) |
| ControleBancario | 18 | **1.752** (969 só de navegação) |
| ConfortoTermico | 0 | **4.928** |

**Recomendação:** migrar a navegação para HTMX e apagar `application.js`. É o
maior ganho de higiene por linha removida do conjunto, e resolve U2 de graça.
Risco Médio e esforço G porque toca toda navegação de um app de 14 mil linhas —
faria em fases, por seção, com a possibilidade de parar no meio.

### H2 — 4.928 linhas de JavaScript próprio no ConfortoTermico

**Impacto: Alto · Esforço: G+ · Risco: Alto**

O Conforto não tem HTMX. Toda a interface — dashboard de zonas, histórico,
entrada de dados, cadastro, operação, análises — é JavaScript escrito à mão
com `fetch` e manipulação de DOM, em oito arquivos de 372 a 912 linhas.

É o maior débito estrutural do conjunto em volume. Também é o mais caro e mais
arriscado de mexer: é a interface de um sistema que controla equipamento, com
polling de 3 segundos e uma malha de controle do outro lado.

**Recomendação:** **não fazer agora**, e não fazer de uma vez nunca. Fica
registrado como direção. Se um dia atacar, o caminho é uma tela por vez,
começando pela mais simples (análises), e só depois de H1 ter provado o padrão
no ControleBancario.

### H3 — Doze arquivos com BOM UTF-8

**Impacto: Baixo · Esforço: P · Risco: Baixo**

Onze no CRV, um no Conforto:

```
ConfortoTermico/tests/test_authorization.py
ControleRendaVariavel/app/__init__.py
ControleRendaVariavel/app/collector_settings.py
ControleRendaVariavel/app/models.py
ControleRendaVariavel/app/routes/settings.py
ControleRendaVariavel/app/routes/tables.py
ControleRendaVariavel/app/routes/transactions.py
ControleRendaVariavel/app/static/app.css
ControleRendaVariavel/app/templates/base.html
ControleRendaVariavel/app/templates/partials/portfolios_results.html
ControleRendaVariavel/app/templates/partials/transactions_results.html
ControleRendaVariavel/app/templates/settings.html
```

O BOM em `.py` é tolerado pelo Python, mas polui diffs, atrapalha ferramentas
que leem o primeiro byte e não tem nenhuma razão de existir. Em `.css` e
`.html` é ruído puro.

**Recomendação:** remover os doze. Confirmar que o `.gitattributes` do CRV não
os traz de volta.

### H4 — Script órfão no ConfortoTermico

**Impacto: Baixo · Esforço: P · Risco: Baixo**

[`scripts/gerar_zip_limpo.py`](ConfortoTermico/scripts/gerar_zip_limpo.py) não
é referenciado por nenhum arquivo versionado do repositório — nem código, nem
template, nem `pyproject.toml`, nem CI, nem documentação. É o único órfão
encontrado nos seis repositórios.

**Recomendação:** apagar, ou documentar em uma linha para que serve. Confirme
antes: pode ser uma ferramenta manual que você usa e que simplesmente não é
citada em lugar nenhum.

### H5 — Documentação desigual

**Impacto: Médio · Esforço: M · Risco: Baixo**

| Repositório | `docs/` |
|---|---|
| ConfortoTermico | ARQUITETURA, DESENVOLVIMENTO, DOMINIO, RUNBOOK, 1 ADR |
| ControleBancario | architecture, development, domain, operations, annual-planning-report |
| MegaSena | architecture, business-rules, development, deployment-vps, 1 ADR |
| **ControleRendaVariavel** | **deployment-vps, planilha-acoes, planilha-opcoes** |
| BackupRestore | (nenhum; usa README + KIT_RECUPERACAO + RESTAURAR na raiz) |
| SharedAuth | (nenhum; usa README + AGENTS) |

O CRV é o **maior** app do conjunto (14.996 linhas) e é o único dos quatro sem
documento de arquitetura nem de desenvolvimento. Também é o que tem a
navegação mais dependente de convenções não escritas (o desenho de expansão na
URL, os `HEARTBEAT_ENDPOINTS`, o agente RTD remoto).

Há ainda a divergência menor de nomenclatura: o Conforto usa nomes em
maiúsculas e português, os outros três usam minúsculas e inglês.

**Recomendação:** escrever `architecture.md` e `development.md` do CRV. Deixar
a divergência de nomes como está — renomear arquivos quebra links e não paga.

### H6 — Faixas de dependência divergentes

**Impacto: Médio · Esforço: P · Risco: Baixo**

Sua política registrada é alargar o teto e manter o piso. Dois pontos onde os
projetos discordam entre si:

| Dependência | ConfortoTermico | ControleBancario | ControleRendaVariavel | MegaSena |
|---|---|---|---|---|
| gunicorn | (usa waitress) | `>=26.0.0,<27` | **`>=23.0.0,<24`** | `>=25.1,<27` |
| Flask-Limiter | `>=3.0,<4.0` | — | `>=3.12,<4` | `>=3.0,<5` |
| Flask | `>=3.0,<4.0` | — | `>=3.1.3,<4` | `>=3.1.3,<4` |

O caso do gunicorn tem consequência visível: o CRV está preso na major 23
enquanto os irmãos estão na 25/26, e é o único cujo comando não passa
`--no-control-socket` — a flag existe a partir da família 25. O Dockerfile do
CRV é o único sem ela.

**Recomendação:** alinhar o gunicorn do CRV em `>=25.1,<27` e acrescentar
`--no-control-socket` ao comando; alinhar o teto do Flask-Limiter dos outros
em `<5`, como o MegaSena já faz.

### H7 — Trabalho não commitado no BackupRestore

**Impacto: Baixo · Esforço: — · Risco: —**

`agendamento.py`, `extract_backup.py` e `tests/test_agendamento.py` existem no
disco e não estão versionados; `README.md` e `.gitignore` têm alterações
pendentes. O `agendamento.local.json` também está no disco.

Não é achado técnico, é um alerta de estado: esse código não tem histórico, não
passa pelo CI e não entra em nenhum backup baseado em Git.

**Resolvido em 28/08.** Você autorizou o commit. Foram commitados
`agendamento.py`, `tests/test_agendamento.py` e as alterações de `.gitignore`
e `README.md` (commit `c838ebc`).

`extract_backup.py` foi **deixado de fora**, e a razão apareceu ao lê-lo: ele
consulta `SELECT payload_base64 FROM artefatos`, e a coluna `payload_base64`
não existe em [banco.py](BackupRestore/banco.py). Somado ao id 117 fixo no
código e ao caminho do Temp escrito à mão, é rascunho de depuração que já não
roda. Continua sem versionar, para você apagar ou recuperar.

### H9 — Comentário obsoleto no ConfortoTermico

**Impacto: Baixo · Esforço: P · Risco: Baixo · (achado da revalidação)**

[app_factory.py:206](ConfortoTermico/app/app_factory.py) diz "ver
`auth._proteger_csrf`, que usa `app.testing` para dispensar CSRF nos testes".
Essa função **não existe mais** — a proteção CSRF migrou para o Flask-WTF via
`sharedauth.csrf.iniciar_csrf`, e a busca por `_proteger_csrf` em todo o
repositório só encontra a própria menção no comentário.

Apareceu ao rastrear [S9](#s9--conforto_testing-desliga-o-rate-limit-em-qualquer-ambiente):
o comentário me fez procurar um mecanismo de dispensa de CSRF que já não
existe. É um bom exemplo do que você levantou — um texto que descreve uma
realidade antiga e desorienta quem lê depois.

**Recomendação:** corrigir o comentário para descrever os dois efeitos reais
de `app.testing` neste app (desliga o limiter, permite chave gerada), junto
com a correção de S9.

### H8 — A camada de compatibilidade de banco do ConfortoTermico

**Impacto: Médio · Esforço: G+ · Risco: Alto**

[`app/db_backend.py`](ConfortoTermico/app/db_backend.py) é um adaptador escrito
à mão que faz o PostgreSQL parecer o SQLite antigo: traduz marcadores `?` para
`%s`, emula `lastrowid` via `currval`, e devolve um `LinhaCompat`. O próprio
docstring lista duas armadilhas conhecidas e ainda abertas:

1. `RETURNING id` não pode ser aplicado a todo INSERT, porque várias tabelas
   não têm coluna `id` e isso quebraria upserts válidos;
2. um `LIKE '%termo%'` pode ser confundido com formatação de parâmetro na
   conversão para o estilo do psycopg, e escapar às cegas quebraria SQL que já
   usa `%s`.

São armadilhas que só se manifestam quando alguém escreve a consulta errada, e
que nenhum teste pega automaticamente.

**Recomendação:** **não mexer agora.** Registrado porque é o débito estrutural
que mais provavelmente vai cobrar juros um dia, e porque você deve saber que
ele existe quando decidir o roteiro de 2027. Migrar para SQLAlchemy Core seria
um projeto próprio, não um item de higiene.

---

## 8. Performance

A busca não encontrou nada crítico. O eager loading está bem usado, os índices
estão declarados (26 no CRV, 20 no Django, 4 no MegaSena) e o `pool_pre_ping`
está ligado onde importa. Dois registros:

### P1 — Uma consulta extra por página no CRV

**Impacto: Baixo · Esforço: P · Risco: Baixo**

O context processor `_theme_context`
([\_\_init\_\_.py:245-256](ControleRendaVariavel/app/__init__.py)) faz
`db.session.get(AppSetting, 1)` em **todo render autenticado**, só para
descobrir o tema. É uma consulta por página, sempre, para um valor que quase
nunca muda.

O próprio projeto já mostra que sabe evitar isso: o
`_collector_heartbeat_context` logo acima é explicitamente restrito a cinco
endpoints, com o motivo escrito ("ele custa uma consulta por render").

**Recomendação:** guardar o tema na sessão ao autenticar e ao trocá-lo, lendo
do banco só quando não estiver na sessão. Cinco linhas.

### P2 — Relatórios que carregam a tabela inteira

**Impacto: Baixo hoje · Esforço: G · Risco: Médio**

`dividends_results_context`
([dividends.py:88-105](ControleRendaVariavel/app/routes/dividends.py)) faz
`list(db.session.scalars(statement))` de todos os proventos e agrega em Python.
O mesmo desenho aparece em outros relatórios do CRV e do ControleBancario.

Para uma carteira pessoal isso é irrelevante — são centenas ou alguns milhares
de linhas, e agregar em Python é mais legível que a consulta SQL equivalente.

**Recomendação:** **não fazer.** Trocar por agregação no banco deixaria o código
mais complicado sem ganho perceptível, que é exatamente o que você pediu para
evitar. Registrado para o caso de o volume mudar de ordem de grandeza.

---

## 9. Fases sugeridas

Ordenadas por retorno sobre risco. Cada fase é independente e pode parar.

*Atualizado na revalidação: os seis itens novos foram encaixados, e H4/H7 já
estão feitos.*

**Fase 1 — SharedAuth v0.4.0 e adoção — ✅ escrita e testada em 28/08,
aguardando a tag**

Na biblioteca: A2, A3, A4, A7, A8, A9. Nos consumidores: S1, S2, S4, S5, mais
S9, H9 e H3 aproveitados no caminho.

| Suíte | Resultado |
|---|---|
| SharedAuth | 151 testes, 0 falhas (eram 82 — 69 novos) |
| ConfortoTermico | 155 testes, 0 falhas |
| ControleRendaVariavel | 117 testes, 0 falhas |
| MegaSena | 72 testes, 0 falhas |
| `ruff check` nos três apps | sem apontamento |

**Bloqueio conhecido e deliberado:** os três consumidores já apontam para
`@v0.4.0`, e essa tag **ainda não existe**. As suítes acima rodaram em
contêiner efêmero com o SharedAuth instalado da fonte local, não da tag. Nada
foi commitado e nada foi publicado; a tag é imutável e não será criada sem o
seu aval.

**ControleBancario permanece em `v0.3.0`**, de propósito: nenhum contrato da
v0.4.0 é necessário lá nesta fase, e a carta do SharedAuth diz que a adoção
não é implícita nem simultânea.

Duas regressões foram introduzidas e apanhadas pelas suítes durante o
trabalho, ambas corrigidas — ver
[§13](#13-o-que-as-suítes-apanharam-durante-a-fase-1).

**Fase 2 — Segredos unificados — ✅ escrita, testada e commitada em 28/08**

A1 na biblioteca (`v0.5.0`, tag local criada) e adoção nos **quatro** apps —
o ControleBancario entra aqui, pulando da v0.3.0 direto para a v0.5.0, porque
este é o primeiro contrato de que ele precisa desde então.

| Suíte | Resultado |
|---|---|
| SharedAuth | 168 testes, 0 falhas |
| ConfortoTermico | 155, 0 falhas |
| ControleRendaVariavel | 117, 0 falhas |
| MegaSena | 72, 0 falhas |
| ControleBancario | 147 passam; 4 falhas de `staticfiles` idênticas ao baseline |
| `ruff check` nos quatro | sem apontamento |

As 4 falhas do ControleBancario foram conferidas contra o commit anterior com
a mesma montagem: são artefato de rodar a suíte sem `collectstatic`, e não
têm relação com a mudança. O profile `quality` do Compose, que é como o CI
roda, faz o collectstatic.

`ConfortoTermico/app/secret_files.py` foi removido — não restou nada nele que
não fosse o contrato compartilhado. O do CRV encolheu para o caso que só ele
tem (o agente RTD lendo de `.secrets/` no Windows).

**Decisão deliberada, e pendência aberta:** a trava `caminho_esperado` — a
checagem estrita que só o ConfortoTermico tinha — está disponível para os
outros três, e os quatro Compose montam em `/run/secrets/<nome>`, então ela
funcionaria. Não foi aplicada: apertar o contrato de implantação de três apps
dentro de um commit rotulado "adotar" esconderia a mudança, e eu não consigo
ver daqui se algum fluxo local seu aponta `*_FILE` para outro lugar. Fica como
item a decidir — é um argumento por chamada.

**Fase 3 — Endurecimento pontual e higiene — ✅ concluída em 28/08**

S3, S8, H6 e P1 nesta fase; S9, H9 e H3 já tinham entrado na Fase 1.

| Item | O que mudou |
|---|---|
| S3 | `web.py` do BackupRestore recusa `Host` fora do loopback em toda requisição e `Origin` estranha nos métodos mutantes. 7 testes novos; suíte em 65. |
| S8 | Favicon vira `favicon.svg` no MegaSena e no ControleBancario; `img-src` fecha em `'self'` nos dois. A CSP dos quatro apps é agora a fechada da biblioteca, sem exceção. |
| H6 | gunicorn do CRV sobe de `>=23,<24` para `>=25.1,<27` e ganha `--no-control-socket`; teto do Flask-Limiter vai a `<5` no CRV e no ConfortoTermico. |
| P1 | Tema do CRV passa a viver na sessão — some uma consulta por render autenticado. |

**Verificação:** SharedAuth 168, ConfortoTermico 155, CRV 117, MegaSena 72,
BackupRestore 65 — todas sem falha. ControleBancario 150 passam com
`collectstatic` prévio, e o `favicon.svg` foi confirmado no manifesto
(`favicon.421bd717118b.svg`), o que prova S8 ponta a ponta. `ruff check` limpo
nos quatro.

**Uma falha pré-existente, não minha:**
`test_annual_planning_partial_uses_summary_headers_without_transfer_card` do
ControleBancario falha, e falha idêntica no commit anterior (verificado com a
mesma montagem). É um bug de asserção no commit `feat: adiciona relatório de
planejamento anual`, que estava sem push antes desta rodada: o teste injeta
"Ana" em três lugares — a lista de titulares do filtro, o rótulo da conta e a
coluna do relatório — e depois exige `rendered.count("Ana") == 1`. A asserção
não acompanhou a chegada do painel de filtros ao partial. Deixado para o
mantenedor: está fora do escopo da auditoria e é trabalho em andamento dele.

**Fase 4 — A barra de endereço do CRV — ⚠️ concluída com escopo reduzido em 28/08**

A implementação começou por verificar a premissa, e a premissa estava errada:
`expanded`, `expanded_tickers` e `expanded_years` nunca chegaram à barra de
endereços. Ver [U1](#u1--estado-de-interface-na-barra-do-crv) para a apuração.

Feito: `hx-push-url` → `hx-replace-url` nas oito ocorrências, o que resolve o
empilhamento de histórico (cada mexida num select criava uma entrada). Suíte
do CRV: 117 testes, 0 falhas; `ruff` limpo.

Não feito: mover os filtros para a sessão. Com a premissa corrigida, isso
deixou de ser higiene e virou uma troca — perder link compartilhável, favorito
e F5 em nome de uma barra vazia. É decisão do mantenedor, não consequência do
achado.

**Fase 5 — Documentação do CRV (1 sessão)**
H5: `architecture.md` e `development.md`.

**Fase 6 — ControleBancario sem `application.js` (várias sessões)**
H1, que resolve U2. Por seção, com parada possível a qualquer momento.

**Concluídos em 28/08:** H4 (script órfão removido), H7 (agendamento
commitado).

**Sem fase:** H2, H8, S6, S7, P2 — registrados, decisão adiada.

---

## 12. O que a revalidação reexaminou e manteve

Sua liberação vale para conclusões apoiadas em documentação. Estas cinco foram
reabertas e continuam de pé, porque o que as sustentava era mérito técnico:

**S6 — rate limit `memory://` com dois workers.** Não há backend compartilhado
barato: a biblioteca `limits` suporta Redis, Memcached, MongoDB e etcd, e
nenhum PostgreSQL — então não dá para reaproveitar o banco que já existe.
Subir um Redis para coordenar contador de rate limit em sistema pessoal não
paga, e o nginx já cobre o caso que importa (`POST /login`). Mantido.

**H2 — 4.928 linhas de JS no ConfortoTermico.** A recusa nunca foi documental:
é o tamanho, o risco e o fato de ser a interface de um sistema que aciona
equipamento. Mantido como direção sem prazo, depois de H1 provar o padrão.

**H8 — camada de compatibilidade de banco do Conforto.** Idem: projeto
próprio, não item de higiene. Mantido.

**P2 — relatórios que carregam a tabela inteira.** Trocar por agregação em SQL
deixaria o código menos legível para ganhar tempo que ninguém percebe no
volume atual. É o caso onde a sua orientação de simplicidade e o mérito
técnico apontam para o mesmo lado. Mantido como recusa.

**Autorização rica (parte de A6).** Os modelos do Conforto e do Django são
diferentes de verdade, não cópias que divergiram. Mantido — mas o pedaço que
era genuinamente comum saiu de lá e virou
[A9](#a9--requer_papel-o-decorator-de-admin-escrito-duas-vezes).

Um registro honesto sobre o método: a primeira versão deste relatório elogiou,
na §10, os comentários que explicam *por quê* — e o elogio continua válido,
porque foram eles que permitiram separar decisão consciente de descuido. Mas
eles também me fizeram parar cedo demais em seis pontos. As duas coisas são
verdadeiras ao mesmo tempo: o comentário que explica a razão é o que torna a
revisão possível, e é também o que a encerra antes da hora se for lido como
sentença.

---

## 10. O que a auditoria confirmou que está bem

Vale escrever, porque um relatório só de achados dá uma impressão falsa do
conjunto:

- A carta do SharedAuth em `AGENTS.md` é o melhor documento dos seis
  repositórios. Os critérios de entrada, a fronteira importável sem Flask e a
  regra de tags imutáveis são o que impediu a biblioteca de virar um `commons`
  genérico. As propostas da seção 6 foram todas testadas contra ela.
- Os comentários que explicam **por que** uma decisão foi tomada — o
  `Referrer-Policy: same-origin` por causa do `Origin` no POST, o `ProxyFix`
  atrás de variável, o `trusted_proxy` do waitress, a reatribuição de
  `view_functions` — são a razão pela qual esta auditoria conseguiu separar
  decisão consciente de descuido. Sem eles, metade dos itens acima teria virado
  "achado" indevido.
- A adoção do SharedAuth foi feita com disciplina: cada app fixa a tag `v0.3.0`
  explicitamente, o Django instala só o núcleo sem o extra `[flask]`, e as
  exceções de CSP (`img-src data:` no MegaSena e no ControleBancario) são
  pedidas por nome com o motivo escrito no ponto da chamada.
- O endurecimento dos Compose e a estrutura de CI são uniformes nos quatro apps
  sem que exista bloco compartilhado copiado — foi mantido igual por cuidado,
  não por geração automática.

---

## 11. Registro de decisão

Estado em 28/08, depois da sua aprovação geral e da revalidação. Os seis itens
marcados **novo** não estavam na versão que você aprovou — são os únicos que
ainda precisam do seu aceite.

| # | Achado | Impacto | Esforço | Risco | Recomendação | Situação |
|---|---|---|---|---|---|---|
| S1 | Cookie "lembrar-me" de 365 dias (CRV, MegaSena) | Alto | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| S2 | Sem expiração por inatividade (CRV, MegaSena) | Médio | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| S3 | BackupRestore aceita POST de qualquer origem | Médio | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| S4 | `_load_user` do CRV sem guarda | Baixo | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| S5 | Conforto fora do limiter compartilhado | Médio | P | Médio | Aceitar | ✅ **Feito** 28/08 |
| S6 | Rate limit por processo com 2 workers | Médio | M | Médio | Não agir | Registrado |
| S7 | Trilha de auditoria | Médio | G | Baixo | Decisão sua | MegaSena **recusado** 28/08; aberto só p/ CRV |
| S8 | Fechar `img-src data:` nos dois apps | Médio | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| S9 | `CONFORTO_TESTING` desliga o rate limit | Médio | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| U1 | Estado de UI na barra do CRV | Baixo | P | Baixo | **Premissa corrigida** — ver o achado | ⚠️ **Parcial** 28/08 |
| U2 | Estado de UI na barra do Bancário | Médio | M | Médio | Junto de H1 | **Aceito** — Fase 6 |
| A1 | `sharedauth.secrets` | Alto | M | Baixo | Aceitar | ✅ **Feito** 28/08 |
| A2 | Duração do "lembrar-me" no `configurar_sessao` | Alto | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| A3 | `iniciar_limiter` com política do consumidor | Médio | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| A4 | `aplicar_limite` / `isentar_limite` | Alto | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| A5 | `sanitizar_log` compartilhado | Baixo | P | Baixo | Adiar (depende de S7) | Adiado |
| A7 | `ler_flag` no núcleo | Médio | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| A8 | `montar_url_postgres` em Python puro | Médio | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| A9 | `requer_papel` para o binário admin | Baixo | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| H1 | Apagar `application.js`, consolidar em HTMX | Alto | G | Médio | Aceitar, em fases | **Aceito** — Fase 6 |
| H2 | JS próprio do ConfortoTermico | Alto | G+ | Alto | Não agora | Registrado |
| H3 | Doze arquivos com BOM | Baixo | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| H4 | `gerar_zip_limpo.py` órfão | Baixo | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| H5 | Documentação do CRV | Médio | M | Baixo | Aceitar | **Aceito** — Fase 5 |
| H6 | Faixas de dependência divergentes | Médio | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| H7 | Trabalho não commitado no BackupRestore | Baixo | — | — | Decisão sua | ✅ **Feito** 28/08 (`c838ebc`) |
| H8 | Camada de compatibilidade de banco do Conforto | Médio | G+ | Alto | Não agora | Registrado |
| H9 | Comentário obsoleto em `app_factory.py:206` | Baixo | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| P1 | Consulta de tema por render no CRV | Baixo | P | Baixo | Aceitar | ✅ **Feito** 28/08 |
| P2 | Relatórios carregando tabela inteira | Baixo | G | Médio | Recusar | Recusado |

---

*Auditoria feita em 28/08/2026 sobre a base commitada localmente. Nenhum
arquivo dos projetos foi alterado; nenhum commit foi criado.*

---

## 13. O que as suítes apanharam durante a Fase 1

Registrado porque as duas falhas dizem algo sobre onde o risco realmente mora
neste conjunto — e porque as duas foram apanhadas por testes que já existiam
ou que nasceram na mesma mudança.

### O 403 que deixou de ser `abort`

A primeira versão de `sharedauth.access.requer_papel` **devolvia** a resposta
403 em vez de levantar com `abort`. Parece equivalente e não é: `abort` levanta
a exceção HTTP, e é isso que deixa um `errorhandler(403)` do consumidor
renderizar a página de erro do próprio aplicativo. Devolvendo a resposta
pronta, o visitante receberia um 403 cru, sem a casca visual do app.

Quem apanhou: `tests/test_authorization.py` do ControleRendaVariavel, com dois
testes que afirmam que a recusa **levanta**. Eles falharam com "DID NOT RAISE".
Corrigido na biblioteca, com um teste novo que registra a razão
(`test_recusa_em_html_levanta_para_o_errorhandler_do_consumidor`).

A lição não é sobre `abort`: é que extrair uma mecânica para a biblioteca pode
trocar um detalhe de comportamento que o consumidor dependia sem dizer. A
suíte do consumidor é a rede — não a da biblioteca.

### A trava que quebrou a própria suíte

`_validar_testing` (achado [S9](#s9--conforto_testing-desliga-o-rate-limit-em-qualquer-ambiente))
lê `config.development`, um campo do `AppConfig`. A primeira tentativa de
acomodar a suíte definiu a **variável de ambiente** `CONFORTO_DEVELOPMENT` no
fixture — inútil, porque `tests/conftest.py` monta o `AppConfig` à mão, sem
passar por `AppConfig.from_env`. Vinte e sete testes quebraram de uma vez.

Corrigido no lugar certo: o `_config()` do conftest passa `development=True`,
declarando no mesmo objeto que a fábrica lê que aquilo é contexto de
desenvolvimento.

Vale notar o que a trava **não** faz: ela não cria um jeito novo de desligar a
proteção. Ligar `CONFORTO_TESTING` continua desligando o rate limiter — só que
agora exige, junto, desenvolvimento explícito e host de loopback, a mesma
combinação que `_validar_debug` já cobrava do `CONFORTO_DEBUG`.

### Mudança de tipo de exceção, sem consumidor afetado

`ler_flag` levanta `FlagInvalidaError` (um `ValueError`), enquanto o
`_environment_flag` do MegaSena levantava `RuntimeError`. Nenhum teste dos
quatro apps afirma sobre esse tipo, e nos dois casos a falha continua
derrubando a inicialização de forma visível. Fica registrado por ser uma
diferença real de contrato, não por ter causado problema.
