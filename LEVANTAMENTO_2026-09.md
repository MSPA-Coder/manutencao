# Levantamento em profundidade — setembro/2026

Oito repositórios, cinco aplicações em produção, uma biblioteca compartilhada,
um utilitário de host e a infraestrutura do VPS. O pedido não foi caçar bugs:
foi julgar se as escolhas se sustentam e o que fazer, em fases, sem
funcionalidade nova.

- **Data:** 07/09/2026 · revisado no mesmo dia com as decisões do mantenedor
  (§2).
- **Escopo:** `mega-sena`, `sistema-financeiro` (ControleBancario),
  `ControleRendaVariavel`, `mp-solucoes`, `SharedAuth`, `BackupRestore`,
  `manutencao` — e o `Sistema-de-Controle-de-Indice-de-Conforto-Termico` em
  trilha separada (§7).
- **Apetite declarado:** endurecer o que existe; trocar tecnologia quando
  compensar; rever processo. **Fora de escopo por decisão:** trocar
  hospedagem ou infraestrutura.
- **Horizonte do site:** vitrine + contato agora; portal com área de cliente
  em algumas semanas.

---

## 1. Veredito

**As escolhas estão certas. O que falta não é tecnologia — é prova.**

Python, Flask, Django, PostgreSQL, Docker, nginx e um VPS. Para aplicações de
baixo volume mantidas por uma pessoa, não existe pilha melhor disponível;
existem pilhas diferentes, todas mais caras de operar. Nada aqui recomenda
reescrever coisa alguma.

O que este levantamento encontrou é outra coisa, e é consistente nos oito
repositórios: **um conjunto de invariantes escritos com muito cuidado e quase
nenhum mecanismo automático que os verifique.**

Os documentos declaram atomicidade, transação delimitada no caso de uso,
fechamento mensal que bloqueia mutação, idempotência da projeção recorrente,
preço médio não-negativo, importação de XLSX atômica. O código, onde eu li,
faz exatamente isso — e faz bem. Mas **nenhuma das aplicações tem um único
teste automatizado que rode contra um banco de dados**. As suítes recusam a
conexão de propósito, e está escrito no `conftest.py` de cada uma.

Ponto de precisão, porque a frase é fácil de ler errado: as aplicações **são**
PostgreSQL — em produção, no Compose e no desenvolvimento. O que falta é o
banco na **suíte de testes**. No `compose.yaml` do ControleBancario o serviço
`postgres` está declarado na linha 70; o serviço `quality`, na linha 160, não
tem `depends_on` para ele e roda isolado.

A consequência não é hipotética. Ela é o encadeamento que fecha o sistema:

> A CI não consegue reprovar uma migração ruim, porque ela nunca aplica
> migração. O `deploy.sh` aplica essa migração em produção. E o rollback
> automático — que é bom, e é raro alguém ter — reverte código e imagem, mas
> **não reverte migração**. Está escrito no próprio script.

Esse é o achado central, e é o único item do plano com prioridade máxima.

### O que está genuinamente bem

Não é elogio de praxe; é a linha de base contra a qual o resto é medido.

- Segurança de aplicação auditada duas vezes, sem achado crítico ou alto em
  aberto. SQL parametrizado, sem `eval`/`exec`/`pickle`, `next=` validado,
  `hmac.compare_digest`, segredo por arquivo, CSP sem `unsafe-inline`.
- Contêineres endurecidos de forma uniforme: não-root, `read_only`,
  `cap_drop`, `no-new-privileges`, `mem_limit`, healthcheck, Postgres só em
  loopback.
- CI com portão real: Ruff, pytest, `pip-audit` no ambiente instalado, Trivy
  na imagem servida por `docker save` (sem montar o socket do Docker), actions
  fixadas por SHA, ruleset ativo exigindo `Qualidade` + `CodeQL`.
- Deploy com fast-forward, sonda `/health` pública (atravessa DNS, TLS, nginx,
  app e banco) e rollback automático com registro atômico do último SHA
  saudável.
- Operação com vigia horário (disco, saúde, certificado, frescor de backup),
  autocura com teto, alerta por Telegram, monitor externo independente do VPS
  e poda semanal de cache.
- Backup diário verificado por releitura, publicado por troca atômica, com
  SHA-256 e retenção que nunca remove o último artefato válido — mais uma
  Camada 2 que traz os dumps para fora do VPS.
- `SharedAuth` com fronteira arquitetural escrita, critérios de entrada
  explícitos e um teste que guarda a importabilidade sem Flask.
- Os quatro consumidores fixados na **mesma** tag `v0.11.0`. Sem deriva.

Isto está acima da média larga do mercado. O que segue são refinamentos de um
sistema bom, não conserto de um sistema ruim.

---

## 2. Decisões do mantenedor

A primeira versão deste documento propôs oito fases. Estas são as decisões
tomadas sobre elas, e o restante do documento já está reescrito de acordo.

| Item | Decisão | Efeito |
|---|---|---|
| **F2** — backup de mídia e ensaio de RTO | **Não por enquanto** | Fase adiada; risco registrado em §6 |
| **L05** — `media_volume` sem backup | **Continua sem backup** | Risco aceito |
| **L06** — RTO nunca medido | **Não fazer** | Risco aceito |
| **L07** — publicar imagem no GHCR, implantar por digest | **Não fazer** | Risco aceito; F3 encolhe |
| **F3** — lockfile e base por digest | **Manter** | Sobrevive sem o L07 |
| **L14** — ShellCheck | **Sobe para a F0** | Único item da F2 que foi adiante |
| **L19** — domínio próprio para o site | **Manter DuckDNS por enquanto** | Risco aceito; muda o desenho da F5 |
| **L11** — GitHub Pro para o repositório do cliente | **Fica como está** | Risco aceito |
| **L16** — telefones de exemplo no site | **Trocar por asteriscos** | Entra na F0 |
| **ConfortoTermico** | **Independente daqui para a frente** | Trilha própria (§7); F6 reformulada |

### A mudança estrutural: o ConfortoTermico sai da frota

O ConfortoTermico é o projeto de mestrado do mantenedor e segue caminho
próprio. A arquitetura dele fica **livre para variar**; os outros sistemas
continuam juntos e evoluindo em conjunto.

O grau de separação escolhido foi o mais leve dos três possíveis: **só o
código diverge.** Concretamente:

| Continua | Deixa de valer |
|---|---|
| Hospedado no VPS, em `conforto-mspa.duckdns.org` | Ser referência de padronização da frota |
| No `deploy.sh`, no `vigia.sh`, na autocura e nos monitores | Ter de adotar o padrão de interface dos irmãos (HTMX, templates) |
| No `manutencao` (vhost, alvo de deploy) | Aparecer no roadmap das fases |
| No backup diário e no BackupRestore | Entrar na conta de “toda mudança feita duas vezes” |
| Consumindo `SharedAuth` na tag fixada | — |

**O que isso realmente elimina — e o que não elimina.** O custo de duplicação
tinha duas metades, e só uma desaparece:

- **Desaparece** a metade de *padrão e interface*: HTMX, formato de template,
  organização de rotas, convenção de tela. O ConfortoTermico pode ficar SPA em
  JS puro para sempre, e isso deixa de ser dívida.
- **Permanece** a metade de *contrato operacional*: ele continua consumindo
  `SharedAuth`, então uma tag nova ainda precisa ser adotada por ele; continua
  servindo `/health` no formato que o `deploy.sh` e o `vigia.sh` esperam;
  continua sujeito ao contrato de deploy e de backup.

Essa distinção é o conteúdo do ADR da F6. Sem ela escrita, a separação vira
ambiguidade na primeira mudança transversal.

**Efeito colateral favorável:** a frota restante — MegaSena, ControleBancario e
ControleRendaVariavel — fica *mais* homogênea do que era. Dois Flask e um
Django, todos com HTMX, todos com ORM, todos com gunicorn, todos com um
serviço. Padronizar os três é agora mais barato do que padronizar os quatro
era, e a recomendação de §3.3 (“o próximo nasce em Django”) fica mais limpa.

---

## 3. As tecnologias escolhidas são adequadas? Existem melhores?

