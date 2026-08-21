# Plano — uniformizar as rotinas de login e mensagens entre os 4 projetos

Iniciado e **concluído** em 2026-08-20: as seis fases mescladas e em
produção nos três apps Flask, com o ControleBancario acompanhando a política.
A rodada seguinte é o [PLANO_EQUALIZAR_BASE_COMPARTILHADA.md](PLANO_EQUALIZAR_BASE_COMPARTILHADA.md).

Documentos irmãos: [PLANO_RETIRAR_BACKUPS_LOCAIS.md](PLANO_RETIRAR_BACKUPS_LOCAIS.md)
é o mesmo tipo de trabalho aplicado ao backup — a referência de forma e de
risco para este plano.

---

## 1. O problema, em uma frase

Os quatro projetos com login (ConfortoTermico, MegaSena, ControleBancario,
ControleRendaVariavel) resolvem o mesmo conjunto de rotinas — sessão, CSRF,
hash de senha, limite de tentativas, criação do primeiro usuário, tela de
administração de contas — de quatro jeitos diferentes, escritos em momentos
diferentes, sem nunca terem sido comparados lado a lado. Não é calibração de
risco: é o mesmo problema resolvido de novo a cada projeto, exatamente o
padrão que motivou consolidar o backup.

**O que este plano não propõe:** login único (SSO), nem uniformizar o modelo
de autorização (papéis/permissões) de cada app. Essas duas coisas resolvem
domínios genuinamente diferentes entre os quatro — ver seção 3.

---

## 2. O que foi levantado (2026-08-20)

Conferido lendo o código de cada projeto, não por inferência.

### As rotinas que são o mesmo trabalho, feito quatro vezes

| Rotina | ConfortoTermico | MegaSena | ControleBancario | ControleRendaVariavel |
|---|---|---|---|---|
| Framework | Flask | Flask | Django | Flask |
| Sessão | própria (`before_request`) | Flask-Login | Django nativo | Flask-Login |
| CSRF | **próprio**, HMAC feito à mão | Flask-WTF | Django nativo | Flask-WTF |
| Cookie | HttpOnly, SameSite=Lax, Secure se HTTPS, 12h | idêntico + remember | idêntico, 24h | idêntico + Talisman |
| Hash de senha | scrypt (Werkzeug) | scrypt (Werkzeug) | PBKDF2 (Django) | PBKDF2-SHA256 (Werkzeug) |
| Piso de senha | 8 (`SENHA_TAMANHO_MINIMO`, achado corrigido — o levantamento inicial não encontrou) | **2 caracteres** | 15 (configurável) | 8 |
| Rate limit / lockout no login | Flask-Limiter 5/min | Flask-Limiter 10/min | `LoginLockout` por usuário+IP | Flask-Limiter |
| Criar 1º usuário | script standalone à parte | comando CLI (`flask criar-usuario`) | **não verificado** | comando CLI (`flask users create-admin`) |
| Tela de admin de usuários | própria (`/usuarios`) | própria (`/usuarios`) | própria, com catálogo de permissões | própria, parcial |
| Recuperação de senha por e-mail | ausente | ausente (reset é admin→usuário) | ausente | ausente |

A recuperação por e-mail está ausente nos quatro — não é uma divergência a
corrigir, é uma ausência uniforme, compatível com o porte destas aplicações.

### O que ficou sem verificar, e precisa entrar na Fase 0 de execução

- Piso de senha do ConfortoTermico (o agente de levantamento não encontrou
  validação explícita).
- Como o ControleBancario cria seu primeiro usuário administrador
  (`createsuperuser` nativo do Django? comando próprio?).
- Forma exata da tela de administração de usuários do ControleRendaVariavel.

### O que cada app faz de autorização — não entra neste plano

| Projeto | Modelo de autorização | Por que fica fora |
|---|---|---|
| ConfortoTermico | 6 perfis, acesso por área+endpoint | Gente de fato distinta opera (técnico, veterinário, gestor) |
| MegaSena | nenhum — binário autenticado/não | Não existe "dado de fulano" ali; é acervo único compartilhado |
| ControleBancario | ~30 permissões, escopo por titular de conta, log de auditoria | É livro-razão financeiro; "quem mexeu em qual conta" importa de verdade |
| ControleRendaVariavel | 2 papéis binários (admin/operador) | Sem dado a particionar por usuário |

Forçar um formato comum aqui tiraria rigor do ControleBancario ou adicionaria
peso morto ao MegaSena. Isso fica como está — resolve um problema real e
diferente em cada um, não porque tenha sido "desenhado assim" desde o início.

### Mensagens de status e confirmação — mesmo tipo de achado

Adicionado ao escopo em 2026-08-20, a pedido do mantenedor: como os quatro
avisam sucesso/erro e como confirmam uma ação destrutiva.

| | ConfortoTermico | MegaSena | ControleBancario | ControleRendaVariavel |
|---|---|---|---|---|
| Mecanismo | misto — só parte usa `flash()` | `flask.flash()` nativo | `django.contrib.messages` nativo | `flask.flash()` nativo |
| Categorias estilizadas | só "erro" | **uma cor só, para tudo** | 4 (sucesso/erro/aviso/info) | 2 (sucesso/erro) |
| Mensagem em HTMX parcial | não usa HTMX | `hx-swap-oob` copiado por template | 1 middleware genérico | não trata |
| Confirmação antes de excluir | `window.confirm()` cru | `hx-confirm` (nativo do HTMX) | modal próprio | **nenhuma** |

Os quatro já usam o mecanismo nativo do próprio framework (`flash()` no
Flask, `messages` no Django) — ninguém reinventou essa parte, e não há
motivo para trazer pacote de terceiros por cima. O que diverge é só a
renderização e a cobertura.

**Dois achados são defeito, não só inconsistência de estilo:**

- **MegaSena mostra erro com a cor de sucesso.** `get_flashed_messages()` é
  chamado sem `with_categories=true` (`app/__init__.py:248`,
  `templates/base.html:53`); a categoria `"error"` passada no código é
  descartada antes de chegar ao HTML.
