# Plano de manutenção — 5 projetos

Documento vivo de retomada. Cada sessão nova (após reinício de limite de uso)
deve começar lendo este arquivo inteiro antes de qualquer ação. Ele não faz
parte de nenhum repositório Git dos projetos (fica em `_manutencao/`, fora de
todos eles) — é meta-informação da manutenção, não do produto.

Escopo: ConfortoTermico, ControleBancario, ControleRendaVariavel, MegaSena,
BackupRestore. Os quatro primeiros seguem a Base compartilhada de engenharia
v1.7 (bloco `SHARED-ENGINEERING-BASE` no `AGENTS.md` de cada um) — **esse
bloco nunca é editado** nesta manutenção, só as seções específicas de cada
projeto. BackupRestore não tem AGENTS.md ainda (ver Fase 5).

## Regras que governam esta manutenção (não só o código)

- Não mexer no bloco `SHARED-ENGINEERING-BASE` de nenhum AGENTS.md.
- Documentar só o estado atual — nunca narrar histórico de tentativas ou bugs
  já resolvidos (exigência já presente em todos os AGENTS.md dos 4 projetos).
- Nada de CI, suíte de regressão ampla, mypy ou auditoria de dependências —
  todos os 4 projetos têm desvio aprovado explícito dispensando isso.
- "Organizar diretórios" é conservador: corrigir arquivo fora de lugar, não
  reestruturar módulos já documentados como arquitetura atual (MegaSena
  AGENTS.md proíbe isso explicitamente; vale como princípio para os outros).
- "Otimizar" exige medição/justificativa concreta, não reescrita especulativa.
- Nenhuma ação destrutiva em dado real, dump ou segredo sem checar o conteúdo
  primeiro e, em caso de dúvida, perguntar ao mantenedor.
- Commits: autorizado pelo mantenedor em 2026-08-15 commitar em todos os
  projetos ("pode comitar todos os projetos"). Push continua exigindo
  autorização explícita separada — não foi dada ainda.
- Verificação de fechamento por projeto: `docker compose --profile quality
  run --rm quality` (ou equivalente do projeto) antes de considerar a Fase 6
  concluída.

## Estado geral (atualizar a cada sessão)

| Projeto | F1 Auditoria | F2 Higiene | F3 Diretórios | F4 Otimização | F5 Documentação | F6 Verificação | F7 Commit final |
|---|---|---|---|---|---|---|---|
| ConfortoTermico | ✅ | ✅ | ✅ (nada a fazer) | ✅ | ✅ | ✅ | ✅ (`8d43875`+`294c459`+`cb2cc23`) |
| ControleBancario | ✅ | ✅ | ✅ (nada a fazer) | ✅ | ✅ | ✅ | ✅ (`1efa1fc`+`e6b6eb9`) |
| ControleRendaVariavel | ✅ | ✅ | ✅ (nada a fazer) | ✅ | ✅ | ✅ | ✅ (`d38945d`+`ca546f1`+`870c3a2`) |
| MegaSena | ✅ | ✅ | ✅ (nada a fazer) | ✅ | ✅ | ✅ | ✅ (`30d3bad`) |
| BackupRestore | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (`cli.py verificar`) | ✅ (`47173ea`) |

Legenda: ⬜ pendente · 🔄 em andamento · ✅ concluído · ⏭️ pulado (motivo
registrado na seção do projeto) · ⚠️ bloqueado (aguardando decisão do
mantenedor, registrada na seção do projeto).

## Achados que já valem para todos os 4 projetos com base compartilhada

- Containers ativos no host no momento do levantamento (2026-08-15):
  ControleRendaVariavel (web+db, subiu ~31min antes) e ConfortoTermico
  (ict+coletor, subiu ~11h antes). Auditoria deve ser não-destrutiva o
  suficiente para não exigir derrubar esses containers.
- `.ruff_cache/` e `__pycache__/` aparecem soltos em vários projetos — checar
  se estão no `.gitignore` (esperado que sim) antes de qualquer limpeza.
- `ControleBancario/.claude/worktrees` e `ControleRendaVariavel/.claude/worktrees`
  existem — checar se são worktrees Git reais em uso ou lixo órfão de sessão
  anterior antes de tocar.
- `ConfortoTermico/instance/` tem dois `.dump` reais e `secret_key.txt` /
  `interno_token.txt` — **não são lixo**, são segredo/backup operacional.
  Confirmar apenas que não estão rastreados pelo Git; não apagar.
- `ControleRendaVariavel/.docker-local/` tem dumps reais
  (`pre-volume-rename.dump`, `pre_options.dump`, `pre_reference_tables.dump`)
  — parecem backups de segurança de uma migração de volume já concluída.
  Não apagar sem confirmar que não são mais necessários; é decisão do
  mantenedor, não limpeza automática.
- `ControleRendaVariavel/.venv/` é um virtualenv completo dentro do
  repositório (desvio aprovado do host Windows para o controlador RTD/COM).
  Confirmar que está no `.gitignore` e não rastreado; não é candidato a
  remoção, é parte do ambiente aprovado.

## Achados por projeto

### MegaSena (auditoria concluída, sessão 1)

- **Higiene**: limpa. `.gitignore`/`.dockerignore`/`.gitattributes` cobrem
  tudo corretamente. Nada rastreado por engano. F2 e F3 não têm trabalho —
  marcar como concluídas sem ação.