### 3.1 A pilha

**Sim, é adequada. Não, não há melhor para o seu caso.** Justificando por
partes, porque a pergunta merece mais que um "sim":

**Python.** Certo. O domínio é regra de negócio e dados, não latência.
Ecossistema de PostgreSQL, planilha, PDF e Modbus todo presente. Trocar por Go
ou Rust compraria desempenho que você não precisa ao preço de reescrever
dezenas de milhares de linhas auditadas. Trocar por Node/TypeScript compraria
tipagem — que você pode ter em Python, de graça, com `mypy`/`pyright`, e hoje
não tem.

**PostgreSQL.** Certo, sem ressalva. `Decimal` correto, `CHECK constraints`,
JSONB, dump em formato custom, transação de verdade. Para dados financeiros,
qualquer alternativa é pior.

**Docker + Compose.** Certo. A imagem imutável, o perfil `quality` que não
monta código do host, o `read_only` — isso é uso maduro, não uso decorativo.

**nginx + Let's Encrypt + systemd.** Certo. Simples, observável, sem camada de
orquestração que você teria de manter.

**HTML no servidor + HTMX.** Certo, e é a escolha mais inteligente do
conjunto. Um front-end React/Vue para essas telas seria mais código, mais
build, mais superfície e nenhuma tela melhor.

### 3.2 A única troca que se paga: gerência de dependências

Hoje: faixas em `pyproject.toml`, **sem lockfile**, imagem base
`python:3.14-slim` **sem digest**, e `apt-get upgrade` dentro do build.

Efeito: dois builds do mesmo commit produzem imagens diferentes. Como o
`deploy.sh` roda `compose up -d --build` no VPS, o artefato que serve o site é
sempre uma reconstrução, nunca uma cópia do que foi testado.

**Recomendação (mantida):** adotar `uv` (`uv lock` + `uv sync --frozen`).
Lockfile com hash, resolução determinística, instalação bem mais rápida no
build. Mantém `pyproject.toml` como fonte única — não muda nada do que você já
escreveu. Alternativa conservadora: `pip-compile` gerando `requirements.lock`
com `--generate-hashes`. Fixar a base por digest
(`python:3.14-slim@sha256:...`) fecha o resto, e o Dependabot já sabe atualizar
digest.

**O que isso resolve e o que não resolve, agora que o L07 está fora.** Com
lockfile e base por digest, as dependências Python e a camada base passam a ser
determinísticas. Sobra flutuando **só a camada de pacotes do sistema
operacional**, e isso é por desenho: o `apt-get upgrade` existe justamente para
aplicar correção de CVE do Debian antes de a imagem oficial ser republicada, e
tirá-lo trocaria reprodutibilidade por vulnerabilidade — mau negócio.

A diferença entre a imagem testada e a servida deixa de ser "tudo pode variar"
e passa a ser "só variam patches de segurança do sistema". Não é o mesmo que o
L07 entregaria, mas é a maior parte do ganho pelo menor custo, e sem tocar no
caminho do deploy.

### 3.3 Flask ×2 e Django ×1 — a observação honesta

Vale dizer em voz alta, porque orienta o que vem: **o `SharedAuth` existe, em
boa medida, para reconstruir em Flask o que o Django já traz de fábrica.**
Sessão, CSRF, hash de senha, controle de acesso por papel, senha temporária,
trava de troca pendente, cabeçalhos, mensagens — o Django tem tudo isso, mais
admin, paginação, formulários e i18n.

Isso **não** é argumento para migrar o MegaSena e o ControleRendaVariavel. Eles
funcionam, estão auditados, e a migração custaria meses para entregar
exatamente as mesmas telas. O `SharedAuth` foi a resposta certa para o problema
que existia.

É argumento para uma coisa só, e é a decisão que importa agora:

> **Tudo que nascer daqui para a frente nasce em Django.** Concretamente: o
> portal do cliente da MP Soluções.

---

## 4. Achados por eixo

Legenda de esforço: **P** até 2h · **M** meio dia · **G** um dia ou mais.
Situação: **ativo** (está no plano) · **adiado** · **risco aceito** (decidido
não fazer; registrado em §6) · **trilha CT** (movido para §7).

### 4.1 Verificação e estabilidade — o eixo crítico

#### L01 · Nenhuma aplicação testa contra banco · Alto · G · **ativo**

Evidência, literal, nos `conftest.py`:

- `MegaSena/tests/conftest.py:3` — "A suite nao toca o banco."
- `ControleRendaVariavel/tests/conftest.py:3` — "A suite nao toca o banco."
- `ControleBancario/tests/conftest.py:3` — "A suite nao toca o banco."

Cada docstring chama isso de "desenho, não limitação", e o argumento é bom: as
coisas que a suíte protege (cabeçalhos, negação por padrão, CSRF) são decididas
antes de qualquer consulta, e sem banco a suíte cabe em 30 segundos.

O problema é o que sobra de fora. Estes são invariantes que os próprios
`AGENTS.md` declaram, e **nenhum deles é verificável sem banco**:

| Invariante declarado | Projeto |
|---|---|
| "operações compostas são atômicas e services delimitam transações" | ControleBancario |
| "fechamento mensal bloqueia mutações e conciliações do período" | ControleBancario |
| "a rotina [projeção recorrente] é idempotente" | ControleBancario |
| "transferências internas mantêm contrapartes e saldos consistentes" | ControleBancario |
| "quantidade e preço médio não são negativos" | ControleRendaVariavel |
| "Proteja invariantes concorrentes no banco" | ControleRendaVariavel |
| "As `CHECK constraints` de `Draw` protegem valores derivados" | MegaSena |
| "Importações de XLSX são atômicas" | MegaSena |

Eu li vários desses pontos no código. `delete_portfolio` em
`ControleRendaVariavel/app/routes/tables.py:392` faz commit, captura
`IntegrityError`, faz rollback e arquiva — está correto. **Correto hoje, e sem
rede se alguém mexer amanhã.**

O caso mais agudo é o **ControleBancario**: 17.949 linhas, 211 testes, e um
único `django_db` no repositório inteiro
(`tests/test_operational_configuration.py`). É a aplicação que mexe com
dinheiro e é a que menos exercita persistência.

**Recomendação.** Não é reescrever a suíte, e não é infraestrutura nova — é
ligação. O `pytest-django` já é dependência de dev, o serviço `postgres` já
existe no Compose, e o Django cria e destrói o banco de teste sozinho:

1. `depends_on: postgres` e `POSTGRES_HOST=postgres` no serviço `quality`.
2. Um teste que aplique `alembic upgrade head` / `manage.py migrate` em banco
   **vazio** e depois `downgrade` um passo. Isso sozinho fecha o encadeamento
   do §1.
3. Cinco a dez testes de invariante por aplicação — os da tabela acima, não
   cobertura geral.

Ordem sugerida: ControleBancario → ControleRendaVariavel → MegaSena.

#### L02 · O teste de migração não aplica migração · Alto · M · **ativo**

`MegaSena/tests/test_schema_bootstrap.py` (e os equivalentes nos irmãos) lê os
arquivos de `migrations/versions/` **com expressão regular** e verifica o
grafo: uma base, uma cabeça, elos íntegros, sem revisão duplicada. É um bom
teste do que se propõe, e o docstring é honesto: "Nao aplica migracoes: isso e
verificacao manual obrigatoria contra PostgreSQL vazio."

O que escapa: SQL inválido, coluna `NOT NULL` adicionada a tabela com linhas,
dependência de extensão ausente, `downgrade` que não desfaz o `upgrade`.
Tudo isso passa verde na CI e falha na produção — onde encontra o limite
documentado do rollback (`vps/deploy.sh:25`).

Resolvido junto com L01, item 2.

#### L03 · O piso de Python declarado não é testado por ninguém · Médio · P · **ativo**

| Projeto | `requires-python` | Imagem que executa |
|---|---|---|
| ControleRendaVariavel | `>=3.12` | `python:3.14-slim` |
| MegaSena | `>=3.13` | `python:3.14-slim` |
| SharedAuth | `>=3.13` | (sem imagem) |
| ControleBancario | `>=3.14` | `python:3.14-slim` |