- **ControleRendaVariavel não confirma nenhuma exclusão.** Não há
  `window.confirm`, `hx-confirm` nem modal — é formulário POST comum
  (`templates/table_brokers.html:27-30`).

**O ControleBancario é o modelo a seguir aqui**, mesmo sendo Django: 4
categorias estilizadas, mensagem funcionando certo em HTMX, modal de
confirmação. Os três Flask ganham o equivalente: um parcial de template +
CSS com as 4 categorias, um ajudante pequeno de `hx-swap-oob` generalizado
(o mesmo padrão que o Bancário já provou, só reaproveitável), e confirmação
padronizada em `hx-confirm` — atributo nativo do HTMX, já usado pelo
MegaSena, zero biblioteca nova.

Isso não pede um repositório à parte: vive no mesmo repositório da
biblioteca de autenticação (decisão A), como um módulo separado dentro dele.

---

## 3. Por que não é SSO

Um provedor de identidade central (Authelia, Keycloak, OIDC próprio)
resolveria "uma senha só", mas:

- **Vira o quinto serviço em produção**, e o único cujo colapso derruba o
  acesso aos quatro de uma vez. Hoje a queda de um Postgres não afeta os
  outros três; um IdP central inverteria isso.
- **Contradiz o isolamento construído na ressincronização do VPS**
  ([PLANO_RESSINCRONIZACAO_VPS.md](PLANO_RESSINCRONIZACAO_VPS.md)) — deploy
  keys por repositório, `.secrets/` por projeto, Postgres separado por app.
  Sessão compartilhada é o oposto: comprometer um app comprometeria a sessão
  dos quatro.