- **Divergência de documentação (achado grave, prioridade alta para F5)**:
  `docs/business-rules.md`, seção "Escopo de segurança" (linhas ~104-109),
  afirma *"Não há autenticação porque o produto foi desenhado para uso local
  e individual"* — **isso é falso hoje**. O commit `640e6f8 feat:
  autenticacao no MegaSena...` adicionou login obrigatório
  (`_require_login`, `PUBLIC_ENDPOINTS`, `app/web/auth.py`,
  `User`/hash de senha, migração `20260814_0002_users.py`) e não atualizou
  esse trecho da doc. `README.md` e `AGENTS.md` já descrevem a autenticação
  corretamente — só `business-rules.md` ficou para trás. Também falta
  mencionar autenticação em `docs/architecture.md` ("Módulos" / "Segurança e
  implantação").
- **Código morto / chaves sem leitor** (baixo risco, F4):
  - `app/draws/statistics.py::build_stats()` linha ~71: chave `"count"` sem
    leitor em nenhum template.
  - `app/bets/combinatorics.py::calculate_individual_filter_targets()`
    linhas ~360-367: `metric()` retorna `count`/`percentage`/
    `percentage_text` por parâmetro e a chave de topo `target_count` — só
    `targets.parameters[name].value` e `targets.total` têm leitor em
    `app/templates/bets/_filter_targets.html`.
  - `requirements.txt::defusedxml` sem `import` direto — proteção indireta
    via `openpyxl`; merece um comentário explicando, não é remoção.
  - Nomenclatura confusa (não é bug): `_import_feedback()` em
    `app/web/contests.py` na verdade renderiza `_import_response.html`,
    enquanto existe também `_import_feedback.html` usado só pelo handler
    413. Renomear um dos dois evita erro de manutenção futuro.
- **Risco que exige decisão** (registrar, não resolver sozinho no código):
  `test_authorization.py` (um dos 5 arquivos fixos da suíte mínima, base
  compartilhada linha 251) não existe neste projeto — plausível porque
  `MegaSena` não tem papéis/autorização diferenciada (só autenticação), mas
  a base exige que toda exceção seja **registrada** na seção "Desvios
  aprovados" do `AGENTS.md` do projeto, e essa exceção específica ainda não
  está lá. Ação proposta para F5: registrar a exceção por escrito (não
  criar o teste, já que não há papel a testar).
- **Arquivos fora de lugar**: nenhum.
- Sem trabalho de F2/F3. F4 e F5 ficam para execução na Fase de escrita.

### ControleRendaVariavel (auditoria concluída, sessão 1)

Árvore limpa (pós-commit `d38945d`), `.gitignore` sem gaps, nenhum worktree
Git real além do principal.

- **Higiene — decisão do mantenedor pendente (F2)**:
  - `.docker-local/pre-volume-rename.dump(+.list)`, `pre_options.dump`,
    `pre_reference_tables.dump` (27-28/07) protegiam as 19 revisões Alembic
    incrementais que existiam antes do commit `87d32dc` (14/08), que as
    consolidou numa baseline única. Essas revisões incrementais **não
    existem mais no repo** — restaurar esses dumps hoje deixaria o banco
    sem caminho de migração Alembic disponível. Agente recomenda
    arquivar/descartar; **pedir confirmação ao mantenedor antes de apagar**
    (dado real, regra "nunca apagar sem substituto").
  - `.claude/worktrees/gracious-chebyshev-31fdae` — diretório vazio, não é
    worktree Git real (`git worktree list` não lista). Lixo órfão, seguro
    remover.
  - `Dockerfile` monta um build secret opcional `host_ca` (linhas 18-22,
    36-40) que `compose.yaml` não declara em lugar nenhum — ou é
    infraestrutura não documentada (proxy corporativo com TLS inspection?)
    ou vestígio de ambiente que não existe mais. `.docker-local/host-ca.crt`
    /`.der` (mesma época dos dumps antigos) reforçam a hipótese de
    vestígio. Perguntar ao mantenedor.
  - `backups/` está vazio apesar do fluxo documentado (`scripts/backup.ps1`,
    `README.md`, `.dropboxignore`) supor backups diários — confirmar se o
    agendamento está rodando de fato.
- **Divergência de documentação (F5)**:
  - `docs/planilha-acoes.md:59` referencia
    `docs/plano-carteiras-e-transacoes-opcoes.md`, removido no commit
    `87d32dc` — link morto, corrigir/remover a menção.
  - `docs/plano-performance-twr.md`: os dois tópicos (TWR e ciclo de vida
    do host) estão implementados no código. Falta migrar o contrato TWR
    (net_flow, rateio de proventos, colunas novas) para
    `docs/planilha-acoes.md`/`planilha-opcoes.md` (os contratos normativos)
    e então aposentar o plano, como o próprio plano prevê. Tópico 2 só
    falta a validação manual de logoff/logon (não é algo que eu resolvo
    remotamente — é ação do mantenedor no Windows).
  - "Limitações documentadas" do plano (6 itens de comportamento aceito por
    design, ex. `ADJUSTMENT` datado com `date.today()`) não estão nos docs
    de contrato — avaliar se merecem migrar junto.
- **Código morto (F4)**:
  - `scripts/backfill_open_real_transactions.py` **quebrado hoje**:
    importa `PositionKind`, que não existe mais desde a introdução de
    `Portfolio`. `ImportError` garantido se executado. Script de uso único
    já expirado — candidato a remoção direta (baixo risco, já não
    funciona).
  - `scripts/backfill_open_option_transactions.py` ainda roda mas é
    migração de uso único do WP4b, já concluído e hoje automático — mesma
    categoria, mas funcional; decisão do mantenedor entre manter ou remover.
- **Otimização**: nada de novo — as otimizações relevantes (evitar N+1,
  O(n) na sombra de benchmark) já foram feitas conforme
  `docs/plano-performance-twr.md`. Agente preferiu não inventar itens
  fracos.
- **Arquivos fora de lugar**: nenhum.

### ConfortoTermico (auditoria concluída, sessão 1)

Árvore limpa. `instance/` (dumps + secret_key.txt/interno_token.txt) e
`.secrets/` confirmados **ignorados**, nunca rastreados — achado prévio de
risco não se confirmou, projeto está limpo nesse quesito.

- **⚠️ Achado de segurança real (prioridade alta, decisão do mantenedor)**:
  `app/auth.py:179-200` (`obter_ou_criar_chave_secreta`), chamada em
  `app/app_factory.py:225` — se `CONFORTO_SECRET_KEY` não está no ambiente,
  a função **gera e persiste** uma chave em `instance/secret_key.txt` em vez
  de falhar a subida. `compose.yaml` confirmadamente **não** define
  `CONFORTO_SECRET_KEY` nem tem Docker secret para isso (só
  `postgres_password` e `internal_token` são secrets reais) — ou seja, na
  pilha real documentada, o fallback autogerado é sempre o caminho tomado.
  Isso contradiz textualmente a "Linha de base de segurança" do próprio
  `AGENTS.md` ("Segredos não têm valor padrão... a aplicação falha ao subir
  se faltarem... Nunca gere segredo efêmero como fallback") e **não está
  registrado** em "Desvios aprovados". É atenuado (persiste em disco, não
  regenera a cada boot) mas ainda viola a regra central. Duas saídas
  possíveis: (a) registrar como desvio aprovado explicando a razão já
  presente no código, ou (b) exigir `CONFORTO_SECRET_KEY`/secret Docker
  dedicado e falhar ao subir sem ele. **Não decidir sozinho — perguntar.**
- **⚠️ Achado de cobertura de teste (decisão do mantenedor)**: a suíte
  mínima de segurança é inteiramente "caixa-branca" via
  `inspect.getsource()`/comparação de constantes — nenhum dos 5 arquivos
  instancia `criar_app_ict()` nem usa `app.test_client()`. Uma regressão
  real (ex.: remover `auth.registrar_autenticacao(app)` do factory,
  desprotegendo todas as rotas) **não seria pega por nenhum teste atual** —
  exatamente o cenário que a suíte mínima existe para prevenir, segundo o
  próprio `AGENTS.md`. Razão documentada: o factory conecta a banco e a
  suíte foi desenhada para não depender de banco. Tensão de desenho
  legítima, mas vale decidir conscientemente (aceitar e documentar, ou
  adicionar 1 teste com banco descartável que monte o factory de verdade
  dentro do orçamento de 30s).
- **Divergência de documentação (F5, sem risco, pode executar)**:
  - `docs/RUNBOOK.md:49-59` ("Verificação estática") documenta só
    `docker run ... ruff check/format` — **nunca roda a suíte mínima**.
    O comando correto (`docker compose --env-file .env.docker --profile
    quality run --rm quality`) já está certo em README/AGENTS.md; só o
    RUNBOOK ficou para trás.
  - `app/app_factory.py:179-185` tem comentário órfão citando
    `tests/__init__.py` (não existe) como quem liga `CONFORTO_TESTING`.
  - `requirements-dev.txt:3-5` descreve uma suíte baseada em
    `app.test_client()` que não é o que os 5 testes atuais fazem (são
    caixa-branca). Ambos os comentários descrevem uma suíte anterior à
    reescrita (provável commit `9b2ec7a`).
- **Código morto (F4, baixo risco)**:
  - `app/cache.py`: método `cached()` (decorator, linhas ~129-166) e
    `stats()` (~112-127) sem nenhum consumidor — `database_configuracoes.py`
    usa só `.get()/.set()/.delete()`. ~55 linhas removíveis.
  - `backups/` (raiz, vazio, gitignorado) parece resíduo de convenção
    anterior — a rotina de backup real grava em `instance/` hoje. Não é
    rastreado pelo Git, então é limpeza de disco local, não do repositório.
- **Otimização concreta (F4)**: N+1 real em
  `app/database_leituras.py:155-185` (`obter_historicos_recentes_zonas`,
  usada pelo polling do Dashboard a cada 3s) — fallback por zona sem
  leitura recente faz 1 query por zona num loop; falta índice `(zona_id,
  id)` para essa query específica (os índices existentes são todos
  compostos com `indice`/`criado_em` primeiro). Baixo impacto hoje (poucas
  zonas), mas concreto.
- **Arquivos fora de lugar**: `docs/ANALISE_DE_DADOS.pdf` não é órfão (citado
  em comentário) mas não é mencionado no README — lacuna pequena de
  descoberta, não um problema de organização.

### ControleBancario (auditoria concluída, sessão 1)

Árvore limpa. Nota: o relatório deste agente veio com uma tag do harness
avisando que um trecho leu como "instruction-shaped" (por causa do conteúdo
de `.claude/settings.local.json`, que é só um allowlist de permissões
acumulado de sessões anteriores da própria ferramenta) — conferido, não é
injeção real, é só o agente descrevendo o conteúdo desse arquivo de
configuração local. Nada a agir sobre isso além do achado de `.gitignore`
abaixo.

- **⚠️ Achado de segurança real (prioridade alta, decisão do mantenedor)**:
  `financeiro/settings.py:98-99` — `POSTGRES_USER`/`POSTGRES_PASSWORD` caem
  para o padrão `'postgres'`/`'postgres'` via `os.environ.get(..., 'postgres')`
  se a variável faltar. `SECRET_KEY` no mesmo arquivo segue corretamente o
  padrão fail-fast (`RuntimeError` sem valor). `compose.yaml` protege a
  subida normal (`${POSTGRES_PASSWORD:?Defina...}`), mas o Django em si
  aceitaria a credencial padrão conhecida se rodado fora desse caminho
  (`manage.py` direto, outro orquestrador). Mesma categoria do achado do
  ConfortoTermico (SECRET_KEY) — violação textual da "Linha de base de
  segurança" do `AGENTS.md`, não registrada como desvio.
- **⚠️ Achado de segurança real (prioridade alta, decisão do mantenedor)**:
  Django Admin habilitado (`INSTALLED_APPS`, `/admin/` roteado) e
  parcialmente registrado — `bank_statements/admin.py` expõe
  `BankStatementImportAdmin`/`BankStatementLineAdmin` com list/search
  completos, autorizado por `is_staff`/`is_superuser` do Django, um sistema
  **paralelo e diferente** do `AppPermissionBackend`/`accessible_owner_ids`
  que todas as telas da aplicação usam. Um staff/superuser veria extratos de
  todas as contas via `/admin/`, sem o escopo por titular. Os outros 7 apps
  têm `admin.py` vazio (boilerplate) — parece scaffolding esquecida, não
  decisão deliberada. Nenhum doc menciona `/admin/` como interface
  suportada. Decisão: remover os registros (e possivelmente
  `django.contrib.admin` de `INSTALLED_APPS`), ou documentar/restringir
  intencionalmente.
- **Higiene (F2, pode executar)**:
  - `.claude/worktrees/` vazio, não é worktree Git real (`git worktree
    list` só mostra o principal) — lixo órfão, seguro remover.
  - **Gap real**: `.claude/` não está excluído em `.gitignore` nem
    `.dropboxignore`, apesar de `.codex/`/`.agents/` (outras ferramentas)
    estarem. Nada rastreado hoje, mas sincroniza pelo Dropbox sem exclusão
    — risco se worktrees Git voltarem a ser usados ali. Adicionar exclusão.
  - `logs/`, `backups/`, `.ruff_cache/`: todos limpos e corretamente
    ignorados, sem ação necessária.
- **Divergência de documentação (F5, sem risco, pode executar)**:
  - **Achado importante**: o comando real da suíte mínima
    (`docker compose --profile quality run --rm quality`) só existe como
    **comentário** em `compose.yaml:86` — não está em `AGENTS.md` (que só
    lista `ruff check`/`manage.py check`/`up --build`), nem em `README.md`,
    nem em `TESTING.md`. Pior: o comando que `TESTING.md:28` documenta
    (`exec web ... ruff check`) **vai falhar** — o serviço `web` usa o
    estágio `runtime`, que não instala `ruff`/`pytest` (só em
    `requirements-dev.txt`, exclusivo do estágio `quality`). Isso é
    exatamente o tipo de lacuna que a base compartilhada trata como
    inaceitável (suíte que protege acesso precisa ser fácil de rodar
    corretamente). Corrigir AGENTS.md/README/TESTING.md com o comando certo.
  - `AGENTS.md`/`CONTEXT.md` citam a migration `core.0002` como origem da
    conversão para `timestamptz` — essa migration foi absorvida na
    consolidação de baseline (commit `14825fb`); hoje é `core/0001_initial.py`.
    O invariante continua verdadeiro, só o nome do arquivo citado mudou.
- **Código morto**: nenhum candidato real encontrado (views/urls/templates
  todos com consumidor confirmado; os 7 "candidatos" automáticos eram todos
  falsos positivos — template filters Django usados nos templates).
- **Otimização concreta (F4)**:
  - N+1 em `bank_statements/reconciliation.py::reconciliation_view_data`
    (linhas ~122-123): até 100 queries extras (uma por linha de extrato) em
    `candidate_entries_for_line`; resolver com uma consulta agrupada por
    `(account_id, entry_type, entry_amount)`, no mesmo espírito do batching
    já usado em `transactions/services.py::counterparty_account_map`.
  - `reports/services.py::projection_months_between` (linhas ~548-598): até
    2N queries agregadas para N meses de projeção, em vez de uma query
    `TruncMonth`+`Sum`+`GROUP BY` como `dashboard/views.py::dashboard_view`
    já faz para o mesmo tipo de total multi-mês.
- **Arquivos fora de lugar**: nenhum.

### BackupRestore (auditoria concluída, sessão 1)

Sem AGENTS.md ainda. Nenhum segredo real versionado hoje.

- **⚠️ Achado de decisão de produto (prioridade alta)**: entre os dois
  commits do projeto, o artefato `config` (zip de `.env*`, `.secrets/`,
  `.certs/`, `.docker-local/` — necessário para reconstruir um projeto do
  zero, ex. sem `.certs/local-root-ca.crt` o `compose.yaml` nem constrói)
  foi **removido silenciosamente** de `motor.py`/`projetos.py`. Hoje um
  backup deste sistema **não reconstrói um projeto do zero**. `RESTAURAR.md`
  documenta a consequência honestamente, mas em nenhum lugar há o motivo da
  decisão. `motor.py` ficou com 4 funções órfãs do artefato removido
  (`_gerar_bundle`, `verificar_bundle`, `_gerar_config`, `verificar_config`)
  e `_gerar_config` tem um bug latente (referencia `CAMINHOS_CONFIG`/
  `SUFIXOS_IGNORADOS_CONFIG`, que não existem mais — `NameError` se
  reativada sem notar). Decisão: (a) reimplementar o artefato config, ou
  (b) formalizar a exclusão por escrito e limpar o código órfão.
- **Achado de higiene (baixa severidade, decisão do mantenedor)**:
  `catalogo.sqlite3` foi commitado no commit inicial (`916fa4d`) e removido
  no `7ec08a2` (quando o `.gitignore` foi criado) — o blob continua
  recuperável via `git show 916fa4d:catalogo.sqlite3` enquanto o histórico
  não for reescrito. Conteúdo real inspecionado: 20 artefatos, sem
  credenciais (coerente com o desenho "sem senha guardada"). Baixo risco,
  mas reescrever histórico é barato agora (2 commits) e caro depois —
  decisão do mantenedor se vale a pena.
- **Quatro caminhos diferentes de "raiz de backup"** documentados/configurados
  (README/RESTAURAR prosa, `configuracao.py:RAIZ_PADRAO`,
  `configuracao.local.json` real = `D:\Backups\BackupRestore`, mount do
  `compose.teste.yaml` = um quarto valor não lido por nenhum código).
  Confirmar qual é o real e generalizar os exemplos na doc.
- **Documentação (F5, pode executar após decisão do item de config)**:
  - `README.md` linha ~49: "Três artefatos por projeto" mas a tabela lista
    só dois — resíduo textual de antes da remoção do artefato config.
  - `RESTAURAR.md`: numeração pula de "1. Código" para "3. Subir só o
    banco" — faltou renumerar depois de remover o passo 2 (Configuração).
  - `ESPECIFICACAO.md` está completamente descolada do sistema real (Docker
    Compose, SQLAlchemy, fila de jobs, criptografia — nada disso existe).
    `claude-PLANO.md` também já diverge (descreve `git bundle` + config
    "não opcional", nenhum dos dois sobreviveu). Proposta do agente: mover
    os 4 arquivos (`ESPECIFICACAO.md` + 3 `claude-*.md`) para
    `docs/historico/` ou marcar cada um com um banner "superado por
    README.md/RESTAURAR.md" — não decidir sozinho, mas é baixo risco.
- **Código morto (F4, baixo risco, mas ligado à decisão do item de config)**:
  `index.html`/`app.js`/`styles.css` na raiz confirmados inalcançáveis por
  qualquer rota Flask (não passa de resíduo do protótipo) — mover para
  `docs/prototipo/` ou remover.
- **Proposta de `AGENTS.md`** (F5): o agente redigiu uma proposta completa
  de conteúdo — papel host-only, sem ORM por decisão, interpretador Python
  correto, as sete regras de `motor.py`/`restaurar.py` como invariantes,
  comandos de verificação (`cli.py verificar`/`cli.py ensaio` substituem a
  suíte mínima dos irmãos), e o aviso explícito de não "consertar" o
  artefato config sozinho. Usar como base ao criar o arquivo.
- Sem testes automatizados (`pytest --collect-only` = 0 coletados) — não é
  falha a corrigir, `cli.py ensaio` cumpre esse papel.

### ConfortoTermico — executado (sessão 1)

Commit `8d43875`: registrado desvio SECRET_KEY em AGENTS.md (decisão do
mantenedor: manter fallback, documentar), corrigido `docs/RUNBOOK.md` para
usar `docker compose --profile quality run --rm quality`, corrigidos 2
comentários órfãos, removido `cache.cached()`/`stats()` sem consumidor.
Suíte mínima + Ruff passaram (32 testes) antes do commit.

**Ainda pendente, não decidido nesta sessão**:
- N+1 em `app/database_leituras.py::obter_historicos_recentes_zonas`
  (fallback por zona sem leitura recente) + índice `(zona_id, id)` faltando
  — requer medir impacto real e, se valer a pena, uma migração Alembic.
  Baixo impacto hoje (poucas zonas). Deixado para outra sessão.
- Suíte mínima 100% caixa-branca não pega remoção de
  `auth.registrar_autenticacao(app)` do factory — risco de desenho
  registrado no achado da auditoria, mas não perguntei ao mantenedor o que
  fazer. Precisa de decisão numa próxima sessão.
- `backups/` (raiz, vazio, não rastreado) — resíduo de disco local, baixa
  prioridade, não removido ainda.

### ControleBancario — executado (sessão 1)

Commit `1efa1fc`: removido Django Admin de `bank_statements/admin.py`
(decidido pelo mantenedor), corrigidos AGENTS.md/README.md/TESTING.md para
o comando de verificação real (`--profile quality run --rm quality` —
`exec web ... ruff` nunca funcionou, `web` usa estágio `runtime` sem
ruff/pytest), corrigida referência a `core.0002`, registrado desvio
POSTGRES_USER/PASSWORD em AGENTS.md (decisão: manter fallback,
documentar), removido `.claude/worktrees/` órfão. Suíte mínima + Ruff
passaram (52 testes) antes do commit. `.claude/` também excluído do
núcleo comum de `.gitignore`/`.dropboxignore` nos 4 projetos-irmãos
(commit `294c459` no ConfortoTermico; será incluído nos commits de
ControleRendaVariavel e MegaSena quando chegar a vez deles).

**Ainda pendente, não decidido nesta sessão**:
- N+1 em `bank_statements/reconciliation.py::reconciliation_view_data`
  (até 100 queries extras) e loop mês-a-mês em
  `reports/services.py::projection_months_between` — otimizações
  concretas, mas médio esforço/risco sem suíte de regressão para pegar
  regressão sutil. Deixado para outra sessão dedicada.

### ControleRendaVariavel — executado (sessão 1)

Commit `ca546f1`: descartados os 3 dumps antigos em `.docker-local/`
(decidido pelo mantenedor), removido `scripts/backfill_open_real_transactions.py`
(já quebrado, `ImportError` garantido), corrigido link morto em
`docs/planilha-acoes.md:59`. `.claude/` incluído no gitignore/dropboxignore
sincronizados. Suíte mínima + Ruff passaram (85 testes) antes do commit.

**Não consegui**: `.claude/worktrees/gracious-chebyshev-31fdae` (diretório
vazio, sem worktree Git real associado) deu "Device or resource busy" ao
tentar remover — provavelmente um handle do Windows/Dropbox preso nele.
Baixa prioridade; tentar de novo numa sessão futura ou o mantenedor remove
manualmente pelo Explorer.

**Ainda pendente, não decidido nesta sessão**:
- `scripts/backfill_open_option_transactions.py` — ainda funcional mas é
  migração de uso único do WP4b, já concluído e automático hoje. Manter ou
  remover é decisão do mantenedor, não perguntei.
- Build secret `host_ca` no `Dockerfile` sem wiring em `compose.yaml` nem
  documentação — vestígio ou infraestrutura real não documentada?
- `docs/plano-performance-twr.md`: falta migrar o contrato TWR para
  `docs/planilha-acoes.md`/`planilha-opcoes.md` e então aposentar o plano —
  reescrita de doc substancial, fica para uma sessão dedicada.
- `backups/` vazio: confirmei que **não há tarefa agendada** registrada no
  Windows Task Scheduler para `scripts/backup.ps1` deste projeto
  (`schtasks /query` não encontrou nada) — se o mantenedor espera backup
  diário automático, ele não está rodando hoje. Só reportando, não é algo
  que eu resolvo sozinho (decisão de agendar ou não).

### MegaSena — executado (sessão 1)

Commit `30d3bad`: corrigida afirmação falsa de "sem autenticação" em
`docs/business-rules.md` e lacuna equivalente em `docs/architecture.md`,
registrado desvio `test_authorization.py` ausente em AGENTS.md, removidas
chaves de contexto sem leitor em `build_stats()` e
`calculate_individual_filter_targets()`, comentado `defusedxml` em
`requirements.txt`. Suíte mínima + Ruff passaram (25 testes) antes do
commit. MegaSena é o único dos 4 projetos com base compartilhada que
terminou **todas as 7 fases nesta sessão** — nada pendente.

### BackupRestore — executado (sessão 1)

Commit `47173ea`: criado `AGENTS.md` próprio (deliberadamente sem o bloco
`SHARED-ENGINEERING-BASE` — justificativa no próprio arquivo), removido
código órfão do artefato `config` em `motor.py` (`_gerar_bundle`,
`_gerar_config`, `verificar_bundle`, `verificar_config`) e a constraint
correspondente em `banco.py`, decisão de exclusão documentada no topo de
`motor.py`, corrigidos README.md/RESTAURAR.md, movidos `index.html`/
`app.js`/`styles.css` para `docs/prototipo/` e os 4 docs de decisão
divergentes para `docs/historico/` (cada um com nota do que diverge),
genericizados caminhos hardcoded. Validado com `cli.py verificar` contra o
catálogo real: 8/8 artefatos íntegros.

**Ainda pendente, não decidido nesta sessão**:
- `catalogo.sqlite3` do commit inicial (`916fa4d`) continua recuperável do
  histórico Git (`git show 916fa4d:catalogo.sqlite3`) — conteúdo sem
  credenciais, baixo risco. Reescrever histórico (`git filter-repo`/BFG) é
  barato agora (poucos commits) e caro depois; decisão do mantenedor.

## Pendências gerais

Nenhuma. Os 3 itens que restavam depois da sessão 2 foram resolvidos na
sessão 3, com autorização explícita do mantenedor para cada um. Ver "Sessão
3" no log abaixo para o que cada um exigiu de fato.

Achado à parte (não pedido, resolvido no mesmo fôlego): um evento externo
(provável reinício do Docker Desktop) derrubou todos os containers da
máquina no início da sessão 3. ConfortoTermico e ControleRendaVariavel
voltaram sozinhos (`restart: unless-stopped`); MegaSena não tem essa
política e ficou parado — foi religado manualmente e a integridade dos
dados foi confirmada (3044 registros em `draws`). Vale considerar adicionar
`restart: unless-stopped` ao `compose.yaml` do MegaSena numa próxima sessão
(mesmo padrão já usado nos outros 3 projetos), mas não fiz sem perguntar,
já que é fora do que foi pedido nesta rodada.

## Log de sessões

### Sessão 1 — 2026-08-15

- Levantamento inicial dos 5 projetos: leitura dos 4 `AGENTS.md` (base
  compartilhada v1.7 idêntica + seções específicas), leitura do README/docs
  do BackupRestore (que não tem AGENTS.md), checagem de `git status`/`git
  log` nos 5, checagem de Docker ativo, levantamento de estrutura de
  diretórios (profundidade 2) dos 4 projetos com base compartilhada.
- Achado: ControleRendaVariavel tinha mudanças não commitadas — um refactor
  completo e coerente do ciclo de vida do host RTD (consolidação de
  `start.ps1`/`stop.ps1`/`rtd-automation.ps1` em `scripts/rtd-host.ps1` +
  `app/host_bootstrap.py`/`app/host_env.py`, com testes novos). Rodei
  `docker compose --profile quality run --rm quality` antes de commitar: 85
  testes passaram, ruff limpo. Mantenedor autorizou commitar em todos os
  projetos; commitado como `d38945d` no branch `performance-twr` (não é
  push, só commit local).
- Próximo passo: Fase 1 (auditoria completa, só leitura) dos 5 projetos,
  delegada a agentes em paralelo, para levantar candidatos concretos de
  limpeza/organização/documentação antes de qualquer escrita.
- **Continuação da sessão 1**: os 5 agentes de auditoria voltaram (achados
  completos nas seções "Achados por projeto" acima). Consolidei e levei 4
  decisões de segurança/produto ao mantenedor via pergunta direta: (1)
  SECRET_KEY/POSTGRES_PASSWORD com fallback inseguro → manter e documentar
  como desvio aprovado; (2) Django Admin no ControleBancario bypassando
  `accessible_owner_ids` → remover; (3) artefato `config` removido
  silenciosamente no BackupRestore → formalizar a exclusão e limpar código
  órfão; (4) dumps antigos em `.docker-local/` do ControleRendaVariavel →
  descartar. Executei as 4 fases (Fases 2-7) nos 5 projetos, cada um
  verificado (`docker compose --profile quality run --rm quality` nos 4 com
  base compartilhada — todos passaram; `cli.py verificar` no BackupRestore —
  8/8 artefatos íntegros) e commitado separadamente:
  - ConfortoTermico `8d43875` + `294c459`
  - ControleBancario `1efa1fc`
  - ControleRendaVariavel `ca546f1` (além do `d38945d` do WIP commitado no
    início da sessão)
  - MegaSena `30d3bad` — único projeto com as 7 fases 100% concluídas
  - BackupRestore `47173ea`
  - Nenhum `git push` foi feito — só commits locais.
  - Pendências que ficaram deliberadamente de fora estão listadas em
    "Pendências gerais para a próxima sessão", acima.

### Sessão 2 — 2026-08-15 (continuação, mesma conversa)

Mantenedor pediu para prosseguir até o final. Resolvi as pendências da
sessão 1, exceto duas que são decisão do mantenedor por natureza (histórico
Git, tarefa agendada) — ver "Pendências gerais", que foi reescrita para
refletir isso.

- **ControleRendaVariavel** (commit `870c3a2`): o build secret `host_ca`
  não era vestígio — é a mesma infraestrutura de CA local opcional que
  ConfortoTermico/ControleBancario/MegaSena têm (`local_ca`), só que aqui
  nunca foi declarada em `compose.yaml` (silenciosamente nunca funcionaria)
  e com nome diferente. Alinhado aos 3 irmãos: renomeado, declarado em
  `compose.yaml`, certificado movido para `.certs/local-root-ca.crt`.
  Validado com `docker compose build --no-cache`. Removido
  `scripts/backfill_open_option_transactions.py` (confirmado com o banco
  real: 0 posições ainda precisavam do backfill, e o script nem é copiado
  para a imagem Docker). Migrado o contrato TWR de
  `docs/plano-performance-twr.md` para `docs/planilha-acoes.md` ("Performance
  mensal") e removido o arquivo de plano, como ele mesmo previa; corrigidas
  as 3 referências no código que apontavam para o arquivo removido. A
  validação manual pendente do Tópico 2 (logoff/logon) virou uma nota no
  README em vez de um documento inteiro. Tentei remover
  `.claude/worktrees/gracious-chebyshev-31fdae` de novo — continua
  "Device or resource busy", registrado como pendência de baixa prioridade.
- **ConfortoTermico** (commit `cb2cc23`): corrigido o N+1 de
  `obter_historicos_recentes_zonas` com uma consulta em janela por partição
  (`ROW_NUMBER() OVER (PARTITION BY zona_id ...)`) cobrindo todas as zonas
  do fallback de uma vez — validado com comparação direta contra a versão
  antiga usando o banco real (resultado byte-a-byte idêntico). Migração
  nova para o índice `(zona_id, id)` em `historico.leituras`: backup
  (`pg_dump`) validado antes, migração aplicada no banco real, bootstrap
  confirmado do zero num PostgreSQL vazio na mesma rede Docker. Acrescentado
  teste que fecha a lacuna de cobertura registrada na sessão 1: nenhum
  teste garantia que `criar_app_ict()` chama `auth.registrar_autenticacao`
  — agora garante, no mesmo estilo caixa-branca da suíte existente
  (`inspect.getsource`), sem introduzir dependência de banco na suíte.
- **ControleBancario** (commit `e6b6eb9`): as duas otimizações N+1
  deixadas pendentes na sessão 1 foram implementadas e validadas
  extensivamente contra o banco real antes de commitar — `candidate_entries_for_lines`
  (conciliação, agrupada por conta/tipo/valor, testada com 200 linhas
  sintéticas construídas a partir de lançamentos reais, 138 candidatos,
  zero divergência) e a reescrita de `projection_months_between`
  (`TruncMonth`+`Sum`+`GROUP BY` em vez de uma consulta por mês, testada em
  20 cenários reais — 5 combinações de conta/período × 4 modos — contra
  `decimal_period_start_balance`, que continua no código para outros usos).
- Containers subidos só para validação (ControleBancario) foram derrubados
  ao final (`docker compose down`, sem `-v`) para devolver o estado
  anterior à sessão; os que já estavam rodando antes (ConfortoTermico,
  ControleRendaVariavel) não foram parados.
- Nenhum `git push` foi feito em nenhum projeto, nesta nem na sessão
  anterior.

### Sessão 3 — 2026-08-15 (continuação, mesma conversa)

Mantenedor autorizou os 3 itens pendentes ("sim para os 3 itens"), pedindo
antes uma checagem de saúde dos containers.

- **Checagem de saúde**: um evento externo derrubou todos os containers
  ~7-8min antes (provável reinício do Docker Desktop — todos saíram no
  mesmo instante, `exited (255)`). ConfortoTermico e ControleRendaVariavel
  voltaram sozinhos (`restart: unless-stopped`); MegaSena não tem essa
  política e ficou parado. Religado manualmente
  (`docker compose up -d`), confirmada integridade dos dados (3044 linhas
  em `draws`) e saúde de todos os 7 containers dos 3 projetos com stack
  ativa.
- **ControleRendaVariavel — `.claude/worktrees/gracious-chebyshev-31fdae`**:
  terceira tentativa de remoção teve sucesso (o handle que prendia o
  diretório nas duas tentativas anteriores havia liberado). Diretório não
  rastreado pelo Git — sem commit associado.
- **ControleRendaVariavel — tarefa agendada**: criada
  `schtasks /create /tn "ControleRendaVariavel Backup" ... /sc daily /st
  02:00` rodando `scripts/backup.ps1` (mesmo padrão do `BackupRestore` e do
  `rtd-host.ps1 -Action Install`, sem elevação). Validada rodando uma vez
  na hora (`schtasks /run`): produziu `backups/investimentos_2026-08-15_060411.dump`,
  195 entradas no TOC, `pg_restore --list` passou, resultado da tarefa = 0.
- **BackupRestore — reescrita de histórico Git**: achado crítico durante a
  execução — **o registro da sessão 1/2 estava errado**: o repositório TEM
  remote real (`github.com/MSPA-Coder/BackupRestore`, **público**), com
  `origin/main` e a tag `V1.0` apontando para um commit cujo ancestral
  (`916fa4d`) continha o `catalogo.sqlite3`. Ou seja, o arquivo estava
  publicamente acessível no GitHub, não só localmente. Parei e voltei ao
  mantenedor com a informação corrigida antes de agir — confirmou o
  force-push sabendo do risco. Executado: backup completo do diretório do
  repo (cópia física, não só o dump) antes de qualquer coisa; instalado
  `git-filter-repo` via pip (ferramenta recomendada oficialmente pelo Git
  para isso); `git filter-repo --path catalogo.sqlite3 --invert-paths
  --force`; verificado que o arquivo sumiu de todo o histórico
  (`git log --all --full-history`), que a árvore de trabalho ficou
  byte-a-byte idêntica à cópia de segurança (`diff -rq`), e que `git fsck
  --full --unreachable` não apontou objeto órfão (o commit "amend"
  intermediário `36b7004`, só no reflog, também foi limpo). Reconectado o
  remote (removido pelo filter-repo por segurança) e feito
  `git push --force` em `main` e na tag `V1.0`; confirmado via
  `git ls-remote` que o GitHub reflete a nova história. Hashes mudaram:
  `916fa4d→9243661`, `7ec08a2→2ca1972` (tag `V1.0` agora aqui),
  `47173ea→5a2caf3`. Cópia de segurança do repo pré-reescrita fica em
  `_manutencao/` fora do Git — ver nota abaixo.
- **Nota para quem ler isto depois** — **resolvida em 2026-08-20**: a cópia
  de segurança completa do BackupRestore antes da reescrita
  (`_manutencao/BackupRestore_backup_pre_filter_repo_20260815/`) foi apagada
  a pedido do mantenedor. O histórico reescrito (`git filter-repo`, seção
  acima) já está confirmado no GitHub desde 2026-08-15; a cópia física era
  só rede de segurança para o caso de a reescrita precisar ser desfeita.

Todas as pendências fechadas. Nenhum `git push` foi feito em nenhum outro
projeto além do BackupRestore (que foi o único autorizado nesta sessão).