Sua política diz, com todas as letras, que o piso "registra a compatibilidade
mínima **efetivamente verificada**". Não há nada que verifique. Nenhum job roda
a suíte em 3.12 ou 3.13.

Duas saídas legítimas: subir os pisos para `>=3.14` (reconhecendo que é o
único ambiente exercitado), ou adicionar uma matriz de Python no venv da CI. A
primeira é honesta e custa cinco minutos; a segunda preserva a intenção
original e custa mais.

#### L04 · Cinco commits parados em branches locais · Médio · P · **ativo**

Árvores limpas, mas o HEAD não está no `main`:

| Repositório | Branch | Commits fora do `origin/main` |
|---|---|---|
| ControleRendaVariavel | `fix/coletor-sem-janela` | 2 — `fix: parar de corromper o acento no log do coletor`; `fix: rodar o coletor sem janela de console` |
| BackupRestore | `chore/normalizar-fim-de-linha` | 2 |
| SharedAuth | `chore/normalizar-fim-de-linha` | 1 |

Os dois do CRV são **correções de defeito real**. O VPS espelha `main`. Logo,
essas correções **não estão em produção**, e a máquina de desenvolvimento está
há dias fora do branch que a produção usa — o estado mais fácil de esquecer que
existe.

---

### 4.2 Persistência e recuperação

#### L05 · Comprovantes do ControleBancario sem backup no VPS · Alto · M · **risco aceito**

`vps/backup-db.sh` e `BackupRestore/projetos.py` cobrem, para os projetos de
produção, `tipos=("banco",)`. Só o banco. O `ControleBancario` guarda anexos de
comprovante em `media_volume` (`/workspace/media/attachments`), e o próprio
`docs/operations.md:61` registra:

> "**Lacuna operacional:** não há neste repositório um procedimento
> automatizado, versionado e testado para backup/restauração de
> `media_volume`. […] Até isso existir, não trate os comprovantes como
> cobertos pelo backup central."

**Decisão:** continua sem backup. O cenário que isso aceita: perde-se o VPS, o
dump restaura todas as linhas, e cada comprovante referenciado por essas linhas
deixou de existir — restauração parcial que parece completa.

A recomendação original fica registrada para quando o gatilho de §6 disparar:
um `vps/backup-vol.sh` irmão do `backup-db.sh`, com o mesmo contrato já provado
(temporário → releitura → troca atômica → SHA-256 → retenção que nunca apaga o
último válido), e o `vps.py` ensinado a buscá-lo.

#### L06 · O RTO nunca foi medido · Médio · M · **risco aceito**

Provado hoje: **o dump restaura**. Os ensaios do BackupRestore são reais, e o
sandbox `backuprestore-sandbox` é o único destino autorizado — bom desenho.
Não provado: **que o ambiente pode ser reconstruído**. O `KIT_RECUPERACAO.md`
descreve o inventário; descrever não é ensaiar.

- **RPO, medido:** até 24 horas (timer diário às 03:00, retenção de 14 dias no
  VPS + Camada 2 fora dele). Claro e defensável.
- **RTO:** desconhecido, e permanece assim por decisão.

---

### 4.3 A entrega

#### L07 · A imagem servida nunca foi testada nem varrida · Alto · G · **risco aceito**

Nenhum workflow publica imagem: não há `docker push`, nem `ghcr.io`, nem
`packages: write` em nenhum dos dez. A CI constrói, testa, varre com Trivy e
**descarta**. O `deploy.sh` roda `compose up -d --build` no servidor.

Portanto: a imagem que atende `bancario-mspa.duckdns.org` foi construída no
VPS e não passou pelo Trivy nem pelo pytest. O portão de qualidade é real, mas
guarda uma porta ao lado.

**Decisão:** não fazer. A proposta era construir uma vez na CI, publicar no
GHCR por digest e trocar `--build` por `pull` no `deploy.sh`.

**Mitigação parcial que permanece no plano:** a F3 (lockfile + base por
digest) reduz a diferença entre a imagem testada e a servida a apenas os
pacotes de sistema — ver §3.2. Não elimina o achado; corta a maior parte dele
pelo menor custo.

Fica registrado o que continua valendo: rollback reconstrói a imagem inteira
(minutos, com o site fora); o PAT de leitura do `SharedAuth` continua
necessário no servidor; e PyPI e GitHub permanecem no caminho crítico de um
deploy.

#### L23 · A engrenagem de token do `SharedAuth` é peso morto · Médio · M · **ativo (F3)** — *novo, achado no F0*

O `SharedAuth` é um repositório **público**. Toda a maquinaria montada para
lê-lo como privado continua no lugar, em quatro projetos:

| Onde | O quê |
|---|---|
| 4 `Dockerfile` | `--mount=type=secret,id=github_token` e o `git config url.<...>.insteadOf` que injeta o PAT, mais o `--unset` que o remove da camada |
| 4 CIs | passo "Write SharedAuth read token" e o secret `SHAREDAUTH_READ_TOKEN` |
| VPS | `.secrets/github_token.txt` presente no servidor, exigido pelo build de cada deploy |
| Máquina local | o mesmo arquivo, exigido para qualquer build |

Nada disso é necessário: `pip install git+https://github.com/...` num repositório
público pede apenas `git` no PATH.

**Por que vale a pena tirar, e não é só higiene.** O PAT existe hoje no VPS
unicamente porque o build acontece lá. Removê-lo apaga um segredo de produção,
um secret da CI e um arquivo que precisa ser recriado a cada reclone — e cada
um deles é uma peça que pode expirar, vazar ou faltar num momento ruim. É
também metade do argumento que sustentava o [L07](#l07--a-imagem-servida-nunca-foi-testada-nem-varrida--alto--g--risco-aceito),
recuperada por um caminho que você não vetou.

**Onde entra:** na **F3**. É o mesmo conjunto de arquivos que o lockfile e o
pino por digest já vão abrir, e a mesma validação — build limpo e `quality`.
Fazer junto reconstrói as imagens uma vez em vez de duas.

---

### 4.4 Observabilidade: você sabe se caiu; não sabe se quebrou

#### L08 · Nenhuma visibilidade de erro de aplicação · Médio† · M · **ativo**

Busca em todos os repositórios por `sentry`, `opentelemetry`, `prometheus`,
`glitchtip`, `loki`, `grafana`: **nenhuma ocorrência**. Configuração de
logging estruturado: nenhuma.

O que existe, e é bom: `vigia.sh` horário (disco, `/health` público,
certificado, frescor do backup), `autocura.sh` com teto, alerta Telegram por
`OnFailure=` do systemd, UptimeRobot por fora do VPS.

O que isso cobre: **queda**. O que não cobre: **quebra**. Uma rota que devolve
500 para todo mundo mantém o `/health` verde — porque `/health` consulta o
banco, e o banco está bem. O erro vira uma linha em `docker logs`, com rotação
de 10 MB × 3, e ninguém é avisado.

Para uso pessoal, tolerável: você é o usuário e percebe. **Para um cliente, não
é** — o cliente percebe primeiro, e liga. († Impacto Alto assim que houver
cliente.)

**Recomendação, na ordem de custo:**

1. *Barato e no seu estilo:* um handler de erro 500 em cada app que chame o
   `alerta.sh` que já existe, com deduplicação (a supressão de repetição já
   está implementada lá). Reaproveita o canal Telegram que você confia e
   resolve 80% sem adicionar dependência.
2. *Melhor:* Sentry no plano gratuito (5 mil eventos/mês, folgado para este
   volume) ou GlitchTip auto-hospedado, quando o portal do cliente subir.

---

### 4.5 Segurança residual

Duas auditorias já passaram por aqui e não sobrou nada crítico ou alto. O que
segue é a camada de plataforma, que não fazia parte do escopo delas.

#### L09 · `manutencao` público com todas as proteções desligadas · Alto · P · **ativo**

Consultado pela API do GitHub, `MSPA-Coder/manutencao`:

```
visibility: public
dependabot_security_updates: disabled
secret_scanning:              disabled
secret_scanning_push_protection: disabled
```

Os outros seis repositórios públicos têm `secret_scanning` e
`push_protection` **habilitados**. O `manutencao` é a exceção — e é justamente
o que contém `deploy.sh`, `backup-agent.sh`, `instalar.sh`, os vhosts do
nginx, as unidades systemd, os domínios, as portas, os caminhos e o usuário de
deploy.

Duas coisas distintas, e vale separá-las:

**a) As proteções desligadas.** Defeito claro, sem contra-argumento. Um
segredo commitado por engano no repositório mais sensível é o único que
ninguém detectaria. **Ligar as três** custa dois minutos, e está na F0.