- **Não resolve os papéis.** SSO autentica ("é você"), não autoriza ("o que
  você pode fazer aqui"). O ControleBancario ainda precisaria mapear
  identidade → permissão granular; o MegaSena continuaria sem papel nenhum.
  O trabalho de portar os quatro para um cliente OIDC seria real, e o ganho
  seria só "uma senha".

---

## 4. O formato da solução: biblioteca, não serviço

A diferença central com o backup: lá, uma ferramenta externa roda contra os
quatro projetos de fora. Login não pode — precisa executar dentro do
processo de cada app, na própria sessão HTTP. Não há como ter um
"BackupRestore de login" rodando à parte.

O que dá certo é **uma implementação escrita uma vez, importada pelos três
apps Flask** (ConfortoTermico, MegaSena, ControleRendaVariavel):

- configuração de sessão/cookie
- CSRF via Flask-WTF
- esqueleto de rota de login com rate limit
- hash de senha + piso mínimo comuns
- comando CLI padrão de bootstrap do primeiro usuário
- blueprint reutilizável de administração de usuários, com um único ponto de
  extensão por app: a lista de papéis que ele anexa (vazia no MegaSena, os 6
  perfis no ConfortoTermico, os 2 papéis no Renda Variável)
- parcial de template + CSS de mensagens com as 4 categorias, ajudante de
  `hx-swap-oob` para HTMX, padrão de confirmação via `hx-confirm`

**O ControleBancario (Django) não entra na biblioteca** — framework
incompatível, sem como compartilhar código Python de verdade. Ele adota os
mesmos *valores* de política (piso de senha, por exemplo) com as ferramentas
nativas do Django. Mesmo comportamento, implementações separadas — o mesmo
padrão que já vale para o backup do ConfortoTermico e o BackupRestore: não
compartilham código, cumprem o mesmo contrato.

### Como o código chega aos três apps sem virar um monorepo

Os quatro projetos são repositórios GitHub privados independentes, cada um
com build Docker reproduzível a partir do próprio repositório — é assim que
o `deploy.sh` e a CI de cada um funcionam hoje. Uma biblioteca compartilhada
precisa entrar sem quebrar isso. Opção recomendada:

**Repositório próprio, pequeno, versionado com tag**, instalado via
`requirements.txt` apontando para o repositório Git (não um pacote no PyPI
público — não há razão para publicar isso fora). Cada app fixa uma versão
(`git+ssh://.../SharedAuth.git@v1.0.0`) e sobe deliberadamente quando quiser.
O acesso usa o **mesmo padrão de deploy key por repositório** já em uso desde
a ressincronização do VPS — nada novo a aprender, só mais uma chave
somente-leitura.

**Rejeitado: git submodule.** Historicamente frágil e opaco de operar; não
compensa para três consumidores.

**Rejeitado: copiar o código em cada repositório.** É voltar à estaca zero —
a mesma rotina reescrita três vezes, só que agora com um passo manual de
"lembrar de copiar de novo" a cada correção.

Isto é uma peça nova de infraestrutura — um quinto/sexto repositório para
manter, com sua própria disciplina de versão. É a decisão B da seção 6.

---

## 5. Ordem de execução, e por quê

O risco aqui é maior que o do backup: lá, um bug travava um dump — chato,
reversível. Aqui, um bug trava login de produção, ou pior, abre uma falha de
autenticação.

1. **MegaSena + ControleRendaVariavel primeiro.** Já usam Flask-Login; são os
   dois mais parecidos entre si hoje. Consolidar os dois valida o formato da
   biblioteca com o menor risco.
2. **ConfortoTermico por último.** É o mais divergente (mecanismo de sessão e
   CSRF inteiramente próprios) e o que tem mais a perder — 6 perfis
   funcionando em produção agora. Migra só depois de o formato já estar
   provado nos outros dois.
3. **ControleBancario nunca entra na biblioteca**, só acompanha a política de
   piso de senha.

Cada fase termina com login de verdade testado no navegador — cada papel
ainda vendo exatamente o que via antes — não só testes automatizados
passando.

---

## 6. Decisões — validadas em 2026-08-20

| # | Pergunta | Decisão |
|---|---|---|
| A | Repositório novo para a biblioteca compartilhada? | ✅ **Sim** — única forma limpa de compartilhar código real entre repositórios independentes (seção 4) |
| B | Ordem: MegaSena+Renda primeiro, ConfortoTermico por último, Bancário fora | ✅ **Sim**, nessa ordem (seção 5) |
| C | Piso de senha comum para os três Flask (hoje: 2 / 8 / 8) | ✅ **8** |
| D | ControleBancario acompanha o mesmo piso (hoje 15)? | ✅ **Sim, revertido em 2026-08-20** — o mantenedor decidiu piso uniforme de 8 nos quatro, permanente. 15 era desproporcional para o porte de uso (pessoal/&lt;5 usuários); a inconsistência entre projetos era o problema real, não o número em si |
| E | Mensagens/confirmação entram no mesmo repositório e cronograma da biblioteca de auth? | ✅ **Sim** — mesmo formato de achado, sem infraestrutura nova |
| F | Corrigir os dois defeitos já, ou só na migração de cada app? | ✅ **Só na migração** — evita duas rodadas de mudança na mesma tela |

**O plano está validado por inteiro.** A execução pode começar pela Fase 1
(repositório da biblioteca + extração de sessão/CSRF/rate-limit/hash/
mensagens a partir do que já existe no MegaSena, Renda e Bancário).

---

## 7. Fases

| Fase | O que faz | Mexe onde | Critério de validação |
|---|---|---|---|
| 0 | Levantamento | — | ✅ feito, seção 2 (com 3 pontos pendentes a confirmar antes da Fase 1) |
| 1 | Criar o repositório da biblioteca; extrair sessão+CSRF+rate-limit+hash+mensagens a partir do que já existe no MegaSena/Renda/Bancário | novo repositório | ✅ **feito 2026-08-20**, seção 9 |
| 2 | MegaSena consome a biblioteca (auth + mensagens); corrige a cor do erro (decisão F) | MegaSena | ✅ **feito, mesclado e implantado em produção 2026-08-20** (PR [#23](https://github.com/MSPA-Coder/mega-sena/pull/23)), seção 10 |
| 3 | ControleRendaVariavel consome a biblioteca; adiciona confirmação nas exclusões (decisão F) | ControleRendaVariavel | ✅ **feito, mesclado e implantado em produção 2026-08-20** (PR [#17](https://github.com/MSPA-Coder/ControleRendaVariavel/pull/17)), seção 11 |
| 4 | ConfortoTermico migra para a biblioteca | ConfortoTermico | ✅ **feito, mesclado e implantado em produção 2026-08-20** (PR [#16](https://github.com/MSPA-Coder/Sistema-de-Controle-de-Indice-de-Conforto-Termico/pull/16)), seção 12 |
| 5 | ControleBancario ajusta piso de senha para acompanhar a política (se aplicável) | ControleBancario | ✅ **feito, mesclado e implantado em produção 2026-08-20** (fora de ordem, antes da biblioteca existir — PR [sistema-financeiro#22](https://github.com/MSPA-Coder/sistema-financeiro/pull/22)), seção 8 |
| 6 | Documentação: README/AGENTS.md dos quatro descrevem o padrão comum e onde cada um diverge de propósito | documentação | ✅ **feito 2026-08-20**, seção 13 — falta commit/PR |

Nenhuma fase depende da anterior estar em produção — cada uma é um PR, CI,
merge e deploy independentes, como já é o fluxo estabelecido.

## 8. Piso de senha e conta Admin — executado em 2026-08-20

Executado fora da ordem das fases (não dependia da biblioteca compartilhada
ainda não criada): piso de senha em 8 nos quatro, e uma conta `Admin`
provisória em cada um, em produção, a pedido do mantenedor — ele mesmo troca
a senha depois.

> A senha inicial dessa conta **não está escrita neste repositório**, de
> propósito: era fraca e ficou em texto puro aqui por um tempo. Isto aqui é
> um repositório Git, e o que entra no histórico não sai. Se precisar
> registrar credencial de novo, use um gerenciador de senhas, nunca um plano.

### Piso de senha

| Projeto | Antes | Depois | PR |
|---|---|---|---|
| ConfortoTermico | 8 | 8 (sem mudança — achado corrigido) | — |
| ControleRendaVariavel | 8 | 8 (sem mudança) | — |
| MegaSena | 2 | **8** | [mega-sena#22](https://github.com/MSPA-Coder/mega-sena/pull/22) |
| ControleBancario | 15 | **8** | [sistema-financeiro#22](https://github.com/MSPA-Coder/sistema-financeiro/pull/22) |

O ControleBancario tinha **dois** pontos com o mesmo piso duplicado —
`accounts/password_validators.py` (o validador que de fato roda) e
`core/services.py` (a tela Configurações > Parâmetros) — os dois precisaram
mudar juntos, senão a tela aceitaria um valor que o validador recusaria. Os
dois PRs passaram CI, foram mesclados e implantados no VPS (`~/deploy.sh
megasena` e `~/deploy.sh bancario`), confirmados `healthy` + HTTP 200.

### Conta Admin

| Projeto | Situação encontrada | Ação | Mecanismo usado |
|---|---|---|---|
| ConfortoTermico | não existia | criada, perfil `administrador` | `scripts/criar_usuario_admin.py` dentro do contêiner `ict` |
| MegaSena | não existia | criada | `flask criar-usuario` dentro do contêiner `app` |
| ControleRendaVariavel | não existia | criada, papel `admin` | `flask users create-admin` dentro do contêiner `web` |
| ControleBancario | **já existia** (`user_type=administrator`) | senha alterada, conta ativada | `manage.py shell` + `set_password()` (ORM, hash correto) |

Feito em produção e, depois (Docker Desktop voltou a responder na mesma
sessão), também localmente — os quatro stacks subidos com `--build` (pegando
o piso 8 já no código) e a mesma conta criada/alterada em cada um, pelo
mesmo mecanismo. Nos dois lugares, nenhuma senha foi gravada por SQL direto
— sempre pela CLI, script ou ORM de cada projeto, preservando hash correto e
validação. Localmente, o ControleBancario também já tinha um "Admin"
existente (mesmos nomes de usuário que a produção — `Mariano`, `Claudia`,
`Esther`, `Admin` —, indício de que o banco local é espelho de um dump de
produção antigo), então também foi alteração, não criação.

**Um susto sem consequência, registrado para não se repetir:** ao investigar
o ConfortoTermico, uma consulta a `SELECT ... FROM usuarios` devolveu "tabela
não existe" — pareceu, por um instante, perda de dado da produção. Era erro
de consulta: as tabelas do ConfortoTermico vivem nos schemas `historico` e
`dados_entrada`, não em `public`, e `\dt` sem qualificação só mostra o
`public`. Confirmado contra o dump de backup mais antigo do dia (04:03 UTC,
antes de qualquer ação desta sessão) e depois against o próprio banco com a
consulta qualificada corretamente: os seis usuários e todas as tabelas
sempre estiveram lá.

## 9. Fase 1 — concluída em 2026-08-20

**Repositório criado:** [github.com/MSPA-Coder/SharedAuth](https://github.com/MSPA-Coder/SharedAuth)
(privado), tag `v0.1.0`. Local em
`C:\Users\MSPA\Dropbox\Programacao\VSCodeProjects\SharedAuth`, mesmo nível
dos outros cinco projetos.

### O que entrou

| Módulo | Extraído de | O que resolve |
|---|---|---|
| `sharedauth.passwords` | piso comum, novo (não existia um "certo" a copiar) | hash Werkzeug + piso 8, um só lugar |
| `sharedauth.session` | MegaSena + ControleRendaVariavel (quase idênticos) | cookie HttpOnly/SameSite=Lax/Secure-se-HTTPS |
| `sharedauth.csrf` | MegaSena + ControleRendaVariavel (Flask-WTF) | inicialização única — o que falta ao ConfortoTermico hoje, que tem CSRF próprio em HMAC |
| `sharedauth.ratelimit` | os três, com números diferentes | Flask-Limiter, padrão 10/min |
| `sharedauth.access` | MegaSena (`HX-Redirect`) + ControleRendaVariavel (401 JSON) | padrão-nega, aceita as duas formas de resposta por parâmetro |
| `sharedauth.messages` | ControleBancario como modelo (4 categorias, HTMX tratado) | template normal + variante OOB para HTMX, CSS com as 4 categorias |

**Deliberadamente fora desta fase:** CLI de bootstrap de usuário e blueprint
de administração. As duas dependem do modelo de usuário de cada app, que
difere o bastante (campos diferentes, papéis diferentes) para que desenhar
a abstração sem um consumidor real na frente fosse abstração prematura —
entram junto da Fase 2, com o MegaSena como primeiro caso real.

### Verificação

26 testes, cobrindo os cinco módulos com caminho feliz e recusa (senha
curta, sessão não autenticada, CSRF ausente, limite estourado, categoria de
mensagem desconhecida caindo em "info"). Passam local e na CI do GitHub, em
ambiente limpo — 17s.

### Versionamento

Tag `v0.1.0`, GitHub Release publicada. `AGENTS.md` do próprio pacote
registra a disciplina: tag nunca reescrita, apps atualizam a versão fixada
um de cada vez com deploy e verificação real antes do próximo, e mudança
que quebra assinatura pública é sempre versão maior.

### Revisão de código (2026-08-20) — 9 achados, todos corrigidos

Revisão de 8 ângulos (correção, comportamento removido, rastreamento entre
arquivos, reuso, simplificação, eficiência, altitude — convenções não se
aplicou, sem `CLAUDE.md` no ambiente) sobre o commit inicial, antes de
qualquer app consumir a biblioteca. O achado mais sério foi **reproduzido de
fato**, não só lido no código: um agente escreveu um script provando que
criar um segundo app Flask no mesmo processo apagava silenciosamente o
contador de limite de tentativas do primeiro.

| # | Achado | Veredito | Correção |
|---|---|---|---|
| 1 | `Limiter` era singleton de módulo — `init_app` de um segundo app reconstruía o storage compartilhado, zerando os contadores do primeiro | CONFIRMADO (reproduzido) | `iniciar_limiter` cria instância própria por chamada |
| 2 | `CSRFProtect` era singleton de módulo — isenção (`.exempt()`) de um app vazava para outro no mesmo processo | CONFIRMADO | `iniciar_csrf` cria instância própria por chamada |
| 3 | `conferir_hash(None, senha)` levantava `AttributeError` em vez de recusar | CONFIRMADO | guarda de hash nulo/vazio, devolve `False` |
| 4 | JSON de 401 usava `"erro"`; o ControleRendaVariavel original usa `"error"` | CONFIRMADO | padrão corrigido para `"error"`, com `chave_erro_api` configurável |
| 5 | `registrar_mensagens` duas vezes no mesmo app derrubava com `AssertionError` | CONFIRMADO | vira `Blueprint`, com guarda de dupla-chamada (no-op seguro) |
| 6 | `requer_login` duas vezes: a primeira chamada vence em silêncio para parte das rotas | PLAUSÍVEL | levanta `RuntimeError` — perigoso demais para passar em silêncio num controle de acesso |
| 7 | `next=request.full_path` sempre carregava um `?` sobrando (quirk do Werkzeug) | PLAUSÍVEL | só inclui `?` quando há query string de verdade |
| 8 | CSS servido por rota própria + `ChoiceLoader` manual, reimplementando o que um `Blueprint` já dá de graça (cache condicional) | PLAUSÍVEL | migrado para `Blueprint(template_folder=..., static_folder=...)` |
| 9 | `gerar_hash` levanta exceção própria não compatível com `click.ClickException`, sem aviso na documentação | PLAUSÍVEL | docstring explica a exceção e a necessidade de relançar como `ClickException` no CLI da Fase 2 |

Um décimo candidato — a suspeita de que `usar_hx_redirect=False` reintroduzia
o próprio bug que o módulo existe para evitar — **caiu na verificação**: é
comportamento documentado e testado, fiel ao ControleRendaVariavel original,
não regressão.

36 testes agora (eram 26), 10 novos cobrindo especificamente os bugs
corrigidos — incluindo dois testes de regressão que reproduzem o cenário
multi-app-no-mesmo-processo que expôs os singletons. Tag `v0.1.1` publicada;
`v0.1.0` não foi reescrita, só ficou obsoleta (nenhum app chegou a consumi-la).

### O que ainda falta para os apps de fato consumirem

O pacote existe e funciona isolado, mas **nenhum dos quatro apps o importa
ainda** — isso é a Fase 2. Falta também decidir o mecanismo de acesso Git
(deploy key dedicada, mencionado no plano original — seção 4 — ainda não
criada) para que o `requirements.txt` de cada app consiga instalar de um
repositório privado tanto localmente quanto na imagem Docker de CI/VPS.

## 10. Fase 2 — MegaSena consome a biblioteca (2026-08-20)

**Código migrado**: `extensions.py` não guarda mais `csrf`/`limiter` como
singletons de módulo (só `db`, `migrate`, `login_manager`). `create_app()`
usa `sharedauth.session.configurar_sessao`, `sharedauth.csrf.iniciar_csrf`,
`sharedauth.ratelimit.iniciar_limiter` e `sharedauth.access.requer_login` no
lugar do código próprio equivalente. `models.py` usa
`sharedauth.passwords.gerar_hash`/`conferir_hash` (ganho de brinde: hash nulo
não derruba mais o login com 500). `accounts/service.py` e `cli.py` usam
`sharedauth.passwords.validar_tamanho`/`MIN_PASSWORD_LENGTH` no lugar da
constante própria. Corrigido o defeito documentado na seção 2: erro aparecia
com a cor de sucesso (`get_flashed_messages` sem `with_categories=True`).

**Bug real encontrado e corrigido, reproduzido antes da correção**: como
`iniciar_limiter(app)` cria uma instância nova por `create_app()` (não um
singleton importável no import de `auth.py`, como antes), o limite de
tentativas de login teve que ser aplicado depois do registro da rota:
`limiter.limit(...)(app.view_functions["web.login"])`. O retorno dessa
chamada é uma função *nova*, embrulhada — a primeira versão descartou esse
retorno em vez de reatribuir `app.view_functions["web.login"]`, deixando o
limite decorado e nunca aplicado. Reproduzido de fato: 11 requisições
seguidas ao `/login` devolviam 200. Corrigido reatribuindo o retorno; teste
de regressão em `tests/test_rate_limit.py` (confirmado que falha sem a
correção, revertendo-a manualmente antes de restaurar).

**Escopo deliberadamente deixado de fora**: os 5 templates que reimplementam
o bloco `hx-swap-oob` do banner global de mensagens (`bets/_generation_result
.html`, `bets/_save_response.html`, `settings/_feedback.html`,
`contests/_import_response.html`, `users/_feedback.html`) não foram tocados.
Investigação mostrou que trocar isso por `sharedauth.messages` exigiria
também alterar a lógica Python de várias rotas — a geração de apostas em
particular tem uma ramificação HTMX/não-HTMX deliberada e comentada
(`app/web/bets.py`, comentário em torno da linha 430). Não é o defeito
documentado na seção 2 (que é só sobre a cor do erro no banner global); ficou
como pendência explícita, não esquecimento — candidato natural a entrar
junto da Fase 3, quando o ControleRendaVariavel também mexer no mesmo tipo de
bloco (a confirmação de exclusão que falta lá).

**Credencial de build — decisão nova, diferente do padrão original do
plano**: a máquina do mantenedor não tem nenhuma chave SSH para GitHub (usa
`gh` autenticado por token HTTPS) — o padrão de deploy key SSH da
[[project-ressincronizacao-vps]] não se aplica sem trabalho extra. Optou-se
por um **token de acesso restrito (fine-grained PAT)**, somente-leitura,
escopado só ao repositório SharedAuth, sobre HTTPS. `requirements.txt` usa
`git+https://...`; `Dockerfile` autentica via `git config
--global url.insteadOf` dentro de um `RUN --mount=type=secret,id=github_token`
(nunca vira camada da imagem, removido do `.gitconfig` na mesma instrução).
`compose.yaml` declara o secret `github_token` apontando para
`.secrets/github_token.txt` (fora do Git, mesmo padrão de
`postgres_password.txt`/`secret_key.txt`); `.github/workflows/ci.yml` escreve
esse arquivo a partir do secret do GitHub Actions `SHAREDAUTH_READ_TOKEN`.
**Verificado de verdade**: build local (`docker compose --profile quality
build --no-cache quality`) baixou e instalou `sharedauth@v0.1.1` via HTTPS+
token; suíte completa rodou dentro do container (46 testes); stack completa
(`app`+`postgres`) testada no navegador — login com senha errada (flash
vermelho), logout (flash verde), CSRF, rate-limit (bloqueio real confirmado),
criar/desativar/reativar usuário, guarda de auto-desativação.

**Bug não relacionado, achado testando no navegador — corrigido em
2026-08-20** ([mega-sena#25](https://github.com/MSPA-Coder/mega-sena/pull/25),
na sessão da Fase 6, aproveitando que o MegaSena já estava sendo tocado):
os gráficos de barra do dashboard ficavam vazios depois de trocar o
período de análise via HTMX (funcionavam no carregamento normal). A causa
era a CSP `style-src 'self'` do projeto bloqueando a mutação de estilo
inline que `base.js` fazia (`element.style.setProperty`) especificamente
quando acontecia dentro do listener de `htmx:afterSwap`. Sem relação com
SharedAuth. Corrigido trocando `setProperty` por uma escala estática de
101 classes `.pct-0`..`.pct-100` no CSS (`dashboard-charts.css`/
`components.css`) — o servidor calcula a porcentagem e escolhe a classe,
nada muda estilo em runtime. Validado no navegador: 60 barras do gráfico
de frequência + 22 do histograma de somas, todas com altura correta após
a troca via HTMX. **Implantado no VPS em 2026-08-20** (`~/deploy.sh megasena`) — healthy,
`https://megasena-mspa.duckdns.org/login` HTTP 200.

**PR mesclado**: [mega-sena#23](https://github.com/MSPA-Coder/mega-sena/pull/23), CI verde
(secret `SHAREDAUTH_READ_TOKEN` já existia no repositório, confirmado com
`gh secret list`/`gh pr checks`). **Falta só implantar**: copiar
`.secrets/github_token.txt` para `/home/ubuntu/apps/megasena/.secrets/` no
VPS (mesmo token, código do repositório em `/home/ubuntu/apps/<projeto>` —
ver PLANO_RESSINCRONIZACAO_VPS.md) e rodar `~/deploy.sh megasena`. O
classificador de segurança do modo automático bloqueia consistentemente
ações de escrita/deploy no VPS (até um `scp` de secret foi recusado) — fica
para o mantenedor executar manualmente:

```powershell
scp -i "C:\Users\MSPA\Downloads\OracleKeys\ssh-key-2026-08-17.key" MegaSena\.secrets\github_token.txt ubuntu@163.176.214.214:~/apps/megasena/.secrets/github_token.txt
ssh -i "C:\Users\MSPA\Downloads\OracleKeys\ssh-key-2026-08-17.key" ubuntu@163.176.214.214 "~/deploy.sh megasena"
```

## 11. Fase 3 — ControleRendaVariavel consome a biblioteca (2026-08-20)

**Código migrado e testado, PR ainda não aberto.** Mesmo padrão do MegaSena
(`sharedauth.session/csrf/ratelimit/access/passwords`), com diferenças reais
entre os dois apps que valeram decisão própria:

- **Mais pontos religados que no MegaSena**: além da rota de login,
  `csrf`/`limiter` também eram importados em `routes/partials.py` (rate-limit
  120/min em dois fragmentos HTMX do coletor RTD) e `routes/collector_agent.py`
  (`csrf.exempt` em dois endpoints públicos de API). Todos os cinco pontos
  religados em `create_app()`, depois de `register_blueprints`, com o mesmo
  cuidado do MegaSena: reatribuir `app.view_functions[endpoint]` ao retorno do
  `limiter.limit(...)`, não descartar — o bug do MegaSena quase se repetiu
  aqui (peguei e corrigi no mesmo instante, antes de rodar qualquer teste).
- **`usar_hx_redirect=True` é melhoria real, não só paridade**: o gate
  original devolvia um `redirect()` puro mesmo para requisições HTMX: numa
  sessão expirada, o HTMX seguiria o redirect e trocaria um fragmento pela
  página de login inteira. O app usa HTMX extensivamente (`README.md`: "não
  existe API JSON, o servidor responde HTML"); nenhum teste travava esse
  comportamento. Corrigido como parte da migração, não é regressão.
- **Mensagens não precisaram de nenhuma mudança**: já usa
  `get_flashed_messages(with_categories=true)` num único ponto
  (`base.html`), sem duplicação de blocos HTMX como o MegaSena tinha — o
  próprio defeito que motivou tocar nas mensagens do MegaSena não existe
  aqui. `sharedauth.messages` não foi consumido (nada para corrigir; forçar
  o blueprint compartilhado sem um defeito concreto seria reorganizar sem
  necessidade).
- **Sem tela de admin de usuários** — só CLI (`flask users create-admin` /
  `users deactivate`). Validação da Fase 3 não tem o equivalente a
  "criar/desativar usuário pelo navegador" do MegaSena; cobre login,
  rate-limit, categorias (já corretas) e a confirmação de exclusão.
- **`pyproject.toml`/Hatchling, não `requirements.txt`**: precisou de
  `[tool.hatch.metadata] allow-direct-references = true` — Hatchling recusa
  por padrão uma dependência `nome @ git+https://...` sem esse opt-in
  explícito. Sem equivalente no MegaSena (setuptools não tem essa trava).
- **Docker/CI do PAT construído do zero**: nada parecido existia aqui (só o
  `local_ca` opcional). Mesmo mecanismo do MegaSena (BuildKit secret mount +
  `git config url.insteadOf`) replicado nos dois estágios do `Dockerfile`
  (`runtime`, usado por `web`/`migrate`; `quality`) e nos dois jobs do CI
  (`quality`, `runtime-contracts` — o segundo builda a imagem `web` para
  inspecionar contratos de runtime, também precisa do secret).

**As 11 rotas de exclusão sem confirmação (achado do plano, seção 2) foram
corrigidas** — `hx-confirm` nativo do HTMX, zero biblioteca nova, mesmo
padrão citado como precedente do MegaSena. Duas formas, conforme o HTML já
existente:

- **3 já eram `hx-post`** (delete_portfolio, remove_portfolio_ticker,
  delete_quote_history_by_date): só ganharam `hx-confirm`.
- **8 eram formulário POST puro** (delete_broker, delete_ticker, as duas
  `delete_position`, delete_expiration, delete_contract, delete_dividend, e
  `delete_transaction` em 3 lugares — 2 em `transactions_results.html` + 1
  em `transaction_form.html`): ganharam `hx-boost="true"` junto do
  `hx-confirm`, para o HTMX interceptar o submit nativo sem precisar
  redesenhar o alvo/troca de cada um — `hx-boost` preserva o comportamento
  de navegação (segue redirect, sem exigir `hx-target` novo).

**Verificação real, não só testes automatizados**: 119 testes passam dentro
do container `quality` (o mesmo ambiente do CI) — localmente, fora do
Docker, um teste de RTD falha por incompatibilidade do mock de subprocess
com o Python 3.14 do Windows, não relacionado a esta mudança, confirmado
por não falhar dentro do container Linux. Testado no navegador com dados
reais do mantenedor: login com senha errada (flash vermelho), login válido
(flash verde), CLI recusando senha curta com mensagem limpa (sem
traceback), e o fluxo de confirmação de exclusão nos dois sentidos — criei
uma corretora de teste, cliquei em Excluir com `window.confirm` forçado a
`false` (nenhuma requisição disparada, corretora continuou lá) e depois
forçado a `true` (excluída de verdade, as 5 corretoras reais do mantenedor
intactas).

**PR mesclado**: [ControleRendaVariavel#17](https://github.com/MSPA-Coder/ControleRendaVariavel/pull/17),
CI verde. O secret `SHAREDAUTH_READ_TOKEN` precisou de duas correções no
valor colado (token inválido rejeitado pelo GitHub: "Invalid username or
token") antes de funcionar — mesma causa-raiz possível em qualquer repo
novo que ganhar este secret, vale conferir sem espaço/quebra de linha extra
ao colar. **Implantado em produção em 2026-08-20**: código em
`/home/ubuntu/apps/controle-renda-variavel` (nome confirmado), `.secrets/github_token`
copiado, `~/deploy.sh renda` executado — `controle-renda-variavel-web-1`
healthy, `https://renda-mspa.duckdns.org/login` responde HTTP 200.

---

## 12. Fase 4 — ConfortoTermico consome a biblioteca (2026-08-20)

**A mais arriscada das quatro, feita e testada, commit ainda não feito.**
Diferente dos outros dois apps Flask: sessão e CSRF eram inteiramente
próprios (não Flask-Login/Flask-WTF), e há 6 perfis com mapeamento de área
que precisam ficar 100% intactos (autorização — fora do escopo do
SharedAuth). O mantenedor pediu explicitamente que "os grandes mecanismos"
fossem compartilhados sempre que possível, incluindo o CSRF próprio deste
projeto — não como exceção.

**CSRF: trocado por `sharedauth.csrf` (Flask-WTF) sem tocar templates nem
JS.** Investigação prévia (não achado por tentativa e erro): Flask-WTF
aceita `WTF_CSRF_FIELD_NAME` (nome do campo do formulário) e
`WTF_CSRF_HEADERS` já inclui `X-CSRF-Token` por padrão — bastou configurar
`WTF_CSRF_FIELD_NAME = "_csrf_token"` (o nome que os 4 templates e o
`api.js` já usavam) e `WTF_CSRF_TIME_LIMIT = None` (o token próprio não
tinha prazo, vivia com a sessão de 12h; o padrão do Flask-WTF é 1h, o que
introduziria falha de CSRF sem o login expirar) antes de `iniciar_csrf(app)`.
Zero mudança em `login.html`, `usuario_form.html`, `usuarios.html`,
`index.html`, `api.js`.

**Autenticação e autorização eram um antes hook só — separados em dois.**
`_exigir_login_e_area` fazia as duas coisas: "está logado" (agora
`sharedauth.access.requer_login`) e "tem a área" (continua em
`auth.registrar_controle_de_area`, específico deste app). Ordem dos hooks
importa: CSRF → carregar `g.usuario` da sessão (`registrar_carregamento_
usuario`) → gate de login (`requer_login`) → controle de área
(`registrar_controle_de_area`). `chave_erro_api="erro"` configurado
explicitamente — este app usa `"erro"` (português) em todo JSON de erro,
diferente do `"error"` do ControleRendaVariavel; `sharedauth.access` aceita
os dois por parâmetro exatamente para isso.

**Dois bugs reais de rate-limit encontrados e corrigidos — mesma causa-raiz
já vista no MegaSena, desta vez em dobro:**
1. O limite de 5/min do login **nunca funcionou**: usava um `Limiter`
   órfão (`auth.obter_limiter()`), criado sem `app=` e sem `init_app()` —
   seu hook de enforcement nunca era registrado. Na prática só o default
   global (20/min) protegia o login. Corrigido reaproveitando o limiter de
   verdade da app (`app.extensions["conforto_rate_limiter"]`), com o
   `LIMITE_LOGIN_PADRAO` (10/min) já padronizado nos outros dois apps.
2. **Achado de novo, mesmo padrão, em código que eu não escrevi nesta
   migração**: o limite dedicado de "60 per minute" nas 3 rotas de polling
   do dashboard (a cada 3s) também descartava o retorno de
   `limiter.limit(...)` em vez de reatribuir a `app.view_functions`. Como
   3s = 20 requisições/minuto, exatamente no limite do default global
   (20/min), isso provavelmente já gerava 429 esporádico em produção.
   Corrigido junto, mesmo padrão de fix.

Confirmado empiricamente (não só lido): `RouteLimit.__call__` do
Flask-Limiter devolve uma função *embrulhada*, e o enforcement do limite
decorado por rota roda **dentro** desse embrulho quando a view é chamada —
não num `before_request` genérico por nome qualificado, como cheguei a
suspeitar ao ler o código-fonte da biblioteca antes de testar. Descartar o
retorno deixa o limite decorado e nunca aplicado. Testes de regressão para
os dois casos.

**`next=` no lugar de `proxima=`**: parâmetro da querystring renomeado
(`sharedauth.access.requer_login` sempre gera `next=`) — mesmo nome que
MegaSena e ControleRendaVariavel já usavam. Único ponto tocado:
`login.html` (nome do campo oculto) e `auth.py` (leitura do parâmetro);
`_destino_pos_login` (validação anti-open-redirect) não mudou.

**Mensagem de senha curta alinhada aos outros dois apps**: "A senha precisa
ter pelo menos N caracteres." → "A senha deve ter pelo menos N
caracteres." (mesma frase de `sharedauth.passwords`), em `auth.py` (rotas
de criar/editar usuário) e no script `criar_usuario_admin.py`.

**Achado, descartado ao investigar**: o comentário "o factory deste
projeto conecta ao banco" aparecia em `test_csrf.py`, `test_auth_
required.py` e `test_security_headers.py` como justificativa para a suíte
inteira ser caixa-branca (`inspect.getsource`, sem `test_client()`).
Verificado empiricamente: `db.iniciar_banco()` e `dados_entrada_db.
iniciar_banco()` são no-ops (schema é exclusivo do Alembic) — `criar_app_
ict()` não toca o banco na criação. Só rotas que de fato consultam dados
(ex.: `/health`) tocam. O comentário provavelmente ficou desatualizado
depois de uma mudança anterior no projeto. Isso abriu caminho para uma
suíte de integração de verdade (`tests/conftest.py`, novo — não existia
nenhum fixture de app antes desta migração) em vez de só inspeção de
código-fonte; `test_csrf.py`/`test_auth_required.py`/`test_authorization.py`
reescritos para `test_client()` real onde fazia sentido, mantendo os
testes puramente unitários (chave de sessão, `_destino_pos_login`, mapa de
perfis) como estavam.

**Verificação real**: 57 testes passam dentro do container `quality` (== ao
count local, confirma que não há teste específico de plataforma
divergindo). Build Docker validado com o mesmo mecanismo de PAT dos outros
dois apps (2 estágios no Dockerfile, âncora `x-app-build` + serviço
`quality` no compose, 2 jobs de CI). Testado no navegador com dados reais
do mantenedor (login com senha errada, login válido, logout, criar/excluir
usuário com CSRF de verdade, senha curta com a mensagem unificada, área
"usuarios" acessível só para administrador).

**PR mesclado**: [Sistema-de-Controle-de-Indice-de-Conforto-Termico#16](https://github.com/MSPA-Coder/Sistema-de-Controle-de-Indice-de-Conforto-Termico/pull/16)
(nome real do repositório GitHub, diferente do apelido "ConfortoTermico").
Secret `SHAREDAUTH_READ_TOKEN` criado pelo mantenedor em 2026-08-20, CI
verde (Qualidade e Runtime contracts) e merge feito no mesmo dia.
**Implantado em produção em 2026-08-20**: `/home/ubuntu/apps/conforto-termico/.secrets`
estava com dono `root:root` (diferente dos outros três projetos, `ubuntu:ubuntu`
— corrigido via `chown` antes de copiar o token), `.secrets/github_token.txt`
copiado, `~/deploy.sh conforto` executado — `conforto-termico-coletor-1` e
`conforto-termico-ict-1` healthy, `https://conforto-mspa.duckdns.org/login`
responde HTTP 200.

---

## 13. Fase 6 — Documentação (2026-08-20)

Uma frase curta em `README.md` e `AGENTS.md` de cada app Flask, apontando o
mecanismo compartilhado e o que continua próprio do projeto — mesmo texto-base
nos três, adaptado ao que cada um já documentava:

- **MegaSena**: `README.md` já tinha a frase sobre SharedAuth desde a Fase 2
  (PR #23). Só faltava o `AGENTS.md`, que ganhou a mesma frase na seção
  "Interface, segurança e exposição".
- **ControleRendaVariavel**: nenhum dos dois documentos mencionava
  SharedAuth. `README.md` (seção "Operacao") e `AGENTS.md` (seção
  "Segurança, dados e Docker") ganharam a frase, citando os dois papéis
  (`operador`/`admin`) como o que continua próprio.
- **ConfortoTermico**: idem, nenhum dos dois mencionava. `README.md` (seção
  "Perfis de acesso") e `AGENTS.md` (seção "Arquitetura e invariantes
  essenciais") ganharam a frase, citando `AREAS_POR_PERFIL` como o que
  continua próprio.
- **ControleBancario** (Django, não compartilha código): `AGENTS.md` ganhou
  uma frase na seção de segurança citando que o piso de senha (8, os dois
  pontos duplicados em `password_validators.py`/`core/services.py`) segue a
  mesma política dos três apps Flask, sem compartilhar mecanismo.

**PRs mesclados em 2026-08-20**:
- [mega-sena#24](https://github.com/MSPA-Coder/mega-sena/pull/24)
- [Sistema-de-Controle-de-Indice-de-Conforto-Termico#17](https://github.com/MSPA-Coder/Sistema-de-Controle-de-Indice-de-Conforto-Termico/pull/17)
- [ControleRendaVariavel#18](https://github.com/MSPA-Coder/ControleRendaVariavel/pull/18)
- [sistema-financeiro#23](https://github.com/MSPA-Coder/sistema-financeiro/pull/23)

Com isso, as seis fases do plano têm código, documentação e PRs completos
e mesclados. Documentação-only, sem efeito em runtime — não exige deploy.

---

## Registro de sessões

- **2026-08-20** — Levantamento e plano. Correção de rota registrada: a
  primeira leitura tratou as diferenças entre projetos como decisão de
  arquitetura deliberada; o mantenedor corrigiu — os sistemas cresceram por
  acréscimo, sem esse planejamento. O plano foi reescrito para separar o que
  é *acidente* (sessão, CSRF, hash, rate-limit, bootstrap, tela de admin —
  candidatos a unificar) do que é *necessidade real e diferente por domínio*
  (o modelo de papéis de cada app — fica como está). Escopo ampliado, a
  pedido do mantenedor, para mensagens de status e confirmação de ações
  destrutivas — mesmo formato de achado (rotina duplicada por acidente, os
  quatro já usam o mecanismo nativo do framework, ninguém precisa de pacote
  novo). Dois defeitos concretos encontrados no caminho: MegaSena mostra erro
  com a cor de sucesso (`with_categories` faltando); ControleRendaVariavel
  não confirma nenhuma exclusão. **As seis decisões (A–F) validadas na mesma
  sessão.** Piso de senha e conta Admin **executados fora de ordem** (seção
  8), a pedido do mantenedor: piso 8 uniforme nos quatro — decisão D
  revertida em relação à recomendação original, escolha explícita e
  permanente do mantenedor, não provisória. Conta `Admin` criada
  ou alterada em produção nos quatro (senha fora deste repositório). Susto sem consequência no meio do
  caminho: consulta com schema errado no ConfortoTermico pareceu apontar
  tabelas ausentes; confirmado contra o backup do dia que nunca houve perda.
  **Fase 1 executada e verificada** (seção 9): repositório
  [SharedAuth](https://github.com/MSPA-Coder/SharedAuth) criado, tag
  `v0.1.0`, 26 testes passando local e na CI. CLI de bootstrap e blueprint
  de administração deliberadamente deixados para a Fase 2, junto do
  primeiro consumidor real. Falta ainda a deploy key para instalação do
  repositório privado a partir dos apps. Próximo passo: Fase 2 — MegaSena
  consome a biblioteca.
