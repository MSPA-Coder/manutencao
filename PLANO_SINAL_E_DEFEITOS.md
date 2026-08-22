# Plano — sinal de falha e os defeitos que a consistência não podia ver

Iniciado em 2026-08-21. **Bloco 1 concluído** — fases 0, 0b, 1, 2, 3, 4, 6 e 7.
**Fase 5 (métricas) adiada por decisão do mantenedor.** Bloco 2 (fases 8 a 11)
**em execução** — ver o quadro abaixo.

---

## COMO RETOMAR (bloco 2, atualizado em 2026-08-21)

Sessões anteriores foram interrompidas por limite de uso. Este bloco existe
para que a próxima comece a trabalhar em vez de reconstruir contexto.

### Estado por repositório

| Repositório | Situação |
|---|---|
| **SharedAuth** | **Fase 8 pronta.** Mesclada em `main` e publicada como **tag `v0.3.0`**. Nada a refazer |
| **ConfortoTermico** | **Pronto e revisado.** PR [#28](https://github.com/MSPA-Coder/Sistema-de-Controle-de-Indice-de-Conforto-Termico/pull/28) |
| **ControleBancario** | PR [#30](https://github.com/MSPA-Coder/sistema-financeiro/pull/30) — **NÃO revisado** |
| **ControleRendaVariavel** | PR [#25](https://github.com/MSPA-Coder/ControleRendaVariavel/pull/25) — **NÃO revisado** |
| **MegaSena** | PR [#33](https://github.com/MSPA-Coder/mega-sena/pull/33) — **NÃO revisado** |

### Os três PRs não revisados: o que falta e por quê

Os três agentes foram interrompidos pelo limite de uso **durante a própria
verificação final**. O trabalho estava na árvore e foi commitado para não se
perder — `ruff` passa limpo nos três, mas a suíte não roda nesta máquina
(ControleBancario não tem Django instalado; MegaSena estoura o tempo). **Quem
valida é o CI na imagem `quality`.**

Portanto: **não mesclar sem CI verde e sem ler o diff.** O que conferir em cada
um está escrito na mensagem de commit do próprio PR. Em resumo:

- **todos:** chamada que ficou no `confirm` NATIVO em vez do componente —
  `grep -rn "[^a-zA-Z]confirm(" app/` (ou `static/ templates/` no Django);
- **CRV:** a confirmação da carteira Simulada é CONDICIONAL. Se a condição se
  perdeu, editar posição passou a confirmar sempre, que é o oposto da regra;
- **MegaSena:** o caminho `data-confirm-message` do `base.js` e os atributos
  nos templates saem JUNTOS — se sobrou um lado, ficou meio mecanismo. E
  `templates/components/flash_messages.html` foi APAGADO: confirmar que quem o
  incluía passou a incluir o parcial do sharedauth, senão a página quebra.

### O componente, em cinco linhas

`sharedauth.ui` — CSS e JS puro, **sem template de framework** (o
ControleBancario é Django e instala sem o extra `[flask]`).

- Flask: `registrar_ui(app)`; no template,
  `url_for('sharedauth_ui.static', filename='sharedauth-ui.css')` e `.js`
- Django: `STATICFILES_DIRS += [("sharedauth", CAMINHO_ESTATICO)]`; no template,
  `{% static 'sharedauth/sharedauth-ui.css' %}` e `.js`
- Declarativo: `data-sa-confirmar`, `data-sa-titulo`, `data-sa-severidade`
  (`success|error|warning|info`), `data-sa-ok`, `data-sa-formulario`
- Programático: `await window.sharedauth.confirmar({...})` → `Promise<boolean>`;
  `window.sharedauth.avisar({mensagem, severidade})`
- Ponte servidor→toast: `<div hidden data-sa-avisos='[{...}]'>`
- **Já intercepta `htmx:confirm`**: um `hx-confirm` existente passa a usar o
  modal sem trocar o atributo

O contrato completo está no docstring de `sharedauth/ui/__init__.py` e no
cabeçalho de `sharedauth/ui/estatico/sharedauth-ui.js`.

### As duas armadilhas que já morderam — procure por elas nos três restantes

1. **`confirm(` em vez de `confirmar(`.** No ConfortoTermico o agente deixou
   duas chamadas ao `window.confirm` NATIVO recebendo objeto de opções, o que
   mostra `[object Object]`. Passou pela autoverificação dele porque ele
   procurou chamadas *sem* `await`, e estas tinham `await`. **Grep certo:**
   `grep -rn "[^a-zA-Z]confirm(" app/` e confirmar que só sobra `confirmar(`.
2. **Handler inline que a CSP bloqueia.** `onsubmit="return confirm(...)"` em
   `usuarios.html` nunca disparava — `script-src 'self'` sem `unsafe-inline`
   nem nonce. Excluir usuário vinha sem confirmação nenhuma. **Grep certo:**
   `grep -rn "onsubmit=\|onclick=\|onchange=" templates/`.

Nos dois casos o sintoma é o mesmo: proteção que parece existir e não existe.
É o tema deste plano inteiro.

### Regra que decide onde pôr confirmação

**Irreversível pede; reversível NÃO pede.** A lista das 124 operações, com a
classificação de reversibilidade por projeto, está em
[INVENTARIO_OPERACOES_DESTRUTIVAS.md](INVENTARIO_OPERACOES_DESTRUTIVAS.md),
seção 7. Ler antes de decidir. Confirmar demais anula a confirmação.

Duas linhas do inventário que **não** devem virar confirmação: "gravar apostas"
e "criar usuário" no MegaSena aparecem como irreversíveis só porque não existe
rota de exclusão — é funcionalidade que falta, não confirmação que falta.

### Depois que os quatro PRs mesclarem

1. `./deploy.sh <projeto>` para cada um (o rollback automático já protege).
2. Marcar as fases 8 a 11 como concluídas neste plano.
3. `README.md` deste repositório: a linha do plano já existe; atualizar o
   status.

Documentos irmãos:
[PLANO_EQUALIZAR_BASE_COMPARTILHADA.md](PLANO_EQUALIZAR_BASE_COMPARTILHADA.md)
— a rodada anterior, concluída; é a referência de forma e de mecânica.
Este plano é de natureza diferente: não equaliza nada entre os projetos.

---

## 1. O problema, em uma frase

Todas as rodadas anteriores foram **convergentes** — equalizar os quatro
entre si, unificar no SharedAuth, remover resíduo. São objetivos que comparam
projetos uns com os outros.

O efeito colateral é estrutural: **uma lacuna que os quatro têm igualmente é
invisível para uma varredura de consistência.** Não há divergência para
detectar, então nada aponta para ela.

É por isso que observabilidade está em zero absoluto nos seis repositórios.
Não foi restrição de documento nem decisão registrada em lugar nenhum. Foi o
formato do trabalho.

Este plano ataca duas coisas: as **lacunas uniformes** (o que a consistência
não podia ver) e as **divergências que sobreviveram** à equalização.

---

## 2. O que foi levantado (2026-08-21)

Conferido lendo o código, não por inferência. Cada linha abaixo tem arquivo
e número.

### Tema A — não existe caminho entre uma falha e um humano

| Falha | Como se descobre hoje |
|---|---|
| App devolve 500 | tropeçando nela |
| Backup noturno falha | **nunca** — `vps/backup-db.service` não tem `OnFailure=`; o log morre no journald |
| Contêiner fica `unhealthy` | **nunca** — o Compose não age sobre healthcheck. `restart: unless-stopped` reage a processo que morre, não a saúde. Um app doente fica de pé e quebrado indefinidamente |
| Renovação do certbot falha | quando o navegador avisa |
| Disco do VPS enche | quando o Postgres para de escrever |

Zero ocorrências de `prometheus`, `sentry`, `opentelemetry`, `statsd` ou
`grafana` nos seis repositórios. Não se sabe p95, taxa de erro nem
throughput de nada.

Log: cada projeto com um idioma próprio — `basicConfig` em
`MegaSena/app/__init__.py:301`, `dictConfig` em
`ControleBancario/financeiro/settings.py:270`, `RotatingFileHandler` no
agente do CRV, e nada no ICT do ConfortoTermico. Sem request-id, sem
correlação, teto de 30 MB por serviço no driver `json-file`. Depurar é SSH
mais `docker logs` em quatro contêineres.

O `deploy.sh` verifica a saúde batendo em `/login`, que responde 200 com o
banco fora do ar. Os quatro têm `/health` público que consulta o banco de
verdade (`sharedauth.health`) — a sonda certa existe e não é usada.

### Tema B — um limitador de taxa que não limita

`ConfortoTermico` é **o único dos quatro sem `ProxyFix`**. Comparação:

| Projeto | Confiança em cabeçalho de proxy |
|---|---|
| ControleRendaVariavel | `app/__init__.py:131` — `ProxyFix(x_for=1, x_proto=1, x_host=1)` |
| MegaSena | `app/__init__.py:130` — idem |
| ControleBancario | `financeiro/settings.py:256` — `SECURE_PROXY_SSL_HEADER` |
| **ConfortoTermico** | **nenhuma** |

Ele roda atrás do nginx. Consequência dupla e concreta:

1. `get_remote_address` devolve o IP do gateway Docker. O
   `default_limits=["100 per hour", "20 per minute"]` de
   `app/app_factory.py:73` é **um balde único para o mundo inteiro somado**,
   não por cliente. Num app que faz polling, é auto-DoS esperando a hora — e
   não protege contra força bruta nenhuma.
2. `app/audit_log.py` grava esse mesmo IP de gateway em todo evento de
   autenticação. O registro forense está formalmente correto e materialmente
   inútil.

Vale para os três Flask: o armazenamento do limitador é `memory://`, ou seja
contador por processo. Com `gunicorn --workers 2` o limite efetivo é o dobro
do escrito, e **cada deploy zera a proteção contra força bruta**.

### Tema C — nenhuma varredura de vulnerabilidade, e o elo mais fraco é o compartilhado

Zero ocorrências de `pip-audit`, `bandit`, `trivy` ou `grype` em qualquer
arquivo dos seis repositórios. O Dependabot abre PR de versão; ninguém nunca
pergunta *"a imagem que está rodando agora tem CVE?"*.

E **`SharedAuth` é o único repositório sem `.github/dependabot.yml`** — é a
única dependência compartilhada pelos quatro, portanto o único ponto de
supply chain do conjunto, e é o menos vigiado dos seis. É instalado por tag
Git sem hash de verificação: a política diz "nunca reescrever tag", mas o Git
não a impõe.

### Tema D — o `?` que vira `%s` por substituição cega

`ConfortoTermico/app/db_backend.py` é um emulador de SQLite sobre
PostgreSQL, sobra de uma migração que terminou. O corpo da função de
adaptação é uma linha: devolve `sql.replace("?", "%s")`, sob o comentário
"as consultas do projeto não contêm o caractere '?' em literais SQL".

O invariante está garantido por um comentário. E `?`, `?|` e `?&` são
**operadores legítimos de `jsonb` no PostgreSQL** — e este projeto já
consulta jsonb (`l.entradas::jsonb`, em `app/database_leituras.py:284`). No
dia em que alguém escrever a consulta natural, o `replace` a corrompe em
silêncio.

Junto: `lastrowid` faz um `SELECT currval(...)` — round trip extra por
INSERT, em vez de `RETURNING id`. E `_normalizar_valor` reserializa
`dict`/`list` para string JSON e datas para ISO, jogando fora a tipagem
nativa do Postgres para imitar SQLite, numa tabela de série temporal.

Este plano **só fecha o risco correcional**. A refatoração fica para depois
(seção 7).

### Tema E — sobras pontuais

| Item | Onde | Efeito |
|---|---|---|
| CRV sem `pool_pre_ping` | `ControleRendaVariavel/app/__init__.py:91` — único dos que usam SQLAlchemy sem ele | Postgres reinicia (deploy, OOM) → 500 até o pool reciclar sozinho |
| Sem `.env.vps.example` | ConfortoTermico é o único dos quatro sem | não há linha de base versionada do que a produção deveria ter. **Corrigido pela Fase 0: a produção está certa (`CONFORTO_COOKIE_SEGURO=1`)** — a suspeita levantada a partir do arquivo local não se confirmou. O que resta é o risco de não existir template que preserve isso numa recriação |
| `SECRET_KEY` autogerada | `ConfortoTermico/app/auth.py:166` | os outros três falham alto se faltar; este gera e persiste em `instance/`. Perder o volume invalida todas as sessões sem dizer nada |
| nginx sem `default_server` | `vps/nginx/*` | requisição com `Host` desconhecido cai no primeiro server block carregado |
| nginx sem HTTP/2 | idem — `listen 443 ssl;` sem `http2 on;` | tudo em HTTP/1.1 |
| nginx não serve estático | idem — só `location / { proxy_pass }` | todo asset passa pelo gunicorn/waitress; o `chart.umd.js` inteiro sai do Python |
| nginx sem `gzip` nem cache de estático | idem | revalidação a cada carga |

### Tema F — interface: confirmação, mensagem e login (levantado 2026-08-21)

Levantado a pedido do mantenedor, depois da aprovação do bloco 1. Os três
pedidos procedem, e o diagnóstico é mais específico do que a impressão inicial.

**F.1 — confirmação de CRUD: quatro mecanismos, cobertura minoritária.**

| Projeto | Como confirma | Quantos |
|---|---|---|
| ControleBancario | `data-confirm` → modal próprio (`openConfirmModal`) | 14 |
| ControleRendaVariavel | `hx-confirm` do HTMX — por baixo é o `window.confirm` do navegador | 13 |
| MegaSena | dois mecanismos redundantes sobre os **mesmos 2 botões** | 2 |
| ConfortoTermico | `confirm()` nativo, e nada mais | 5 |

Contra ~79 rotas que mutam estado e 92 funções com nome de exclusão ou
alteração. A diferença entre projetos não é de estilo: em dois deles a
confirmação é a caixa cinza do navegador, no outro é um modal desenhado.

**Números corrigidos em 2026-08-21 pelo inventário item a item.** A contagem
original desta tabela vinha de `grep`, e errou em duas linhas. O MegaSena
estava registrado como "os três misturados, 2 + 2 + 3", o que sugeria sete
operações protegidas; na verdade o `hx-confirm` e o `data-confirm-message`
cobrem **os mesmos dois botões**, e o terceiro caminho (`base.js:58`) tem uma
guarda que se desliga quando o `hx-confirm` está presente. São 2, não 7 — e o
resto do aplicativo não confirmava nada. Contar ocorrências de atributo mede o
código; só o inventário mede a cobertura. Ver
[INVENTARIO_OPERACOES_DESTRUTIVAS.md](INVENTARIO_OPERACOES_DESTRUTIVAS.md).

**O componente que o mantenedor descreveu já existe**, em
`ControleBancario/static/js/core/application.js:760` — `openConfirmModal`,
declarativo por `data-confirm`, ~40 linhas de JS puro. Falta ícone por
severidade (hoje o título é fixo em "Confirmar exclusão") e estar fora de um
arquivo de 900 linhas, em lugar compartilhado.

**F.2 — mensagens: a base comum existe e institucionalizou o formato errado.**
`sharedauth/messages` já dá as quatro categorias e CSS por variável — boa
fundação, criada na rodada de unificação. Mas renderiza **um banner no topo da
página**, que é justamente o formato que o mantenedor não quer, e não tem
ícone nenhum.

**F.3 — o login "harmonizado" é cópia manual, não herança.**
`ControleBancario/static/css/pages/login.css` redeclara o próprio `:root`
(`--bg: #0f172a`, `--text: #e5e7eb`, `--border: #334155`) em vez de importar
as tokens do app. E `static/css/core/application.css` define **cinco temas**;
os valores que o login copiou são os do bloco escuro.

Ou seja: o login está congelado num dos cinco temas. Trocar de tema no app não
o acompanha, e mudar uma cor lá faz o login divergir em silêncio. É o mesmo
mecanismo de deriva do Tema A do plano anterior — o comentário mandava manter
igual e as cópias divergiram assim mesmo.

O alvo, portanto, não é copiar esse login para os outros três. É **fazer o
login herdar as tokens do app** nos quatro, ControleBancario incluído. Cada
app mantém sua paleta; todos ganham a mesma estrutura, e a harmonização passa
a ser automática em vez de mantida na unha.

---

## 3. O que este plano deliberadamente não toca

- **Unificar os três estilos de app Flask.** MegaSena é organizado por
  domínio, CRV é plano com `routes/`, ConfortoTermico é plano com DAL
  própria. O custo de convergir supera o ganho. Fica registrado como decisão
  consciente, não como acidente.
- **A refatoração completa do `db_backend.py`.** Depende de ter Postgres real
  no CI antes; ver seção 7.
- **Redis para o limitador de taxa.** Um serviço novo, com backup e
  atualização próprios, para resolver um problema que o `limit_req` do nginx
  já resolve de graça e melhor (compartilhado por definição, sobrevive a
  deploy).
- **Prometheus e Grafana rodando no VPS.** Somariam RAM e CPU ao mesmo host
  das quatro apps e virariam um quinto sistema para manter.
- **Registry de imagem (GHCR) e artefato imutável.** Ver decisão D2.

---

## 4. Decisões tomadas pelo mantenedor (2026-08-21)

**D1 — observabilidade de nível intermediário.** Rota `/metrics` por app,
coletada para fora do VPS por camada gratuita. Sem stack local.

**D2 — o deploy continua construindo no servidor, e ganha rollback.**
O mantenedor pediu segurança sem custo e sem profissionalização excessiva. A
avaliação: o `deploy.sh` atual já é melhor que a média — recusa árvore suja,
faz `merge --ff-only`, espera a saúde e confere HTTP no fim. Um registry
seria grátis em dinheiro mas custaria uma credencial nova morando no VPS e um
workflow a mais para manter: **adiciona superfície em vez de reduzir**.

O que falta não é o registry, é rollback. Hoje um deploy que quebra o site
avisa e deixa quebrado; o conserto é para frente, sob pressão. Guardar o
commit anterior e voltar sozinho quando a verificação falhar são ~15 linhas,
zero peça nova.

**D3 — `db_backend.py`: blindar agora, refatorar depois.**

**D4 — escopo do bloco 1: apenas sinal e defeitos pontuais.**

**D5 — canal de alerta: bot do Telegram.** Recusados o ntfy.sh (tópico é
público para quem adivinhar o nome) e o SMTP (precisa de relay, e e-mail de
servidor cai em spam). O Telegram é o único privado por construção que não
pede infraestrutura.

O token e o chat id vivem em `/home/ubuntu/.secrets/telegram.env`, modo 600,
dono `ubuntu` — **nunca** como variável de ambiente nem como argumento de
linha de comando, que apareceria em `ps`. Mesmo padrão de segredo-por-arquivo
que os quatro projetos já usam. O arquivo não entra em repositório nenhum; o
`alerta.sh` que o lê entra, porque não tem segredo dentro.

**D6 — a interface entra como bloco 2, depois do bloco 1.** Pedido do
mantenedor em 2026-08-21: confirmação de CRUD, padrão de mensagem e padrão de
login. Fica depois porque o bloco 1 fecha defeito que sangra agora e custa
pouco, e porque existe dependência real de ordem: o rollout de confirmação
mexe em submit de formulário nos quatro apps, e é exatamente o tipo de
mudança que quebra em silêncio. Fazer isso **depois** de existir alerta e
taxa de erro é materialmente mais seguro.

**Exceção que sobe para a Fase 0b:** o inventário de operações destrutivas
sem confirmação é leitura pura. Se revelar caso grave, aquele caso é corrigido
imediatamente, sem esperar o bloco 2.

**D7 — modal para decidir, toast para informar.** O mantenedor pediu "estilo
msgbox com ícone variando conforme o grau de severidade" e disse explicitamente
que quer o resultado, sem limitar a alternativa. Recusado usar modal
bloqueante para *toda* mensagem: "salvo com sucesso" exigindo um clique vira
atrito dezenas de vezes por dia. Adotado:

- **antes de ação destrutiva** → modal bloqueante, com ícone de severidade
- **depois da ação** → toast com o *mesmo* ícone e as *mesmas* cores, sem
  bloquear; sucesso some sozinho, erro fica até ser fechado

Mesma linguagem visual, dois comportamentos.

**D8 — o compartilhado é CSS e JS puro, não template de framework.** O
projeto de referência de interface é o ControleBancario, que é o único Django
e o único que não consome a parte Flask do SharedAuth. Portanto a camada
comum não pode ser template Jinja. Fica: um pacote de CSS (tokens de
severidade e componentes) mais um módulo JS sem dependência, servível igual
pelos dois frameworks. Os templates ficam finos e por framework.

---

## 6. Fases de execução

### Fase 0 — conferir antes de mexer

Nada aqui é editável a partir da estação de trabalho. Levantar no VPS:

- [x] `free -h`, `nproc`, `df -h` — dimensionamento real do host
- [x] `docker system df` — quanto o cache de build dos deploys acumulou
- [x] o `.env.docker` de produção do ConfortoTermico: `CONFORTO_COOKIE_SEGURO`
      está em `1`? (não dá para verificar daqui — o arquivo é gitignored)
- [x] `nginx -v` — decide entre `http2 on;` e `listen ... http2`
- [x] `systemctl list-timers` — o certbot renova por timer? tem `OnFailure=`?
- [x] limites atuais da camada gratuita escolhida em D1 (não confiar em
      número memorizado; ler na fonte no dia)

### Fase 0b — inventário de operação destrutiva sem confirmação

Leitura pura, não altera nada. Sobe para junto da Fase 0 porque o risco aqui
é perda de dado, não estética — e porque o resultado pode reordenar o resto.

- [x] listar, nos quatro apps, toda rota que exclui ou altera estado
- [x] marcar quais têm confirmação hoje e por qual dos quatro mecanismos
- [x] destacar as que **não têm nenhuma** e cujo efeito é irreversível
- [x] **se aparecer caso grave** (exclusão de conta, lançamento ou posição sem
      pergunta), corrigir aquele caso imediatamente com o mecanismo que o
      projeto já tem — sem esperar o bloco 2 e sem inventar componente novo
- [x] o inventário vira a lista de trabalho da Fase 9

**Concluída em 2026-08-21**, em duas etapas. A primeira parou na *medição* — a
tabela do Tema F, com os quatro mecanismos e a contagem agregada. Isso não é
inventário: sem saber qual rota, em qual arquivo, com ou sem confirmação e
reversível ou não, o critério "irreversível pede, reversível não pede" não tem
como ser aplicado e a Fase 9 não tem sobre o que trabalhar.

A segunda etapa produziu a lista item a item — **124 operações nos quatro
aplicativos** — em [INVENTARIO_OPERACOES_DESTRUTIVAS.md](INVENTARIO_OPERACOES_DESTRUTIVAS.md).
Achou **seis casos graves**, todos corrigidos e implantados no mesmo dia, e
corrigiu de passagem um número errado deste plano (ver Sessão 5).

### Fase 1 — sinal de falha (maior retorno, menor custo)

- [x] bot criado no @BotFather; token e chat id gravados pelo mantenedor em
      `/home/ubuntu/.secrets/telegram.env` (600, dono `ubuntu`). Os valores
      não passam por conversa nem por repositório
- [x] `alerta.sh` no VPS: lê o arquivo, envia por `curl`, e falha em silêncio
      sem derrubar quem o chamou — um alerta que não sai não pode virar um
      segundo incidente. Versionado em `vps/` aqui (não tem segredo dentro)
- [x] `alerta@.service` — unidade template para servir de alvo de `OnFailure=`
- [x] testado com uma falha forçada de verdade, não com um envio manual
- [x] `OnFailure=` em `backup-db.service` apontando para uma unidade de alerta
- [x] `OnFailure=` na unidade de renovação do certbot
- [x] auto-cura de contêiner `unhealthy`: **timer systemd com script curto**,
      rodando como `ubuntu` (já está no grupo `docker`). Recusado o
      `autoheal` em contêiner: exige montar o socket do Docker, que é
      privilégio de root na prática — privilégio grande demais para o
      problema
- [x] checagem externa de uptime nos quatro `https://<dom>/health` (não em
      `/login`), com alerta no mesmo canal
- [x] alerta de disco acima de 80%

### Fase 2 — rollback e sonda certa no `deploy.sh`

- [x] guardar `git rev-parse HEAD` antes do `merge --ff-only`
- [x] trocar a verificação final de `/login` para `/health`, e exigir corpo
      com `"status":"ok"` — não só HTTP 200
- [x] em falha da verificação: `git reset --hard` para o commit guardado,
      `compose up -d --build`, reverificar, e alertar em qualquer desfecho
- [x] `--check` continua não alterando nada
- [x] copiar para o VPS e conferir `sha256sum` dos dois lados (convenção do
      `README.md` deste repositório)

### Fase 3 — defeitos de segurança pontuais

- [x] `ProxyFix(x_for=1, x_proto=1, x_host=1)` no ConfortoTermico, atrás da
      mesma variável de ambiente que os outros dois usam — não incondicional:
      confiar em `X-Forwarded-For` sem proxy na frente é pior que não confiar
- [x] conferir depois: o limitador passa a contar por cliente, e o
      `audit_log` grava o IP real
- [x] `limit_req` no nginx nas rotas de login dos quatro (a proteção contra
      força bruta que sobrevive a deploy e é compartilhada entre workers)
      — instalado e conferido em 2026-08-21
- [x] `default_server` que recusa `Host` desconhecido
      — instalado e conferido em 2026-08-21
- [x] `pip-audit` no CI dos seis
- [x] varredura de imagem (Trivy) no CI dos quatro que constroem imagem
      — e os CVE que ela achou foram fechados. Ver Sessão 8
- [x] `.github/dependabot.yml` no SharedAuth
- [x] `pool_pre_ping` no CRV
- [x] `.env.vps.example` do ConfortoTermico, com `CONFORTO_COOKIE_SEGURO=1`
- [ ] `SECRET_KEY` do ConfortoTermico: falhar alto como os outros três, em
      vez de gerar em silêncio

### Fase 4 — blindar o `db_backend.py` (sem refatorar)

- [ ] trocar a substituição cega de `?` por conversão que respeite literais
      e operadores, **ou** por uma verificação que recuse a consulta ambígua
      em vez de corrompê-la
- [ ] teste que prova a recusa/conversão correta com um `?` de `jsonb`
- [ ] `RETURNING id` no lugar do `SELECT currval(...)`
- [ ] registrar em `AGENTS.md` que a camada é dívida datada, com ponteiro
      para a seção 7 deste plano

### Fase 5 — métricas

- [ ] `/metrics` nos três Flask e no Django
- [ ] agente de envio no VPS (um contêiner pequeno, `remote_write`)
- [ ] **rótulos sem cardinalidade alta e sem dado de usuário**: nada de id de
      usuário, ticker, conta ou id de zona virando rótulo. É custo e é
      privacidade — estes são apps financeiros, e a métrica sai do host
- [ ] painel mínimo: taxa de requisição, taxa de erro, p95 por app
- [ ] alerta de taxa de erro no mesmo canal de D5

### Fase 6 — nginx

- [x] HTTP/2 nos quatro vhosts
- [x] `gzip` para texto
- [ ] **NÃO SERÁ FEITO** — servir estático direto pelo nginx. `/home/ubuntu` é
      750 e o `www-data` não atravessa. As três saídas são piores que o
      problema: `chmod o+x` abre o home inteiro, pôr o `www-data` no grupo
      `ubuntu` dá ao nginx leitura dos **dumps do banco**, e copiar para
      `/var/www` no deploy cria uma segunda cópia que diverge da imagem que
      roda. Para 144–628 KB num sistema de um usuário, nenhuma compensa.
- [x] copiar de volta para `vps/nginx/` neste repositório

### Fase 7 — documentação do bloco 1

- [x] `AGENTS.md` dos afetados
- [x] `README.md` deste repositório: nova linha na tabela de planos
- [x] seção 9 abaixo, com o estado final do bloco 1 (Sessões 1 a 7)

---

## Bloco 2 — interface comum (Fases 8 a 11)

Só começa com o bloco 1 fechado e o alerta funcionando. Ver D6.

### Fase 8 — o componente comum, uma vez

- [x] `sharedauth/ui/`: CSS com as tokens de severidade e os componentes, mais
      um módulo JS sem dependência. **Nada de template de framework aqui**
      (D8) — o projeto de referência é Django e não consome a parte Flask
- [x] expor `sharedauth.ui.CAMINHO_ESTATICO` (um `Path`) para o Django
      adicionar em `STATICFILES_DIRS`. O pacote continua sem importar Django,
      como o núcleo já faz hoje com o Flask
- [x] ponto de partida: `openConfirmModal` do ControleBancario, generalizado —
      severidade como parâmetro, título deixa de ser fixo em exclusão
- [x] quatro severidades com ícone: informação, sucesso, atenção, perigo.
      **Desvio deliberado:** o plano pedia SVG servido como ARQUIVO. O ícone é
      SVG **construído no DOM**, o que é melhor que as duas opções que o plano
      considerou. A preocupação registrada era com `data:` no `img-src`, e ela
      estava certa — mas SVG no documento não é requisição e não passa por
      `img-src` nenhum, além de poupar quatro requisições. Servir como arquivo
      resolveria a CSP e criaria o custo à toa.
      Junto: `error` e `warning` ganharam formas DIFERENTES (círculo com X e
      triângulo). Distinguir severidade só por cor exclui quem não distingue
      vermelho de âmbar — só apareceu ao ver os quatro lado a lado
- [x] toast além do banner, no mesmo vocabulário visual (D7)
- [x] acessibilidade não é opcional num modal: foco preso enquanto aberto,
      `Esc` fecha, foco volta ao gatilho, `aria-modal` e rótulo
- [x] **degradar sem JS**: se o script não carregar, o botão precisa continuar
      submetendo o formulário. Um "confirmar" que engole o clique em silêncio
      é pior que não ter confirmação
- [x] SharedAuth sobe de versão por tag; os quatro apps fixam deliberadamente

### Fase 9 — adotar a confirmação, projeto a projeto

Trabalha sobre a lista da Fase 0b.

- [ ] ControleBancario primeiro: é a origem do componente, então a adoção lá é
      migração e prova que a generalização não perdeu nada
- [ ] MegaSena em seguida: é quem tem os três mecanismos misturados
- [ ] ControleRendaVariavel: troca os 13 `hx-confirm` — atenção, o HTMX cancela
      a requisição pelo retorno do `confirm`; com modal a confirmação é
      assíncrona e o padrão muda (`htmx:confirm` com `evt.preventDefault()`)
- [ ] ConfortoTermico por último
- [ ] cobrir as operações que hoje não têm confirmação nenhuma
- [ ] **regra a valer daqui em diante:** operação irreversível pede
      confirmação; operação reversível não pede. Confirmar tudo treina o
      usuário a clicar "sim" sem ler, e aí a confirmação deixa de proteger

### Fase 10 — mensagens no formato novo

- [ ] `sharedauth/messages` passa a emitir ícone por categoria
- [ ] toast para resultado de ação; banner permanece para o que precisa ficar
      na página
- [ ] os quatro passam a usar o mesmo caminho — hoje o ControleBancario usa
      `messages` do Django e os três Flask usam `flash()`; o formato de saída
      é que precisa convergir, não o mecanismo de cada framework

### Fase 11 — login que herda a paleta

- [ ] os quatro logins deixam de declarar cor própria e passam a consumir as
      tokens do app
- [ ] ControleBancario incluído — hoje o dele está congelado num dos cinco
      temas (Tema F.3); é correção, não só padronização
- [ ] mesma estrutura nos quatro (cartão centrado, campo, rótulo, erro em
      `role="alert"`), cada um com a sua paleta
- [ ] conferir contraste do texto sobre o fundo em cada tema, não só no que o
      desenvolvedor tem aberto na tela
- [ ] documentar em `AGENTS.md` que login não declara cor — herda

---

## 7. Levantado e deliberadamente adiado

Não são pendências esquecidas. São a matéria de rodadas seguintes.

**Rede de testes (pré-requisito da refatoração).** Os `conftest.py` apontam
para `postgresql+psycopg://test:test@localhost:5432/test`, mas **nenhum
workflow de CI sobe um serviço Postgres**. Nada toca banco de verdade no CI,
e portanto **as migrações só são exercitadas a primeira vez em produção**.
Somado: nenhum projeto mede cobertura (`addopts = "-q --tb=short"` nos
quatro, sem `--cov`) — o problema não é o número de testes, é não saber quais
partes não têm nenhum. E `mypy` em lugar nenhum, apesar de type hints
extensivos já escritos: o custo foi pago e a verificação não é colhida.

**Refatoração do `db_backend.py`.** Aposentar o emulador, remover a fachada
de re-export `app/database.py` (~60 nomes que existem só para não tocar os
call sites), migrar para tipos nativos, remover `LinhaCompat`. Exige a rede
de testes acima.

**Cobertura do CRV.** 15 mil linhas de lógica financeira — greeks, risco,
fechamento de posição, ledger — com 113 testes e cobertura desconhecida. É
onde um erro custa dinheiro de verdade.

**Backups.** O `backup-db.sh` é bom: dedupe por LSN, releitura com
`pg_restore --list`, troca atômica, sha256, piso de retenção. O que falta:
os dumps não são criptografados em repouso, ficam no mesmo host que os gera,
e **nunca foram restaurados como teste**. "O dump é legível" não é "o sistema
volta".

**Dimensionamento de pool.** Workers × threads × pool do SQLAlchemy nunca foi
calculado contra o `max_connections` do Postgres (default 100) × 4 bancos.

---

## 8. Riscos

- **`ProxyFix` ligado sem proxy na frente é pior que não ter.** Qualquer
  cliente forja `X-Forwarded-For` e escapa do limitador. Por isso a Fase 3
  o põe atrás de variável de ambiente, como nos outros dois, e não
  incondicional.
- **`limit_req` mal calibrado tranca o próprio dono.** Calibrar contra o
  polling real do ConfortoTermico, não contra um número redondo.
- **Rollback automático pode mascarar um deploy ruim** se ninguém ler o
  alerta. Por isso a Fase 2 exige alerta em qualquer desfecho, inclusive no
  rollback bem-sucedido.
- **A métrica sai do host.** Rótulo com dado de usuário vira vazamento. A
  Fase 5 trata isso como requisito, não como boa prática.
- **Fase 4 mexe em código que roda em produção sem rede de testes de banco.**
  É o motivo de ela blindar e não refatorar.
- **A Fase 9 mexe em submit de formulário nos quatro apps.** É o risco maior
  do bloco 2, e quebra em silêncio: o botão para de enviar e ninguém percebe
  até alguém tentar salvar. É o motivo de o bloco 2 vir depois do bloco 1 —
  com taxa de erro e alerta já de pé, a quebra aparece.
- **Confirmação demais anula a confirmação.** Usuário treinado a clicar "sim"
  sem ler não está protegido por nada. Por isso a regra da Fase 9 é
  irreversível pede, reversível não pede — e não "todo CRUD pede".
- **Ícone embutido como `data:` estouraria a CSP.** Dois dos quatro fecham
  `img-src` em `'self'`; abrir para todos seria a união das políticas, que o
  plano anterior recusou explicitamente. Por isso SVG servido como arquivo.
- **Modal sem tratamento de foco é regressão de acessibilidade** em relação ao
  `window.confirm` que ele substitui — o nativo já prende o foco de graça.

---

## 9. Log de sessões

### Sessão 1 — 2026-08-21

Levantamento independente dos seis repositórios, lendo código e não os
planos anteriores, a pedido do mantenedor: ele suspeitava que fases pensadas
isoladamente tivessem deixado restrições acidentais. A suspeita se confirmou,
mas não na forma esperada — o limite não estava escrito em documento nenhum,
estava no *formato convergente* do trabalho (seção 1).

Decisões D1 a D4 tomadas. Nenhum código alterado ainda.

Na sequência da mesma conversa o mantenedor aprovou o plano, escolheu o
Telegram (D5) e trouxe três pedidos de interface: confirmação de CRUD, padrão
de mensagem e padrão de login. Levantados no Tema F, decididos em D6 a D8, e
transformados nas Fases 8 a 11 — um segundo bloco, depois do primeiro.

Dois achados do Tema F merecem destaque porque mudam o trabalho em relação ao
pedido original:

1. O componente de confirmação que o mantenedor descreveu **já existe** no
   ControleBancario. O trabalho é generalizar e compartilhar, não criar.
2. A harmonização de cor do login que ele elogiou **não é herança, é cópia
   manual**, e está congelada num dos cinco temas do próprio projeto. O
   ControleBancario entra na Fase 11 como corrigendo, não como modelo a copiar.

### Sessão 2 — 2026-08-21 — Fase 0 concluída, Fase 1 em curso

**Fase 0 — o levantamento no VPS.** Conferido por SSH, tudo leitura:

| Item | Achado |
|---|---|
| Máquina | Ampere A1, **2 vCPU / 11 GiB**, aarch64, sem swap |
| Disco | 193 GB, **6% usados** — folga grande |
| Cache de build | **5,8 GB, 4,7 GB recuperáveis, 263 entradas** — a acumulação prevista por construir no servidor. Não é urgente com 6% de disco, mas cresce sem teto |
| nginx | **1.24.0** |
| Contêineres | 9, todos `healthy` |
| Backups | ciclo de hoje 06:00Z limpo, quatro dumps gravados e conferidos |
| `OnFailure=` | **nenhum em nenhuma unidade do host**, como previsto |
| Tamanho dos bancos | dumps de **44 KB a 216 KB** |

Quatro consequências que corrigem ou reordenam o que estava escrito:

1. **`http2 on;` não serve.** É diretiva do nginx 1.25.1 em diante; aqui é
   1.24.0. A Fase 6 usa `listen 443 ssl http2;`. Foi para achar isso que a
   Fase 0 existe.
2. **Os limites de `cpus:` do Compose são decorativos.** Somados dão ~12,5
   CPUs numa máquina de 2. Limite não é reserva: sob disputa, nenhum serviço
   está protegido de nenhum outro. Memória está sã (~5,9 GiB declarados em 11).
3. **O eixo de performance encolhe.** Com dumps na casa das centenas de
   quilobytes, quase tudo que foi levantado ali é teórico. O que continua
   valendo é o que independe de volume: HTTP/2, estático fora do Python,
   compressão. O resto desce de prioridade — e fica dito.
4. **Testar restauração é barato.** Restaurar 216 KB não custa nada; a seção 7
   perde a única desculpa que tinha.

Observado de graça: o `unified-monitoring-agent` da Oracle já está instalado e
rodando. O OCI Monitoring dá métrica de host (CPU, memória, disco) e alarme
sem custo — pode cobrir a parte de host da Fase 1 e do alerta de disco, e
deixar o `/metrics` da Fase 5 só para o nível de aplicação. **Decisão a tomar
com o mantenedor antes da Fase 5.**

**Fase 1 — feito até aqui:**

- `alerta.sh` e `alerta@.service` escritos, instalados e versionados em `vps/`
- caminho validado em dois níveis: envio manual (`--teste`) e **falha real de
  unidade** — uma unidade descartável com `OnFailure=` foi feita falhar de
  propósito, o alerta disparou com nome da unidade e log anexado, e a unidade
  foi removida em seguida
- `OnFailure=` ligado em `backup-db.service` (edição direta, arquivo é nosso)
  e em `certbot.service` **por drop-in** em
  `/etc/systemd/system/certbot.service.d/alerta.conf` — o arquivo do certbot
  é do pacote e o apt o sobrescreveria
- `sha256sum` dos quatro arquivos conferido nos dois lados: idênticos

Decisões de projeto do `alerta.sh`, todas por um motivo:

- **nunca sai com código diferente de zero** — é alvo de `OnFailure=`; se
  falhasse, a notificação viraria o segundo incidente
- **token entra no `curl` por `--config -`**, não como argumento, que
  apareceria em `ps` para qualquer processo do host
- **sem `parse_mode`** — a mensagem carrega linha de log, e um `<` faria o
  Telegram recusar a mensagem inteira justamente quando ela mais importa
- **antirrepetição de 15 minutos por título** — contêiner que oscila apitaria
  a cada verificação, e canal que apita demais é canal que se silencia

### Sessão 3 — 2026-08-21 — Fase 1 fechada, e o defeito que ela revelou

**D9 — o OCI não roteia para o Telegram.** As Notifications da Oracle só têm
alvo Email, HTTPS, Slack, SMS e PagerDuty. Mandar o alerta de disco por lá
daria host por e-mail e aplicação por Telegram — dois canais, e o que apita
menos vira o que ninguém lê. Fica: **OCI como painel gratuito de histórico de
host** (já coleta, zero trabalho), **todo alerta pelo `alerta.sh`**. Isso
mantém o alerta de disco no `vigia.sh`, e não no OCI como se cogitou antes.

**Buraco do `OnFailure=`, fechado.** Ele só dispara se o serviço *rodar e
falhar*. Timer desabilitado por engano, systemd que não disparou, máquina
desligada na hora — em nenhum desses casos existe falha para notificar, e o
backup para em silêncio. Só a **idade do último backup** detecta isso; virou
verificação no `vigia.sh`, com teto de 36h.

**Entregue e validado:**

| Peça | Prova |
|---|---|
| `autocura.sh` + timer de 5 min | contêiner descartável com sonda que sempre falha: ficou `unhealthy`, foi reiniciado, alertou |
| teto de 3 tentativas | forçado o contador ao teto: recusou o segundo reinício (`StartedAt` inalterado) e alertou "sem cura" |
| `vigia.sh` + timer horário | ensaio `--estado` nos quatro domínios, disco, certificado e frescor de backup |
| `ALERTA_JANELA` | janela de repetição virou parâmetro: 15 min para falha aguda, 6h para condição que dura horas |
| 10 arquivos | `sha256sum` idêntico nos dois lados |

Produção não foi tocada em nenhum momento do teste: o contêiner de ensaio foi
criado, exercitado e removido, e os nove de produção seguiram `healthy`.

**O defeito que o ensaio revelou — ControleBancario reportava saúde falsa.**

O primeiro `vigia.sh --estado` acusou `bancario-mspa.duckdns.org` com HTTP
301. Duas camadas de problema apareceram ao puxar o fio:

1. **Barra final.** Os três Flask servem `/health`; o Django servia só
   `/health/`, e o `APPEND_SLASH` respondia 301 ao caminho sem barra. Vigia
   que não segue redirecionamento marcaria o projeto como fora do ar.
2. **O grave:** `financeiro/urls.py` devolvia `HttpResponse("ok")` **fixo,
   sem tocar no banco**. É letra por letra o defeito que o `sharedauth.health`
   documenta ter corrigido no MegaSena — o `healthcheck:` do Compose bate
   nessa rota, então o Docker marcava o contêiner saudável com o PostgreSQL
   inteiramente fora.

A rodada que unificou o `/health` cobriu os três Flask e **deixou o Django com
o defeito idêntico** — ele instala o SharedAuth sem o extra `[flask]`, e
`registrar_health` depende de `flask.jsonify`. É o Tema F.3 de novo em outra
roupa: o compartilhado parou na fronteira do framework.

Corrigido: a view consulta o banco, responde 503 com `status: "erro"` quando
não consegue, e o formato de resposta passa a ser idêntico ao dos outros três.
Rota sem barra acrescentada.

**A suíte Django não toca banco por desenho**, e `/health/` era o alvo dos
testes de cabeçalho justamente por isso. Em vez de afrouxar a asserção,
entraram duas fixtures (`banco_sondavel`, `banco_fora`) que simulam os dois
desfechos sem banco. O saldo é **mais** cobertura: agora existe teste do ramo
503, que era exatamente o caso que ninguém verificava. `ruff` limpo e **83
testes passando** na imagem `quality`.

**Pendente de implantação:** a correção está só na cópia local. Até ela subir,
o `vigia.sh` alerta `FORA DO AR: bancario` a cada 6h — e está certo: a
produção de fato não cumpre o contrato. Commit e push aguardam autorização.

**Implantado.** O mantenedor autorizou; seguido o fluxo do projeto (branch →
PR → squash merge), que o histórico confirma ser o de sempre — nenhum commit
vai direto para `main`. PR #25, CI verde em 1m15s, mesclado como `2f485a6`,
`./deploy.sh bancario` concluído. As duas rotas respondem 200 com o corpo
certo em produção.

**Um bug meu, achado pelo próprio ensaio.** Depois da implantação o vigia
*ainda* reprovava o ControleBancario. O `jsonify` do Flask serializa compacto
(`"status":"ok"`) e o `JsonResponse` do Django põe espaço
(`"status": "ok"`); meu padrão era texto literal. Espaço em JSON não é parte
de contrato nenhum — quem tem de ser tolerante é o verificador. Virou regex.
Ciclo real seguinte: **0 alertas**, quatro domínios ok, certificados com 87
dias, backups frescos.

Fica a lição de método: **rodar `--estado` depois da correção**, não presumir
que corrigir a causa relatada encerra o assunto. O primeiro ensaio achou o
defeito da aplicação; o segundo achou o defeito do verificador.

**Falta da Fase 1:** só a checagem externa de uptime, que exige conta em
serviço de fora. O `vigia.sh` cobre mais do que parecia — como bate na URL
pública, atravessa DNS (inclusive o DuckDNS), TLS, nginx, aplicação e banco.
O que ele não pode cobrir é o VPS inteiro inalcançável, porque roda dentro
dele.

**Princípio:** o alerta externo sai por um canal *diferente* do Telegram. A
regra de canal único vale para o que o VPS relata sobre si; o vigia de fora
existe justamente para funcionar quando o primeiro canal está morto, e
repeti-lo herdaria a mesma falha. É a única exceção deliberada.

### Sessão 4 — 2026-08-21 — vigia externo, Fase 1 fechada

Conta gratuita criada pelo mantenedor (a única etapa que não podia ser
delegada). Chave em `/home/ubuntu/.secrets/uptimerobot.env`, 600, mesmo padrão
do Telegram — nunca passou por conversa. Script em
`vps/uptimerobot-monitores.sh`, com `--estado` e `--aplicar` idempotente.

**D10 — intervalo de 12h, por decisão do mantenedor.** O piso não custaria
nada; o número é escolha de tempo de descoberta. Registrada a informação
contraintuitiva que fundamenta a escolha: o UptimeRobot notifica em *mudança
de estado*, não a cada verificação — baixar o intervalo não aumenta o número
de mensagens, só antecipa as mesmas.

**A v2 não serve nesta conta.** Recusa *qualquer* criação de monitor —
inclusive HTTP simples no intervalo mínimo — com
`access_denied: not allowed to use some settings with your current plan`.
Isolado variando um parâmetro por vez, não presumido. A v3 aceita a mesma
chave como Bearer e cria sem reclamar.

**O esquema do POST veio de sondagem, não de documentação.** A página pública
da v3 não traz o corpo do POST. Um `POST {}` proposital devolve a validação
completa, e um valor inválido em `keywordType` devolve o enum aceito
(`ALERT_EXISTS`, `ALERT_NOT_EXISTS`). É mais confiável que memória e mais
rápido que caçar documentação.

**Tipo não pode mudar depois de criado.** O monitor que o cadastro gerou era
HTTP simples — aprovaria um 503. Foi apagado e recriado como KEYWORD; o script
faz isso sozinho e explica o porquê no lugar em que decide.

**Polaridade verificada empiricamente, e essa é a parte que importa.** Um
`ALERT_NOT_EXISTS` invertido seria pior que monitor nenhum: alertaria com tudo
bem e ficaria calado na queda. Sonda descartável apontada para uma URL
comprovadamente boa com uma palavra comprovadamente ausente ficou **DOWN em
~80s** — sentido correto, e de quebra provou o caminho até o e-mail. Sonda
apagada em seguida.

Estado final: quatro monitores KEYWORD, `"ok"`, `ALERT_NOT_EXISTS`,
`CaseSensitive`, contato de alerta ligado, todos **UP**. `sha256sum` do script
idêntico dos dois lados.

**Dois erros meus no caminho, ambos achados por conferir em vez de presumir:**

1. Uma função `chamar()` escrita direto na linha do `ssh` expandiu
   `${3:+--data-binary "$3"}` sem aspas e mandou JSON quebrado; o `id` voltou
   vazio e o `DELETE` seguinte foi para `/monitors/` sem id. **Conferi os
   quatro monitores imediatamente** — intactos. Lição: script vai para arquivo
   e é copiado, nunca montado dentro do comando remoto.
2. A segunda tentativa usou aspas simples dentro de um comando `ssh` já entre
   aspas simples, e o shell as comeu. Mesmo remédio.

**Fase 1 fechada.** Sinal de falha, auto-cura, vigia interno e vigia externo,
todos testados com falha real e não só com envio manual.

### Sessão 5 — 2026-08-21 — Fase 0b de verdade, Fase 2 fechada, Fase 3 em curso

**A Fase 0b estava dada como feita e não estava.** O que existia era a medição
agregada do Tema F. Virou inventário item a item — 124 operações nos quatro
aplicativos, em [INVENTARIO_OPERACOES_DESTRUTIVAS.md](INVENTARIO_OPERACOES_DESTRUTIVAS.md),
levantado por quatro agentes em paralelo, um por projeto.

Lição de método que vale além desta fase: **contar ocorrências de atributo mede
o código, não a cobertura.** O `grep` dizia que o MegaSena tinha "2 + 2 + 3"
confirmações; o inventário mostrou dois mecanismos redundantes sobre os mesmos
dois botões. Eram 2, não 7 — e a tabela do Tema F foi corrigida.

**Seis casos graves, todos corrigidos e implantados no mesmo dia** (irreversível
e sem confirmação nenhuma):

| Projeto | Caso | PR |
|---|---|---|
| CRV | encerrar posição (ação e opção) apaga o extrato em cascata | #22 |
| CRV | editar posição trocando a carteira para Simulada apaga o extrato | #22 |
| CRV | atualizar cotações sobrescreve lançamento manual | #22 |
| Bancário | editar "este e os próximos" apaga comprovante por CASCADE | #27 |
| MegaSena | importar planilha sobrescreve concurso já cadastrado | #30 |
| ConfortoTermico | `/api/reset` apagava a série temporal com trava só no front | #21 |

O pior não é o maior: o do **CRV com a carteira Simulada** é destruição de
histórico com aparência de edição rotineira — o usuário escolhe uma opção num
`<select>`, clica em Salvar e lê "Posição atualizada."

Três armadilhas encontradas por conferir em vez de presumir, todas do tipo que
teria produzido uma proteção *aparente*:

1. `hx-confirm` só dispara em requisição do HTMX. Em `<form method="post">`
   comum ele é ignorado em silêncio — pareceria protegido e não estaria.
2. `hx-boost` num form cascateia para os `<a>` dentro dele, e a busca de
   `hx-confirm` sobe pelos ancestrais: os links "Cancelar" e "Transações"
   passariam a exigir a confirmação de destruição só para navegar. Resolvido com
   `hx-boost="false"` nos links.
3. No ControleBancario, o `_initDynamicConfirmButtons` genérico liga o listener
   uma vez e depois confirma incondicionalmente — não expressa condição que muda
   depois de ligado — e não é reexecutado no swap htmx da tabela, então pararia
   de confirmar depois do primeiro filtro.

**Fase 2 fechada, com o rollback provado por falha real.** Uma cópia descartável
do `deploy.sh` reprovando de propósito a primeira verificação foi rodada contra
o MegaSena: mesclou, reconstruiu, reprovou, voltou para o commit anterior,
reconstruiu de novo, verificou e alertou. Só o veredito era falso; merge,
rebuild, `git reset --hard` e Telegram foram reais.

**Um erro meu, achado por medir.** A poda de cache que escrevi filtrava por
idade (`until=168h`) e não podava nada: com deploys frequentes nenhuma entrada
chega a ter uma semana, e o cache subiu de 5,8 para 6,8 GB com a poda ligada.
Trocado por teto de tamanho (`--max-used-space 3GB`), que liberou 2,6 GB. Idade
mede quando a camada nasceu; o que interessa é quanto disco ela ocupa.

**Fase 6 decidida pelo que o sistema de arquivos permite, não pelo checklist.**
O item "servir estático direto pelo nginx" **não será feito**, e a razão é
concreta: `/home/ubuntu` é 750 e o nginx (`www-data`) não atravessa. As três
saídas são piores que o problema — `chmod o+x` abre o home inteiro,
`usermod -aG ubuntu www-data` daria ao nginx leitura dos **dumps do banco**, e
copiar para `/var/www` no deploy cria uma segunda cópia que pode divergir da
imagem que está rodando. Para 144–628 KB de estático num sistema de um usuário,
nenhuma compensa. O estático sai do Python por cache no navegador
(`SEND_FILE_MAX_AGE_DEFAULT`), não por permissão de arquivo.

**Dois números do Tema E também estavam errados**, conferidos no servidor:
o `default_server` **existe** na porta 80 (vem no site `default` do pacote do
Ubuntu) — o buraco é só na 443; e o `gzip on;` **já está ligado** no
`nginx.conf`, mas com `gzip_types` comentado, e o padrão do nginx nesse caso é
comprimir só `text/html`. Estava ligado e não comprimia CSS nem JS.

**Achado que muda a leitura do caso grave 6.** O botão "Limpar histórico" do
ConfortoTermico é invisível desde sempre: nasce com a classe `oculto` e nem
`moverCampo` nem `moverCheck` a removem. Vale também para `cfg-sons`,
`cfg-emails` e `wrap-email-destino`. Logo `/api/reset` **não tem interface** — a
trava de servidor que entrou hoje é a única proteção que existe, e não uma
segunda camada. Não corrigido de propósito: revelar `cfg-emails` pode disparar
e-mail sem SMTP conferido, e revelar `btn-limpar` acrescenta à tela um botão que
apaga tudo. É decisão de produto.

**Pendente por permissão, não por trabalho.** A configuração nova do nginx está
escrita, com estrutura idêntica nos quatro vhosts, e copiada para
`/home/ubuntu/nginx/` no VPS — mas a instalação exige `sudo` em `/etc/nginx`, que o
ambiente desta sessão bloqueia. Falta rodar `~/instalar-nginx.sh`, que faz
backup, valida com `nginx -t` e **restaura sozinho sem recarregar** se reprovar.

### Sessão 6 — 2026-08-21 — Fase 3, e três camadas de uma correção que não funcionava

Cinco agentes da Fase 3 morreram no limite de sessão, dois deles com trabalho
parcial aproveitável. O resto foi feito diretamente, o que se mostrou mais
barato: remontar contexto num agente novo custa mais que executar.

**Entregue e implantado:** `pip-audit` no CI dos **seis** repositórios,
`dependabot.yml` e CI endurecido no SharedAuth (era o único sem dependabot e o
menos vigiado dos seis, sendo o único ponto de cadeia de suprimento do
conjunto), `pool_pre_ping` no CRV, `.env.vps.example` e `ProxyFix` no
ConfortoTermico.

**A lição da sessão: uma correção de segurança que passou em tudo e não fazia
nada.** O `ProxyFix` foi implantado e o `audit_log` continuou gravando
`172.21.0.1`, o gateway do Docker. Foram **três** camadas de falha empilhadas,
e cada uma teria bastado sozinha para anular a proteção:

1. **A variável não chegava ao contêiner.** O `--env-file` do Compose serve
   para INTERPOLAR `${VAR}` no `compose.yaml`; ele não injeta nada no
   contêiner. Só chega ao processo o que está listado no `environment:` do
   serviço.
2. **O waitress apagava o cabeçalho.** O waitress 3.0.2 vem com
   `clear_untrusted_proxy_headers=True` e `trusted_proxy=None`: remove os
   `X-Forwarded-*` antes de montar o environ, e o `ProxyFix` recebia um
   environ já limpo. Os outros três projetos usam gunicorn, que não toca
   nesses cabeçalhos — **copiar o padrão do irmão para um servidor diferente**
   foi o que produziu a correção inerte.
3. **Meu próprio teste era inválido.** Usei `app.request_context(env)` para
   verificar, e ele monta a requisição direto do environ, sem passar pelo
   middleware. Nunca poderia mostrar o efeito do `ProxyFix`.

O que salvou foi a Fase 3 exigir, como item próprio, *"conferir depois: o
limitador passa a contar por cliente e o `audit_log` grava o IP real"*. Sem
esse item eu teria reportado três vezes uma entrega que não existia. **Item de
verificação no plano vale mais que o item de implementação.**

Verificado ao fim com requisição real e marcador único: `"ip": "177.96.64.76"`,
o IP público de verdade. Como o `flask-limiter` usa a mesma
`request.remote_addr`, o limitador passou a contar por cliente no mesmo ato.

**Efeito colateral que é ganho, não regressão.** Com o `x-forwarded-proto`
finalmente chegando, a aplicação passou a saber que está sendo servida por
HTTPS — e a verificação de referrer do CSRF, que só vale em requisição segura,
saiu do estado desligado em que estava sem ninguém notar. Navegador manda
`Referer` em POST de mesma origem, então o uso normal não muda; um cliente que
não mande passa a levar 400.

**Trivy adiado, com motivo.** A varredura de imagem precisa de um nome de
imagem determinístico para apontar. Três dos quatro `compose.yaml` não
declaram `image:` no serviço servido, e o nome sai derivado do diretório.
Acertar isso significa mexer no `compose.yaml` dos três e trocar o nome das
imagens em produção — mudança de blast radius maior que o item, e que merece
rodada própria em vez de ser embutida aqui.

### Sessão 7 — 2026-08-21 — nginx no ar, Fase 4, chave de sessão, e o Trivy achando coisa

**nginx instalado e conferido no ato**, não só recarregado: HTTP/2 negociado
nos quatro domínios, `content-encoding: gzip` num `.js` real, `Host`
desconhecido recusado no aperto de mão TLS, e o `limit_req` deixando **12 de 12
`GET /login`** passarem enquanto o `POST` cai para 429 depois do estouro — o
`map` que zera a chave em não-POST existia justamente para recarregar a tela de
login não virar bloqueio, e funciona. Fecha `limit_req` e `default_server` da
Fase 3, e HTTP/2 e gzip da Fase 6.

**Fase 4 fechada, e um item dela foi recusado com base em medição.** O plano
pedia `RETURNING id` no lugar do `SELECT currval(...)`. Conferido o esquema:
**8 das 18 tabelas não têm coluna `id`**, e várias são alvo de INSERT
(`configuracoes_zona`, `controle_zonas`, `estado_equipamentos`,
`agregados_15min`). Acrescentar `RETURNING id` a todo INSERT transformaria
upserts que funcionam em erro de SQL, para economizar um round trip num sistema
cujos dumps inteiros têm centenas de quilobytes. O defeito *real* do `currval`
— devolver o id de outra linha quando nada foi inserido — foi fechado com uma
guarda de `rowcount`, sem tocar no esquema.

O item principal foi feito: a substituição cega de `?` por `%s` virou um
percorredor que respeita literal, identificador citado, literal com cifrão,
comentário de linha e de bloco (que aninham no PostgreSQL) e os operadores
`?|`/`?&` de jsonb. E conta os marcadores convertidos: se não baterem com os
parâmetros, recusa com a causa provável e a saída (`jsonb_exists`). 12 testes.

**A ADR 005 foi substituída, não atropelada.** A chave de sessão gerada em
silêncio estava registrada como decisão consciente, com um motivo concreto: "o
Compose não fornece uma chave de sessão como Docker secret dedicado". O motivo
deixou de valer. A própria ADR 005 dizia o que a evolução exigiria — migração
coordenada, compatibilidade temporária e rollback documentado — e a ADR 007 faz
as três. **Ninguém foi deslogado**: o arquivo de segredo foi semeado com a
chave que já estava no volume, dentro do próprio servidor, `sha256` conferido
idêntico. Muda de *onde* a chave vem, não *qual* chave é.

**O Trivy funciona, e por isso as PRs estão vermelhas.**

Duas coisas foram aprendidas antes de ele rodar:

1. **A action de marketplace é barrada.** As quatro PRs falharam com
   `startup_failure` e zero log — não era o YAML. A política destes
   repositórios é `allowed_actions: selected` com `github_owned_allowed: true`,
   `verified_allowed: false` e `patterns_allowed: []`: só actions da própria
   GitHub. Conformar-se a isso é melhor que afrouxá-la para caber uma
   ferramenta, então o Trivy roda como **contêiner**, com `docker save` +
   `--input` em vez de montar `/var/run/docker.sock` — montar o socket é dar
   root na prática, que foi exatamente o motivo de o `autoheal` ter sido
   recusado na Fase 1.
2. **A varredura precisa de nome de imagem determinístico.** Três dos quatro
   `compose.yaml` não declaravam `image:`, e o Compose batizava a imagem pelo
   nome do diretório — um nome no CI, outro no VPS. Isso também exigiu corrigir
   uma linha do CI do ControleBancario que procurava o nome derivado.

E aí ele achou, na primeira execução:

| Pacote | Instalado | Corrigido em | |
|---|---|---|---|
| `setuptools` | 70.3.0 | 78.1.1 | CVE-2025-47273, travessia de caminho |
| `msgpack` | 1.1.2 | 1.2.1 | GHSA-6v7p-g79w-8964 |
| `util-linux` (Debian) | — | — | CVE-2026-53614/53615 |

O `apt-get upgrade` no estágio `base` **fechou toda a parte de sistema
operacional** nos quatro. O que sobrou são dois pacotes Python, e fechá-los não
é uma linha: cada projeto monta a imagem de um jeito diferente — o MegaSena usa
`/opt/venv` (que ganha cópia própria do `setuptools` ao ser criado), o
ControleBancario faz `COPY --from=runtime-dependencies /install /usr/local`
(que sobrescreve o `setuptools` corrigido na base), e o `msgpack` é transitivo
em todos.

**As quatro PRs ficam ABERTAS e vermelhas**, de propósito. Mesclar vermelho
ensina a ignorar o vermelho, e baixar o `--exit-code` para 0 seria instalar um
alarme desligado — os dois erros que este plano inteiro existe para não
cometer. Produção não está pior do que ontem: os CVE já estavam lá, a diferença
é que agora alguém sabe.

Fechá-los é a próxima rodada, e é trabalho de imagem, não de varredura.

### Sessão 8 — 2026-08-21 — os CVE fechados, e bloco 1 concluído

As quatro PRs do Trivy estão verdes e implantadas. A correção não foi subir
versão de pacote — foi descobrir que **nenhum dos dois pacotes precisava estar
na imagem servida**:

- o `msgpack` acusado é o que o **próprio `pip`** carrega vendorizado em
  `pip/_vendor/`, não dependência de ninguém;
- o `setuptools` foi **introduzido pela minha correção anterior**. Conferido nos
  quatro contêineres em produção: eles já rodavam sem ele.

Então `pip` e `setuptools` saíram da imagem servida. É o mesmo raciocínio que
já mantém `gcc`, `make` e `wget` fora do runtime — coisa que os testes de
contrato destes projetos verificam há rodadas. A última linha do `RUN` é a
própria verificação: se `pip` continuar no PATH, o build falha ali em vez de
entregar uma imagem que só *parece* limpa.

**Cinco defeitos apareceram no caminho, e os testes de contrato pegaram dois
deles.** Vale listar porque todos são da mesma família — mexer no nome de uma
imagem quebra quem a procurava pelo nome antigo:

| Onde | O que quebrou |
|---|---|
| ConfortoTermico | só o serviço `schema` tem `build:`; `docker compose build ict` era no-op e a tag nunca existia |
| ControleBancario | com `image:` no âncora, `compose config --images \| grep -x` passou a devolver duas linhas e o `docker run` recebeu ref inválida |
| ControleRendaVariavel | o contrato inspecionava `controle-renda-variavel-web`, nome derivado que deixou de existir |
| MegaSena | o `quality` chamava `pip` direto; `python -m pip` funciona só com o módulo, que é o que o `ensurepip` garante |
| **todos** | removi o `_distutils_hack` e **deixei o `.pth` que o carrega** — o Python passaria a imprimir traceback a cada início. Pego pelo contrato do ControleBancario |

O último é o mais instrutivo: a imagem *funcionaria*, e sujaria todo log de
produção com um erro que não aponta para a causa. Nenhum teste de aplicação
pegaria isso; o teste de contrato pegou.

E o `python -m pip check`, que o contrato rodava na imagem servida, não foi
descartado — foi para o **build**, logo antes da remoção. Verificar antes de
remover a ferramenta é melhor que verificar depois de perdê-la.

**Verificado em produção nos quatro:** `pip=ausente`, `setuptools=ausente`,
diretório do `pip` inexistente, e o interpretador subindo sem reclamar de
`.pth`. Os quatro respondem 200 com `"status":"ok"`.

**Bloco 1 concluído.** Fica pendente, por decisão registrada: a Fase 5
(métricas) e o bloco 2 (interface, fases 8 a 11). A lista de trabalho da Fase 9
já está pronta em
[INVENTARIO_OPERACOES_DESTRUTIVAS.md](INVENTARIO_OPERACOES_DESTRUTIVAS.md).

### Sessão 9 — 2026-08-21 — bloco 2: Fase 8 pronta, ConfortoTermico adotado

**Fase 8 concluída e publicada como tag `v0.3.0`.** O componente comum de
confirmação e aviso está no `sharedauth.ui`: CSS e JS puro, sem template de
framework, porque o projeto de referência é Django e instala o pacote sem o
extra `[flask]`. Foi assim que o `messages` e o `/health` unificado pararam na
fronteira do framework; desta vez a fronteira foi o ponto de partida do
desenho, não a descoberta do fim.

**Validado no navegador antes de liberar**, e foi essa validação que pegou duas
coisas que teste nenhum mostraria:

1. `error` e `warning` usavam o **mesmo triângulo**, distinguidos só pela cor.
   Quem não distingue vermelho de âmbar não distinguiria perigo de atenção. O
   erro ganhou círculo com X — forma, não só cor.
2. Confirmado ao vivo que o `submitter` chega ao servidor (`name`/`value` do
   botão clicado), que o `Esc` cancela sem enviar, que o foco volta ao gatilho
   e que a rolagem destrava.

Uma duplicação inevitável virou invariante conferido: o traçado do ícone existe
em Python (banner do servidor) e em JavaScript (modal e toast), porque o JS não
importa Python. Um teste extrai o traçado do JS e compara com o dicionário
Python. De passagem apareceu que a versão estava declarada em dois lugares
(`pyproject.toml` e `__init__.py`) e **já tinha divergido**; agora um teste
confere as duas.

**ConfortoTermico: fases 9, 10 e 11 prontas** (PR #28). Dois defeitos achados
na revisão, os dois da mesma família — proteção que parece existir e não
existe:

- duas chamadas tinham ficado no `window.confirm` **nativo** recebendo objeto
  de opções, o que mostra `[object Object]`. Escapou da autoverificação porque
  ela procurou chamadas *sem* `await`, e estas tinham `await`;
- `usuarios.html` usava `onsubmit="return confirm(...)"`, e a CSP do projeto é
  `script-src 'self'` sem `unsafe-inline` nem nonce: **aquele confirm nunca
  disparava**. Excluir usuário vinha sendo enviado sem confirmação alguma desde
  que a CSP fechou, e passou despercebido porque era o único handler inline do
  projeto — não havia um segundo caso quebrado para chamar atenção.

Uma confirmação foi **removida** de propósito: comandar atuador. Ligar um
nebulizador é reversível, basta desligar. A Fase 11 ali não teve trabalho: o
login já consumia as tokens do app, com contraste de ~9,5:1.

**Lição de método sobre agentes.** Duas rodadas de quatro agentes em paralelo
morreram no limite de uso, e agentes interrompidos **não deixam nada** — param
na fase de leitura e a árvore fica limpa. A partir daqui: um agente por vez, e
commit assim que cada um entrega, para que a interrupção custe um projeto e não
quatro.