**b) A visibilidade pública.** Decisão, não defeito. Nada ali é segredo — o
desenho é bom e não depende de obscuridade. Mas o conjunto entrega um mapa
completo do ambiente: domínios, portas internas 5101/5201/5301/5401/5501,
caminho `/home/ubuntu/apps`, os quatro verbos do agente de backup, o que o
vigia observa e o que não observa. Não muda a superfície de ataque; muda o
custo de reconhecimento. Com um cliente entrando em cena, eu tornaria **este**
repositório privado e manteria os outros como estão. Continua sendo sua
chamada.

#### L10 · `secret_scanning_non_provider_patterns` desligado nos sete públicos · Médio · P · **risco aceito (indisponível)**

Habilitado, o scanner reconhece tokens de provedores conhecidos (AWS, GitHub,
Stripe). O padrão *non-provider* é o que pega o resto: chave privada colada,
string de conexão PostgreSQL, senha em arquivo de configuração. Exatamente as
formas que os seus segredos têm.

**Correção de 07/09, na execução do F0.** A primeira versão deste documento
dizia "um clique por repositório". Está errado. O `PATCH` da API é aceito com
200 e **ignorado** — testado em dois repositórios, o campo permanece
`disabled`. É recurso do GitHub Secret Protection, pago para conta pessoal.
Não há o que fazer sem contratar; o achado vira risco aceito por
indisponibilidade, não por escolha.

#### L11 · O repositório do cliente é o único sem proteção de branch · Médio · P · **risco aceito**

`mp-solucoes` é privado, e num plano gratuito rulesets e branch protection
**não estão disponíveis** — a API responde "Upgrade to GitHub Pro". Os sete
públicos têm ruleset ativo com histórico linear, sem force-push, sem deleção e
status checks obrigatórios (`Qualidade` + `CodeQL`).

**Decisão:** GitHub fica como está. O repositório que vai virar entrega para
cliente segue sem rede — aceitável enquanto o site é rascunho e você é o único
a commitar.

#### L12 · `AGENTS.md` do MegaSena afirma que não há CodeQL — e há · Baixo · P · **ativo**

A API diz que CodeQL default setup está `configured` nos **sete** repositórios
públicos, semanal, e que `Qualidade`+`CodeQL` é status check obrigatório no
ruleset.

A parte de "análise estática de tipos" continua verdadeira — não há `mypy` nem
`pyright` em lugar nenhum. Vale considerar: em dezenas de milhares de linhas
com anotações já presentes, um `mypy` em modo não-estrito pegaria uma classe
inteira de defeito que os testes sem banco não alcançam. Custo baixo, ganho
real, não é urgente.

Corrigir a frase importa mais do que parece: o `AGENTS.md` é o contrato que os
agentes leem, e documentação errada ali propaga decisão errada.

#### L24 · Três repositórios aceitavam qualquer action de terceiro · Alto · P · **concluído no F0** — *novo, achado no F0*

O `AGENTS.md` do MegaSena afirma que "a política **destes repositórios** é
`allowed_actions: selected` com apenas `github_owned_allowed`". A API mostrava
outra coisa:

| Repositório | `allowed_actions` | `sha_pinning_required` |
|---|---|---|
| mega-sena, sistema-financeiro, ControleRendaVariavel, BackupRestore | `selected` | `true` |
| **manutencao, SharedAuth, ConfortoTermico** | **`all`** | **`false`** |

Ou seja: nos três, qualquer action de qualquer autor podia rodar, sem exigência
de fixação por SHA. O mais grave é o `SharedAuth` — é a biblioteca que os
outros instalam em tempo de build, e o repositório onde uma tag é publicada.
Uma action hostil ali alcança os consumidores. O `manutencao` vem logo atrás,
porque governa a produção.

**Concluído no F0.** Os três foram alinhados a `selected` +
`github_owned_allowed` + `sha_pinning_required`. Não quebrou nada: os três só
usam `actions/checkout` e `actions/setup-python`, ambas do GitHub e já fixadas
por SHA.

A lição que fica é a mesma do [L22](#l22--documentação-viva-à-deriva--baixo--p--ativo-f0): o
`AGENTS.md` descrevia uma política que só valia em quatro dos sete
repositórios, e ninguém tinha como notar sem consultar a API.

---

### 4.6 Padronização

#### L13 · O ConfortoTermico é outra arquitetura · Médio · P · **trilha CT**

Medido, não impressão:

| Dimensão | MegaSena / CRV / Bancário | ConfortoTermico |
|---|---|---|
| Interface | HTML no servidor + HTMX (10, 17 e 23 templates com `hx-`) | SPA em JS puro — **0** templates com HTMX |
| JavaScript próprio | pouco, acessório | **~4.990 linhas** em 11 arquivos |
| Templates | 42 e 47 | **6** |
| ORM | Flask-SQLAlchemy / Django ORM | `db_backend.py` — shim próprio de 340 linhas |
| Sessão/login | Flask-Login | `app/seguranca/auth.py` próprio |
| Servidor WSGI | gunicorn | waitress |
| Serviços | 1 | 2 (`ict` + `coletor`) |

**Situação nova.** Isto deixou de ser dívida. Com a separação decidida em §2, a
divergência arquitetural passa a ser deliberada e sancionada — e o esforço cai
de **G** (convergir) para **P** (registrar o ADR da F6).

O que o ADR precisa dizer, e é a parte que não pode ficar implícita: a
arquitetura é livre, mas o **contrato operacional é preservado** — `/health` no
formato que `deploy.sh` e `vigia.sh` esperam, tag de `SharedAuth` adotada,
sujeito ao contrato de deploy e de backup. Sem essa metade escrita, a
separação vira ambiguidade na primeira mudança transversal.

#### L14 · O `manutencao` é o outlier da CI · Médio · P · **ativo (F0)**

O repositório que governa a produção tem a CI mais fraca dos oito:

- **Sem ShellCheck.** São **1.516 linhas de Bash** rodando backup,
  restauração, deploy com rollback e alerta em produção, e a única verificação
  é `bash -n` — que checa sintaxe, não semântica. ShellCheck pega variável não
  citada, word splitting, armadilhas do `set -e`, `[ ]` frágil. É o linter que
  falta, no repositório onde mais faz falta.
- **Sem `dependabot.yml`.** Os outros sete têm (2 ou 3 ecossistemas). Aqui, a
  action fixada por SHA nunca será atualizada por ninguém.
- **`runs-on: ubuntu-latest`** contra `ubuntu-24.04` nos outros nove jobs.
- **Sem validação de nginx.** Os cinco vhosts versionados não passam por um
  `nginx -t` antes de chegarem ao servidor.

Todos os quatro são correções de um arquivo, e todos foram para a F0.

---

### 4.7 Performance: não é problema — e o gatilho para quando for

#### L15 · Veredito: adequada; nada a fazer agora · Baixo · — · **ativo (nada a fazer)**

Fui atrás dos suspeitos e não encontrei o crime.

- **Índices presentes:** 26 `index=True` + 4 `Index()` no CRV, 20 blocos
  `Meta.indexes` no Django, 8 no MegaSena, 41 `create_index` distribuídos por
  13 migrações.
- **Eager loading correto:** 14 módulos Django com
  `select_related`/`prefetch_related`, 5 no CRV com
  `joinedload`/`selectinload`. Sem N+1 em caminho quente.
- **A listagem do ControleBancario não pagina — e está certo.** Não há
  `Paginator`, mas `build_transactions_view_context`
  (`transactions/services.py:1462`) recorta por mês. O limite natural da tela é
  o mês, não o histórico; paginar adicionaria complexidade sem remover
  trabalho.
- **O saldo de abertura é agregado no banco, não em Python.**
  `decimal_period_start_balance` (`reports/services.py:1011`) soma o histórico
  via agregação SQL indexada — uma consulta, não um laço.

**O gatilho, para não ficar vago:** o saldo de abertura é O(histórico). Em
dezenas de milhares de lançamentos é imperceptível. Se um dia a tela de
Lançamentos passar de ~300 ms para carregar, a solução é um snapshot de saldo
por fechamento mensal — e você **já tem o conceito de `MonthClose`** no
domínio. O gancho existe; não construa antes de precisar.

---

### 4.8 O site MP Soluções

Os outros são de uso pessoal, com um usuário que perdoa. Este vai para um
cliente.

#### L16 · Dados de contato de exemplo no ar · Alto · P · **ativo (F0)**

`site/index.html`, linhas 16, 426, 441 e 484: `0800 000 0000` e
`(11) 90000-0000`, publicados em `mp-solucoes.duckdns.org` agora.

**Decisão:** trocar por asteriscos — `0800 ***-****`, `(11) *****-****`. Um
número mascarado se lê como rascunho deliberado; um número falso completo se lê
como erro, e alguém pode discar. **Feito no F0**, incluindo o e-mail
`contato@********.com.br`; o `placeholder` do campo de telefone ficou como
estava, porque ali ele ensina o formato em vez de afirmar um contato.

**O que apareceu junto, e era pior.** O formulário "Solicite um orçamento" não
tem destino: `site.js` fazia `preventDefault()`, **sorteava** um protocolo
`MP-######` e exibia "Solicitação recebida". Um interessado real preencheria
nome, empresa, e-mail e telefone, receberia um número de protocolo inventado, e
o contato seria descartado em silêncio. Isso invalida a frase do
[L20](#l20--lgpd-entra-com-o-formulário--médio--m--ativo-f7) — havia
formulário, ele é que não levava a lugar nenhum.

Corrigido no F0 pelo caminho menos destrutivo: o protocolo sorteado saiu, e a
página avisa duas vezes que é demonstração — uma tarja antes de alguém digitar
e a tela de retorno depois do envio. O bloco e o desenho permanecem para quando
houver destino (F7).

Nota, sem insistir: asteriscos resolvem o número; não impedem a indexação do
rascunho. Se quiser fechar isso também, é uma linha —
`<meta name="robots" content="noindex">` no `<head>`, removida junto com os
asteriscos quando o conteúdo for real.

#### L17 · SPA por hash: a decisão mais consequente do site · Alto · M · **ativo (F5)**

`site/assets/js/site.js:96-115`: sete "páginas" (`#/home`, `#/solucoes`,
`#/metodo`, `#/segmentos`, `#/parceiros`, `#/empresa`, `#/contato`) vivem todas
dentro de um único `index.html`, trocadas por `hashchange`.

O roteador é caprichado — atualiza `document.title`, marca `aria-current`,
restaura o scroll. Mas o fragmento depois de `#` **não é enviado ao servidor e
não constitui URL para buscador nenhum**:

- **Uma única URL indexável.** Não dá para rankear "portaria" e "controle de
  acesso" em páginas distintas, porque não existem páginas distintas.
- **Compartilhamento quebrado.** Quem manda `.../#/contato` no WhatsApp ou
  LinkedIn gera a prévia da home. Sempre a mesma.
- **Analytics** exige instrumentar `hashchange` à mão.

Confirmado ausente, tudo: `robots.txt`, `sitemap.xml`, `canonical`, Open
Graph, Twitter Card e JSON-LD.

**Recomendação:** converter para **multipágina estática** — um `.html` por
rota, mesmo CSS, mesmo JS, mesmo nginx, mesma CSP `default-src 'none'`, mesma
imagem imutável. Não perde nada: continua sem backend, sem build, sem
dependência externa. Ganha sete URLs reais, sete títulos, sete descrições,
sete prévias.

**Ajuste por causa do domínio (§ L19).** Com o DuckDNS mantido, o trabalho se
divide em duas metades com retornos diferentes:

- **Fazer agora** — a estrutura: multipágina, um `<title>` e uma
  `<meta description>` por rota, Open Graph por rota, imagens. É barato hoje,
  com sete páginas, e caro com trinta. Independe do domínio.
- **Adiar, ou parametrizar** — os artefatos com URL absoluta: `sitemap.xml`,
  `canonical`, `og:url`. Eles apontam para o domínio, e trocar de domínio
  depois exige refazê-los. Se preferir já deixar prontos, gere-os a partir de
  uma constante única de URL base, e a migração vira uma linha.

O ganho de SEO só se materializa quando o domínio próprio entrar. A estrutura
feita agora é o que torna esse dia barato.

#### L18 · Imagens sem `lazy` e sem dimensão · Médio · P · **ativo (F5)**

10 `<img>`, **0** com `loading="lazy"`, **5** sem `width`/`height`, 1,3 MB de
WebP (a maior com 220 KB). Como as sete seções estão no mesmo documento, o
navegador **baixa as dez de uma vez**, no primeiro acesso — inclusive as que o
visitante talvez nunca veja.

`loading="lazy"` abaixo da dobra, `width`/`height` em todas (mata o layout
shift, critério de Core Web Vitals) e `fetchpriority="high"` na imagem do
herói. Trinta minutos. Os `alt` estão todos lá — isso já está certo.

#### L19 · O domínio · Alto · P · **risco aceito**

`mp-solucoes.duckdns.org`. DuckDNS é DNS dinâmico gratuito: sufixo
compartilhado, zero autoridade de domínio para SEO, sem e-mail corporativo, e
os termos de uso não são um contrato de hospedagem comercial.

Para os projetos pessoais é a escolha certa. Para o site de um cliente, é o
primeiro sinal que qualquer visitante lê.

**Decisão:** manter o DuckDNS por enquanto. O achado continua aberto, com
gatilho registrado em §6 — e a consequência prática está no L17: a estrutura
vai adiante, o SEO fica represado até o domínio.

#### L20 · LGPD entra com o formulário · Médio · M · **ativo (F7)**

Hoje não há formulário nem backend. Quando houver, o site passa a coletar dado
pessoal de terceiros e a MP Soluções vira controladora sob a LGPD. Mínimo
necessário: aviso de privacidade acessível, finalidade declarada, base legal,
prazo de retenção e canal para o titular exercer direitos.

| Caminho | Prós | Contras |
|---|---|---|
| Serviço de formulário (Formspree, Basin) | Zero infraestrutura | Dado sai para terceiro — entra no aviso; exige `form-action` na CSP |
| Endpoint no VPS (`POST /contato`) | Dado fica seu; reusa a frota | 6º serviço para manter |
| `mailto:` | Trivial | Conversão péssima; expõe o e-mail a coletor |

**Recomendação:** o endpoint no VPS — mas **só quando o portal for
construído**, como primeira rota dele, em Django. Até lá, WhatsApp e telefone
reais convertem bem e não coletam nada.

#### L21 · O portal do cliente: onde ele nasce · — · G · **ativo (F7)**

Quando chegar, a decisão já está tomada por §3.3: **Django, repositório novo,
consumindo `SharedAuth`**, seguindo o padrão da frota — Compose, CI,
`/health`, `deploy.sh`, backup, vigia.

- **Não transforme o site em portal.** Site institucional estático e portal
  autenticado são coisas diferentes, com cadência, risco e público diferentes.
  Dois repositórios, dois vhosts.
- **O portal é multiusuário de verdade**, com dados por cliente — diferente
  dos atuais, onde "qualquer conta autenticada acessa o acervo comum"
  (ADR 0002 do MegaSena). Isso conecta direto ao plano faseado de multiusuário
  e permissões registrado em 24/08 e nunca implementado. **O portal é o
  consumidor que faltava para justificar aquele plano.**

---

### 4.9 Processo

#### L22 · Documentação viva à deriva · Baixo · P · **ativo (F0)**

Três contradições entre o que os documentos afirmam e o que o código faz. Não
seriam nada, se `AGENTS.md` não fosse o contrato que os agentes leem antes de
mexer:

| Documento diz | Realidade |
|---|---|
| `MegaSena/AGENTS.md`: "Não há […] varredura CodeQL" | CodeQL configurado nos sete públicos, e é status check obrigatório |
| `ControleRendaVariavel/AGENTS.md`: "PostgreSQL também é o backend dos testes com persistência" | `tests/conftest.py:3`: "A suite nao toca o banco" |
| Vários `AGENTS.md`: "`sharedauth` vem de repositório privado" | `MSPA-Coder/SharedAuth` é **público** |

A segunda é a que preocupa: um agente lendo aquele `AGENTS.md` conclui que
existe cobertura de persistência que não existe, e calibra o risco errado.

Some-se a estas a quarta, criada agora: os `AGENTS.md` da frota descrevem uma
base compartilhada de quatro aplicações. Passaram a ser três, e o
ConfortoTermico precisa dizer na primeira linha que segue caminho próprio
(§7).

---

## 5. Roadmap em fases

Ordenado por relação entre consequência e custo. Os identificadores das fases
foram preservados da primeira versão, para que a comparação seja direta — a
F2 aparece explicitamente adiada em vez de removida.

### F0 — Higiene · **EXECUTADA em 07/09** · Risco Baixo

| # | Ação | Achado | Estado |
|---|---|---|---|
| 1 | Proteções de segredo e Dependabot no `manutencao` | L09 | ✅ os sete públicos agora idênticos |
| 2 | `secret_scanning_non_provider_patterns` nos sete | L10 | ❌ **impossível** — recurso pago; ver L10 |
| 3 | Resolver as cinco commits em branch | L04 | ✅ 3 PRs abertos e verdes; os 8 repos de volta no `main` |
| 4 | Mascarar os dados de contato do site | L16 | ✅ + o formulário falso, corrigido |
| 5 | Corrigir as afirmações erradas na documentação | L22, L12 | ✅ 13 lugares em 5 repositórios |
| 6 | `dependabot.yml` + `ubuntu-24.04` no `manutencao` | L14 | ✅ |
| 7 | ShellCheck na CI do `manutencao` | L14 | ✅ verde, com 13 supressões documentadas |
| 8 | `nginx -t` na CI do `manutencao` | L14 | ✅ teste hermético novo |
| 9 | Fechar action de terceiro em três repositórios | L24 | ✅ *não estava no plano* |
| 10 | Ligar `instalar_test.sh` à CI | L14 | ✅ *não estava no plano* |

**O que a execução ensinou, e não estava previsto:**

- **O ShellCheck achou 13 itens e nenhum erro.** O L14 previa "variável não
  citada, word splitting, armadilhas do `set -e`". Não havia nada disso. Cinco
  eram o idioma `CDPATH= cd` (prefixo de ambiente para um comando, e não
  assinalamento com espaço sobrando), quatro eram `ls -1t` sobre nomes que o
  próprio script gera, e um era `PORTA` — que é a única cópia da numeração da
  frota no repositório. Cada um recebeu `# shellcheck disable=` com o motivo ao
  lado, no mesmo padrão que o `--ignore-vuln` do `pip-audit` já usava. **O bash
  está mais limpo do que o achado sugeria.**
- **O `nginx -t` precisou de andaime.** Os vhosts referenciam certificados do
  Let's Encrypt e dois arquivos que o certbot escreve. `vps/tests/nginx_test.sh`
  cria certificados autoassinados e versões mínimas desses arquivos, e foi
  verificado contra três modos de falha reais — zona de rate limit inexistente,
  `include` quebrado e chave faltando — reprovando nos três. A imagem é
  `nginx:1.24` porque é a do Ubuntu do VPS; numa mais nova o teste avaliaria
  outro servidor.
- **O `instalar_test.sh` nunca esteve na CI.** Existia desde que foi escrito e
  rodava só quando alguém lembrava.
- **Dois achados novos:** L23 e L24.


### F1 — Fechar o buraco de verificação · **EXECUTADA em 07/09** · Risco Baixo

Cobriu as três aplicações da frota. O ConfortoTermico ficou de fora, na §7.

| Projeto | Testes | Antes | PR |
|---|---:|---:|---|
| ControleBancario | 282 | 281 | sistema-financeiro#56 |
| ControleRendaVariavel | 267 | 253 | ControleRendaVariavel#54 |
| MegaSena | 135 | 121 | mega-sena#47 |

Os três sobem um PostgreSQL efêmero em tmpfs no perfil `quality`,
deliberadamente separado do banco com dados reais, e **aplicam a cadeia inteira
de migrações a um banco vazio a cada execução**. Confirmado no runner, e não
só localmente: as contagens acima são as da CI, com zero testes pulados.

**O encadeamento do §1 está cortado nos três.** Uma migração que falha ao
executar agora reprova na CI, e não mais no `deploy.sh` — que reverte código e
imagem, mas não reverte migração.

**O que ficou coberto, e o que não ficou.** As `CheckConstraint` e as
`UniqueConstraint` dos três, o tipo `numeric` das colunas de valor, a volta do
`Decimal` exato, a aplicação das migrações e a revisão em que o banco parou. A
**atomicidade** só tem teste no ControleBancario, onde a falha simulada no meio
de `close_month` prova que a transação desfaz; nos dois Flask ela continua sem
cobertura, assim como concorrência. Isso é piso, não teto — e está escrito nos
`conftest.py`.

**O que a execução ensinou, e não estava previsto:**

- **Um defeito latente em `migrations/env.py`.** O `fileConfig(...)` roda com o
  padrão `disable_existing_loggers=True`, que **desliga todo logger já
  existente no processo**, inclusive o da aplicação. No contêiner nunca
  apareceu, porque a migração roda como processo separado que morre em
  seguida. Aplicando-a no mesmo processo, como a fixture faz, um teste do
  MegaSena **sem relação nenhuma** com a mudança passou a falhar. Corrigido no
  MegaSena e no ControleRendaVariavel; **o ConfortoTermico tem o mesmo padrão**
  (§7).
- **O CodeQL pegou um defeito real — meu.** Severidade alta, "uncontrolled data
  used in path expression": a fixture lia o caminho do segredo de uma variável
  de ambiente para depois abri-lo. O alerta não foi dispensado; a variável
  intermediária saiu, porque `/run/secrets/<nome>` é constante. Vale notar de
  onde veio a rede: o CodeQL era o [L12](#l12--agentsmd-do-megasena-afirma-que-não-há-codeql--e-há--baixo--p--ativo), o achado em que o
  `AGENTS.md` afirmava que ele não existia.
- **Permissão de segredo, três vezes.** Um segredo de arquivo do Compose é
  montado preservando dono e modo do host — `uid`, `gid` e `mode` na sintaxe
  longa são ignorados fora do Swarm. Com `umask 077`, o arquivo fica ilegível
  para o uid 70 do PostgreSQL, e o serviço só reporta "dependency failed to
  start". No Docker Desktop do Windows não aparece: lá tudo chega 0777. Os
  três projetos precisaram do mesmo ajuste na CI, e o MegaSena nem criava o
  arquivo — nunca precisara.
- **PR empilhado não roda CI.** O PR da F1 do CRV foi aberto contra o branch da
  F0, e as CIs disparam só em PR para `main`: ele ficou sem verificação nenhuma
  até ser reapontado.
- **Os testes corrigiram seis suposições minhas** — entre elas que `NaN > 0` é
  **verdadeiro** em `numeric` (que é justamente por que existe a constraint
  `quantity_finite`), que `Infinity` é barrado antes, pela precisão da coluna,
  e que `consecutive_count` é o comprimento da maior sequência, e não a
  contagem de pares. Cada erro virou comentário no teste.

**O quarto item, decidido em seguida.** O mantenedor optou por **elevar os
pisos para `>=3.14`**, e não pela matriz de Python. Feito em MegaSena,
ControleRendaVariavel, ConfortoTermico e SharedAuth (o ControleBancario já
estava), com o `target-version` do Ruff acompanhando.

A política da casa — alargar o teto, preservar o piso — continua valendo; o
motivo aqui é outro: o piso declarava uma compatibilidade que **ninguém
verificava**. Um detalhe do ajuste mostra por que ele era necessário: a CI do
SharedAuth instalava Python **3.13**, e elevar só o `pyproject.toml` teria
quebrado o próprio `pip install` de lá. Piso e ambiente testado passaram a ser
a mesma coisa, que era o ponto do achado.

**As três armadilhas da execução também foram fechadas.** O `fileConfig` do
ConfortoTermico recebeu `disable_existing_loggers=False`, fechando o último dos
três projetos que tinham o padrão. E a CI dos **oito** repositórios perdeu o
filtro `branches: [main]` do gatilho de `pull_request`, de modo que PR
empilhado passa a rodar verificação — o `push` continua restrito a `main`. A
armadilha da permissão de segredo já havia sido corrigida nas três CIs onde
mordia.

**Pronto quando — e está:** uma migração deliberadamente quebrada reprova na
CI. Verificado também por mutação no ControleBancario: remover
`@db_transaction.atomic` de `close_month` faz o teste de atomicidade reprovar,
apontando a linha órfã.


### F2 — Recuperação de verdade · **ADIADA POR DECISÃO**

Backup de `media_volume`, ensaio cronometrado de reconstrução, correção do
`KIT_RECUPERACAO.md`. Fora do plano por ora; os riscos aceitos estão em §6
(L05, L06) com os respectivos gatilhos.

O único item que foi adiante — ShellCheck — está na F0.

### F3 — Build reprodutível · **EXECUTADA em 08/09** · Risco Baixo

Encolhida pela decisão sobre o L07, e depois acrescida do L23 — que é o mesmo
conjunto de arquivos.

| # | Ação | Achado | Estado |
|---|---|---|---|
| 1 | `uv lock` (ou `pip-compile --generate-hashes`) nos projetos da frota | §3.2 | ✅ nos três da frota |
| 2 | Base fixada por digest nos `Dockerfile` | §3.2 | ✅ nos três + no site |
| 3 | Retirar a engrenagem de token do `SharedAuth`: o `--mount=type=secret` dos `Dockerfile`, o passo e o secret das CIs, e o `.secrets/github_token.txt` do VPS e da máquina local | L23 | ✅ PAT revogado; falta só apagar o arquivo do VPS |

**Pronto quando:** dois builds do mesmo commit produzem a mesma imagem, salvo
os patches de sistema que o `apt-get upgrade` aplica de propósito (§3.2) — e
não existe mais PAT do `SharedAuth` no VPS, na CI nem na sua máquina.

**O que a execução ensinou, e não estava previsto:**

- **`--frozen` não valida o lock; `--locked` valida.** Os dois nomes sugerem a
  mesma coisa. Testei por mutação: com o lock desatualizado, `uv sync --frozen`
  sai com código 0 e instala as versões antigas em silêncio. Todos os builds
  usam `--locked`.
- **O lock transformou uma versão flutuante em decisão.** O Dependabot havia
  alargado o teto do Django de `<6` para `<7`, então qualquer rebuild do
  ControleBancario já instalaria a 6.x — sem lock, sem aviso, sem ninguém
  escolher. O lock tornou isso visível, e **o Django 6.1.1 foi adotado de
  propósito**, com os 282 testes passando.
- **A suíte não percorre telas, então a major pediu percurso manual.** Foi
  feito no navegador, 20 telas: nenhum erro 500, nenhum stack trace, nenhum
  fragmento HTMX quebrado. **Nenhuma regressão do Django 6.** Achou, em
  compensação, dois defeitos pré-existentes que nada verificava — moeda crua
  em duas telas (os templates nunca carregaram `money_filters`) e um item de
  menu apontando para `/admin/`, rota removida com o `django.contrib.admin`.
  Esse item era folha no fim da árvore que `primeira_tela_permitida` percorre:
  um `is_staff` sem permissão nenhuma seria mandado para o 404 ao entrar.
  Corrigidos, com uma guarda nova que cruza a URLconf com a árvore do menu.
- **Um teste da CI era corrida, e ficou verde por sorte por muito tempo.** A
  guarda de thread do coletor do ControleRendaVariavel comparava
  `threading.enumerate()` antes e depois de `create_app`, e reprovava qualquer
  thread nova. O Flask-Limiter monta um `MemoryStorage`, cujo construtor sobe
  um `threading.Timer(0.01)` sem nome próprio. O teste dependia de o retrato
  cair fora de uma janela de dez milissegundos. Passou a esperar as efêmeras
  saírem — o supervisor que a guarda existe para pegar não morre sozinho.
- **O `--prefix=/install` do ControleBancario virou venv de verdade.** Era um
  venv improvisado, e por isso a remoção do `pip` precisava caçar dentro de
  `/usr/local/lib/python*/site-packages`. Os três `Dockerfile` da frota têm
  agora o mesmo formato.
- **O ConfortoTermico entrou só pelo L23.** Ele segue trilha própria (§7) e
  continua sem lock e sem digest — dito com todas as letras no `AGENTS.md`
  dele. A retirada do token tinha de alcançá-lo mesmo assim: enquanto qualquer
  build da frota exigisse o arquivo, o PAT teria de continuar existindo no VPS.

O risco caiu de Médio para Baixo: nada aqui toca `deploy.sh` nem a topologia de
produção.


### F4 — Observabilidade de aplicação (meio dia) · Risco Baixo

| # | Ação | Achado |
|---|---|---|
| 1 | Handler de 500 → `alerta.sh`, com deduplicação | L08 |
| 2 | Avaliar Sentry gratuito ou GlitchTip quando o portal subir | L08 |

**Pronto quando:** provocar um 500 numa rota qualquer chega no Telegram.

### F5 — Estrutura do site (1–2 dias) · Risco Baixo

Encolhida: domínio próprio e GitHub Pro saíram. Sobra a parte que independe
dos dois — e que fica mais barata agora do que depois.

| # | Ação | Achado |
|---|---|---|
| 1 | Converter para multipágina estática, uma URL por rota | L17 |
| 2 | `<title>` e `<meta description>` próprios por página; Open Graph por rota | L17 |
| 3 | `loading="lazy"`, `width`/`height`, `fetchpriority` na hero | L18 |
| 4 | `robots.txt` e JSON-LD `Organization` (não dependem de domínio) | L17 |
| 5 | *Parametrizar* `sitemap.xml`, `canonical` e `og:url` por uma constante de URL base — ou adiá-los até o domínio | L17, L19 |
| 6 | Analytics respeitando a CSP (Plausible ou Umami, sem cookie → sem banner) | L17 |

**Pronto quando:** cada rota tem URL própria, título próprio e prévia própria
ao ser compartilhada — e trocar de domínio depois é editar uma constante.

### F6 — Separar o ConfortoTermico (1h) · Risco Baixo

Reformulada. Não é mais "declarar uma divergência que incomoda"; é registrar
uma separação decidida.

| # | Ação | Achado |
|---|---|---|
| 1 | ADR no ConfortoTermico: arquitetura livre, contrato operacional preservado | L13 |
| 2 | Primeira linha do `AGENTS.md` dele dizendo que segue caminho próprio | L13, L22 |
| 3 | `AGENTS.md` dos três irmãos: a base compartilhada passa a ser de três apps | L22 |

**Pronto quando:** um agente que abra qualquer um dos quatro repositórios
entende, na primeira tela, quem está na frota e quem não está — e o que
continua valendo para os dois lados.

### F7 — Portal do cliente (quando o site amadurecer) · Risco Médio

Repositório novo, Django, `SharedAuth`, padrão da frota. Traz junto o
formulário de contato e a conformidade LGPD (L20), e é o consumidor que
finalmente justifica o plano de multiusuário e permissões de 24/08 (L21).

---

## 6. Riscos aceitos

Recomendação recusada que não fica escrita vira risco esquecido. Estes cinco
foram decididos com conhecimento do custo; o que segue é o registro do que se
aceita e do gatilho que deve fazer a decisão ser revisitada.

| Achado | O que se aceita | Revisitar quando |
|---|---|---|
| **L05** — `media_volume` sem backup | Perda do VPS restaura o banco e **não** restaura os comprovantes. As linhas voltam apontando para arquivos que não existem mais. | Os comprovantes deixarem de ser reconstituíveis por outra via (extrato do banco, e-mail), ou surgir obrigação fiscal/contratual de guardá-los. |
| **L06** — RTO desconhecido | Sabe-se que o dump restaura; não se sabe em quanto tempo o ambiente inteiro volta, nem se o `KIT_RECUPERACAO.md` está correto. | Antes de o portal do cliente entrar no ar — a partir daí, a indisponibilidade tem custo para terceiro. |
| **L07** — imagem servida ≠ imagem testada | O artefato em produção nunca passou pelo Trivy nem pelo pytest. Rollback leva minutos, e o PAT do `SharedAuth` continua no VPS. | Um deploy falhar por dependência resolvida diferente da testada; ou a F3 não bastar para eliminar surpresas de build. |
| **L19** — DuckDNS no site do cliente | Sufixo compartilhado, sem autoridade de domínio, sem e-mail corporativo. O SEO da F5 fica represado. | Antes de divulgar o site em cartão, proposta comercial ou anúncio — trocar depois de indexado exige 301 e paciência. |
| **L11** — repo do cliente sem branch protection | `main` do `mp-solucoes` aceita force-push e deleção; nenhum status check obrigatório. | O site passar a ter entrega contratada, ou mais de uma pessoa commitando. |

---

## 7. Trilha do ConfortoTermico (mestrado)

O ConfortoTermico sai do roadmap da frota. Continua no VPS, no `deploy.sh`, no
vigia, no backup e consumindo `SharedAuth` — só o código diverge (§2). O que
segue não tem prazo atado às fases e é sugestão, não plano.

**O que herda do levantamento e continua valendo:**

- **Os testes por inspeção de código-fonte.** `tests/test_authorization.py:47`
  verifica autorização com `inspect.getsource(auth)`, comparando **texto**; há
  mais cinco pontos assim, incluindo `test_troca_de_senha.py`. Esse é o tipo de
  teste que passa depois de uma refatoração que quebrou o comportamento, e
  falha depois de uma que não quebrou nada. Para um trabalho acadêmico, é o
  ponto mais frágil: o `AGENTS.md` já registra, corretamente, que "testes do
  código validam a implementação de software, não constituem validação
  acadêmica dos índices" — mas testes que leem o próprio código não validam nem
  a implementação.
- **O que vale mais, aqui, é outra coisa:** testes numéricos de
  `app/termico/thermal_indices.py` contra os exemplos normativos das fontes. É
  o que responde a "como você sabe que o software calcula o que você afirma?",
  e é uma pergunta razoável numa defesa.
- **A camada `db_backend.py`** (340 linhas, adaptador de `?`→`%s` escrito à
  mão, com conferência de aridade e cuidado com JSONB) permanece como decisão
  arquitetural livre. Não precisa mais convergir para ORM. O `AGENTS.md` dele
  já pede para não ampliar essa superfície — isso continua sendo bom conselho.
- **Os ~4.990 linhas de JavaScript próprio** deixam de ser dívida de
  padronização. Passam a ser simplesmente a arquitetura do projeto.
- **`migrations/env.py` tem o mesmo defeito latente que a F1 encontrou nos
  irmãos.** O `fileConfig(config.config_file_name)` roda com o padrão
  `disable_existing_loggers=True`, que desliga todo logger já existente no
  processo — inclusive o da aplicação. No contêiner nunca aparece, porque o
  job `schema` roda como processo separado; aparece no instante em que alguém
  aplicar migração dentro do mesmo processo, e o sintoma é a aplicação parar
  de registrar log em silêncio. **Corrigido em 07/09**, junto com MegaSena e
  ControleRendaVariavel: a correção é uma palavra,
  `disable_existing_loggers=False`. Foi a única intervenção deste levantamento
  no código do ConfortoTermico além das correções factuais de documentação —
  o defeito era idêntico ao dos irmãos e independe da arquitetura.

**O que muda de status:** nada do ConfortoTermico entra nas fases F0–F7,
exceto o item 1 e 2 da F6, que existem justamente para registrar a separação.

---

## 8. Matriz de achados

| # | Eixo | Achado | Imp. | Esf. | Situação |
|---|---|---|---|---|---|
| L01 | Verificação | Nenhuma app testa contra banco | Alto | G | **✅ F1** |
| L02 | Verificação | Teste de migração não aplica migração | Alto | M | **✅ F1** |
| L03 | Verificação | Piso de Python declarado e não testado | Médio | P | **✅ F1** |
| L04 | Processo | 5 commits parados em branches locais | Médio | P | **✅ F0** |
| L05 | Persistência | `media_volume` sem backup no VPS | Alto | M | risco aceito |
| L06 | Persistência | RTO nunca medido | Médio | M | risco aceito |
| L07 | Entrega | Imagem servida nunca testada nem varrida | Alto | G | risco aceito |
| L08 | Observab. | Sem visibilidade de erro de aplicação | Médio† | M | **F4** |
| L09 | Segurança | `manutencao` público com proteções off | Alto | P | **✅ F0** |
| L10 | Segurança | `non_provider_patterns` off nos 7 públicos | Médio | P | **❌ indisponível** |
| L11 | Segurança | Repo do cliente sem branch protection | Médio | P | risco aceito |
| L12 | Segurança | `AGENTS.md` nega CodeQL que existe | Baixo | P | **✅ F0** |
| L13 | Padroniz. | ConfortoTermico é outra arquitetura | Médio | P | **F6** (era G) |
| L14 | Padroniz. | `manutencao` sem ShellCheck/Dependabot | Médio | P | **✅ F0** |
| L15 | Performance | Adequada; gatilho documentado | Baixo | — | nada a fazer |
| L16 | Site | Dados de contato de exemplo em produção | Alto | P | **✅ F0** |
| L17 | Site | SPA por hash mata o SEO | Alto | M | **F5** |
| L18 | Site | Imagens sem `lazy`/dimensão | Médio | P | **F5** |
| L19 | Site | Domínio DuckDNS para cliente | Alto | P | risco aceito |
| L20 | Site | LGPD entra com o formulário | Médio | M | **F7** |
| L21 | Site | Portal nasce em Django, repo novo | — | G | **F7** |
| L22 | Processo | Documentação viva à deriva | Baixo | P | **✅ F0** |
| L23 | Entrega | Engrenagem de token do `SharedAuth` é peso morto | Médio | M | **✅ F3** |
| L24 | Segurança | 3 repos aceitavam action de terceiro | Alto | P | **✅ F0** |

† Alto assim que houver cliente.

**24 achados: 11 concluídos (7 no F0, 3 no F1, 1 no F3), 6 no plano, 5 riscos
aceitos com gatilho, 1 indisponível na plataforma e 1 sem ação.** Zero
críticos. Zero vulnerabilidades exploráveis.

Os itens 1 e 2 da F3 não têm número de achado — vieram da §3.2, e também estão
feitos.

---

## 9. Se você fizer só uma coisa

Ligue a suíte do **ControleBancario** ao Postgres que já está no
`compose.yaml` e escreva cinco testes: transferência interna, fechamento mensal
bloqueando mutação, idempotência da projeção recorrente, atomicidade de
operação composta, e `migrate` em banco vazio.

Meio dia. Cobre a aplicação que mexe com dinheiro e é a que hoje tem menos
rede. E o quinto teste, sozinho, corta o único encadeamento deste levantamento
que termina com dados errados em produção sem rollback possível.

---

*Levantamento conduzido em 07/09/2026 sobre os oito repositórios em
`MSPA-Coder`, no estado de `main` (e branches locais) daquela data, e revisado
no mesmo dia com as decisões da §2. Complementa a `AUDITORIA_2026-08.md` e o
`TESTE_FUNCIONAL_NAVEGADOR/` sem repeti-los: aqueles cobriram segurança de
aplicação e comportamento de interface; este cobre verificação, persistência,
entrega, observabilidade e plataforma.*
