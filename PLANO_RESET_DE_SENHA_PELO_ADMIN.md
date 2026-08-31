# Plano — recuperação de senha pelo administrador nos 4 projetos

Iniciado em 2026-08-30. Sucessor direto do plano de unificação de
autenticação (consolidado em `main`, ver histórico do repositório): aquele
uniformizou as *peças* do login — sessão, CSRF, hash, limite de tentativas —
e este trata do fluxo que ficou faltando nos quatro, **o que acontece quando
alguém perde a senha**.

Documento irmão pela forma: `PLANO_EQUALIZAR_BASE_COMPARTILHADA.md` (mesmo
padrão de "contrato-alvo único, adoção um app por vez").

---

## 1. O problema, em uma frase

Nenhum dos quatro projetos tem recuperação de senha, e **três dos quatro não
têm nem sequer uma tela onde a pessoa troque a própria senha**. Hoje, quem
esquece a senha depende de um administrador digitar uma nova para ela — que
o administrador passa a conhecer, e que a pessoa nunca é obrigada a trocar.
A senha "temporária" vira definitiva, e um administrador conhece a senha
corrente de todo mundo.

O ControleBancario é a exceção: já resolve isso por inteiro, e por isso é a
referência deste plano em vez de mais um app a corrigir.

---

## 2. A decisão, e o que ficou de fora

**Aprovado: reset iniciado pelo administrador, com troca obrigatória no
próximo acesso.** O administrador redefine a senha, o sistema entrega uma
senha temporária, e a pessoa é obrigada a trocá-la antes de fazer qualquer
outra coisa. A senha temporária circula fora do sistema (verbalmente, no
mesmo canal em que essas quatro pessoas já se falam).

**Fora de escopo nesta rodada: "esqueci minha senha" por e-mail.** Não é
recusa da ideia — é ordem de execução. O custo real dela não é o envio:

- **Nenhum dos três apps Flask tem coluna de e-mail no usuário.** MegaSena,
  ControleRendaVariavel e ConfortoTermico guardam usuário, hash, ativo e
  papel — nada mais. São três migrations e o preenchimento manual dos
  endereços. O ControleBancario herda `email` do `AbstractUser` do Django,
  provavelmente vazio.
- **Exige tabela de tokens** (token de uso único, guardado só como hash, com
  validade), rota pública nova e limite de tentativas próprio — superfície
  de ataque nova numa parte do sistema que hoje não tem nenhuma rota pública
  além do login.
- **Exige um relay SMTP** e uma `URL_BASE_PUBLICA` por app (montar o link a
  partir de `request.host_url` abre injeção por cabeçalho `Host`).

E, decisivo: mesmo com o e-mail pronto, o reset pelo administrador continua
sendo necessário — para quem não tiver e-mail cadastrado, e para quando o
e-mail não chegar. Ou seja, este plano não é o degrau anterior ao e-mail; é
a base sobre a qual o e-mail seria uma alternativa. **Registrado como
candidato a rodada futura**, com o levantamento já feito (seção 9).

Sobre a pergunta que originou a decisão — *precisaria de um servidor de
e-mail?*: não. Precisaria de um **relay SMTP autenticado** (senha de app do
Gmail, ou um provedor transacional), nunca de um MTA próprio no VPS. A porta
25 de saída vem bloqueada por padrão no Oracle Cloud, e um subdomínio DuckDNS
não permite alinhar SPF/DKIM/DMARC — o e-mail iria para spam e o VPS ganharia
um serviço a mais para manter. O `Email.enviar` do ConfortoTermico
(`app/models.py`) já fala exatamente o protocolo necessário: SMTP na 587 com
STARTTLS.

---

## 3. O que foi levantado (2026-08-30)

Conferido lendo o código dos cinco repositórios, não por inferência.

| Capacidade | ConfortoTermico | MegaSena | ControleRendaVariavel | ControleBancario |
|---|---|---|---|---|
| Framework | Flask | Flask | Flask | Django |
| Admin redefine senha de outro | sim, dentro de "editar usuário" | sim, ação própria | sim, ação própria | sim, dentro de "editar usuário" |
| Senha temporária gerada pelo sistema | **não** (admin digita) | **não** | **não** | **não** |
| Marca de "precisa trocar" | **não existe** | **não existe** | **não existe** | `must_change_password` |
| Troca obrigatória no próximo acesso | **não** | **não** | **não** | parcial — só no redirect do login |
| Pessoa troca a própria senha | **não existe** | **não existe** | **não existe** | `/change-password/` |
| Registro em auditoria | `audit_log` | log de aplicação | `auditoria.registrar` | snapshot em `core.views` |

### O ControleBancario como referência

O fluxo completo já existe lá, e vale a pena nomear as peças porque são elas
que o contrato-alvo generaliza:

- `accounts/models.py` — campo `must_change_password` no `AppUser`.
- `accounts/services.py` — `create_managed_user` liga a marca ao criar;
  `update_managed_user` religa sempre que a senha muda;
  `change_user_password` desliga ao trocar, e **exige a senha atual correta**
  (sem isso, uma sessão sequestrada vira tomada de conta permanente).
- `accounts/views.py` — `AppLoginView.form_valid` desvia para a tela de troca
  quando a marca está ligada; `change_password_view` faz a troca e chama
  `update_session_auth_hash`.

### A lacuna real do ControleBancario

A troca obrigatória é aplicada **apenas no instante do login**. Não há
middleware verificando a marca nas demais requisições: quem digitar qualquer
outra URL depois do desvio continua navegando com a senha temporária, e a
marca fica ligada para sempre sem efeito. É a única correção que este plano
faz nele.

---

## 4. Contrato-alvo

"Pronto", em qualquer um dos quatro, significa estas seis propriedades:

1. **Marca de troca pendente no usuário** — uma coluna booleana, ligada por
   quem redefine a senha de outra pessoa, desligada só pela troca feita pelo
   próprio dono.
2. **Reset do administrador gera senha temporária** e a exibe **uma única
   vez**, no retorno da própria ação. Não fica guardada em lugar nenhum em
   texto claro, não entra em log nem em auditoria — nem redigida.
3. **Criar usuário liga a marca.** Conta nova nasce com senha que outra
   pessoa conhece; é o mesmo caso do reset.
   *Exceção deliberada:* o bootstrap por CLI **não** liga a marca — quem roda
   o comando escolheu a própria senha, e não há terceiro que a conheça.
4. **Trava enquanto a marca estiver ligada**, em toda requisição, não só no
   login. A trava é um portão global (mesmo formato do `requer_login`), e
   isenta exatamente: a própria tela de troca, o logout, os estáticos e o
   `/health`. Um portão que não isenta o logout prende a pessoa dentro do
   app; um que não isenta os estáticos entrega a tela de troca sem CSS.
5. **Tela de troca da própria senha**, disponível sempre — não só sob
   obrigação. Exige senha atual, confirmação e o piso de 8 caracteres.
6. **Auditoria do que aconteceu, nunca do valor**: quem redefiniu, para quem,
   quando; e a troca feita pelo dono. O mecanismo é o que cada app já tem.

---

## 5. O que entra na biblioteca e o que fica no consumidor

Critério de entrada do SharedAuth (README dele): necessidade real em dois ou
mais consumidores, contrato coeso e testável isolado, núcleo neutro de
framework, sem banco e sem regra de domínio.

**Entra** (nasce junto do primeiro consumidor real, na Fase 1 — não antes;
foi a lição da Fase 1 da rodada anterior, quando contratos abstraídos sem
consumidor na frente tiveram de ser descartados):

| Contrato | Módulo | Por quê |
|---|---|---|
| `gerar_senha_temporaria()` | `passwords` | Alfabeto sem caracteres ambíguos (`0/O`, `1/l/I`), `secrets.choice`, comprimento acima do piso. Python puro. Ditar uma senha por telefone é o caso de uso. |
| `validar_troca(...)` | `passwords` | As três regras da troca própria — senha atual confere, confirmação bate, piso — hoje escritas só no ControleBancario. Sem banco: recebe o hash e as três strings. |
| `SenhaAtualIncorretaError`, `ConfirmacaoNaoConfereError` | `passwords` | Irmãs de `SenhaMuitoCurtaError`, mesma família `ValueError`. |
| `requer_troca_de_senha(app, ...)` | `access` | O portão da propriedade 4, no mesmo formato de `requer_login`: callback `precisa_trocar`, lista de isentos, `HX-Redirect`/401-JSON/redirect HTML, e a mesma recusa de registro duplicado. |

**Fica no consumidor**: a coluna e a migration, o modelo de usuário, as telas
e o CSS (identidade visual é de cada app, pelo critério que o próprio
SharedAuth já declara), a auditoria, e — no ControleBancario — tudo, porque
Django resolve isso nativamente e a biblioteca ali só acompanha a política.

Versão nova do SharedAuth: `v0.8.0`. Tag imutável, como sempre.

---

## 6. Ordem de execução

MegaSena → ControleRendaVariavel → ConfortoTermico → ControleBancario.

- **MegaSena primeiro**: é o mais simples dos três Flask (Flask-Login, sem
  auditoria em banco, sem papéis complexos) e já tem uma ação de reset
  isolada em `web/users.py`. É onde os contratos novos do SharedAuth nascem
  com consumidor real na frente.
- **ControleRendaVariavel em segundo**: mesma forma do MegaSena, mais a
  auditoria em banco (`app/auditoria.py`) — testa se o contrato aguenta um
  app que registra tudo.
- **ConfortoTermico em terceiro**: sessão própria (`g.usuario`, um dicionário,
  não um modelo ORM), SQL cru com marcadores `?` sobre psycopg, e a tela de
  usuários fora do padrão dos outros dois. É o que mais tem a perder, e vai
  último entre os Flask — mesmo julgamento da rodada anterior, que se
  confirmou correto.
- **ControleBancario por último**: não compartilha código com os outros, e a
  parte que faltava parecia ser só o middleware da seção 3. **Isso estava
  subestimado** — ver 11.4: ele também não tinha a senha temporária sorteada
  (propriedade 2 do contrato) nem a recusa de repetir a senha atual, e a
  política de tamanho configurável dele obrigou uma mudança na biblioteca.

Cada app é uma unidade fechada — migrar, testar, validar, **e só então** o
próximo. Sem commit e sem PR até indicação explícita do mantenedor.

---

## 7. O que valida cada app antes de passar ao próximo

Não basta a suíte ficar verde. O portão de cada app é:

1. `docker compose ... --build` — **com `--build`**. Sem ele a suíte roda
   contra a imagem anterior e passa em verde sobre o código antigo; já
   aconteceu neste conjunto de projetos.
2. Suíte completa no perfil `quality`, incluindo testes novos para: o portão
   travando uma rota qualquer, o portão isentando logout/estáticos/troca, a
   troca desligando a marca, e a senha atual errada sendo recusada.
3. **Navegador, com dados reais**, no roteiro: administrador redefine a senha
   de outra conta → senha temporária aparece uma vez → login com ela →
   qualquer URL cai na tela de troca → logout funciona de dentro da trava →
   troca com senha atual errada é recusada → troca correta libera o app →
   novo login já não pede troca.
4. Migration aplicada e conferida no banco local, e o app subindo do zero
   com o schema novo.

---

## 8. Riscos

| Risco | Por que é sério | Mitigação |
|---|---|---|
| Portão mal isentado prende todo mundo | Um `before_request` que não isenta a própria tela de troca gera redirect infinito; sem isentar o logout, ninguém sai. Trava login de produção. | Isentos declarados explicitamente e testados; roteiro do navegador cobre logout de dentro da trava. |
| Marca ligada em massa por engano | Uma migration com `server_default=true` obrigaria as quatro pessoas a trocar a senha ao mesmo tempo, sem aviso. | Coluna nasce `false` para as linhas existentes; só o reset e a criação ligam. |
| Senha temporária vazar em log | Um `_log.info(f"senha {p}")` ou um detalhe de auditoria a levaria para o disco, e nos quatro apps o log vai para arquivo. | Auditoria registra o evento, nunca o valor — regra já praticada no `reset_password` do ControleRendaVariavel. |
| ~~Sessões antigas sobrevivem à troca~~ | — | **Resolvido em 2026-08-31** (seção 11.6): `get_id()` passou a carregar a marca da senha nos três Flask. |
| Migration sem reversão automática | O `deploy.sh` faz rollback de código e imagem, nunca de schema. | Coluna nova e anulável é retrocompatível: a imagem anterior a ignora. Backup verificado antes do deploy, como sempre. |

---

## 9. Registrado para depois, com o levantamento já feito

- **"Esqueci minha senha" por e-mail** — seção 2. O que falta é coluna de
  e-mail (3 migrations), tabela de token, relay SMTP e `URL_BASE_PUBLICA`.
  A parte compartilhável seria `sharedauth.tokens` (gerar/conferir token
  guardando só o hash) e `sharedauth.email` extraído do `Email.enviar` do
  ConfortoTermico, que hoje serve a um consumidor só. No Django **não se
  reimplementa**: `django.contrib.auth` traz o fluxo inteiro pronto; ali se
  compartilha a política e o texto, como já se faz com o piso de senha.
- ~~**O destino pós-login (`next`) tem três posturas diferentes**~~ —
  resolvido em 2026-08-31, ver 11.5.
- ~~**Sessões abertas sobrevivendo à troca de senha**~~ — resolvido em
  2026-08-31, ver 11.6.
- ~~**README do SharedAuth desatualizado**~~: corrigido junto da `v0.8.0`.
- **Sessões abertas em outros navegadores sobrevivem à troca de senha** nos
  três apps Flask (Flask-Login guarda o id, não o hash). O Django já cobre pelo
  `update_session_auth_hash`. Exigiria `get_id()` derivado do hash — seção 8.

---

## 10. Fases

**As quatro fases estão concluídas** (2026-08-30).

**SharedAuth `v0.8.0` está publicado**: [PR #7](https://github.com/MSPA-Coder/SharedAuth/pull/7)
mesclado com CI verde (Testes + CodeQL) e tag `v0.8.0` empurrada. Os quatro
aplicativos foram então reconstruídos **sem** o mount de validação, instalando
a biblioteca da tag: suítes verdes (98 / 180 / 212 / 213), `/health` 200 nos
quatro, e `sharedauth.__version__ == "0.8.0"` conferido dentro dos contêineres
— inclusive o `gerar_senha_temporaria` funcionando no ControleBancario, que
instala **sem** o extra `[flask]`.

**Os quatro aplicativos continuam sem commit**: o mantenedor autoriza commit e
PR explicitamente, e essa indicação ainda não foi dada para eles. A árvore de
trabalho de cada um está com as mudanças prontas.

| Fase | Escopo | Estado |
|---|---|---|
| 1 | SharedAuth `v0.8.0` + MegaSena | **concluída** (2026-08-30); SharedAuth mesclado e com tag, MegaSena sem commit |
| 2 | ControleRendaVariavel | **concluída** (2026-08-30), sem commit |
| 3 | ConfortoTermico | **concluída** (2026-08-30), sem commit |
| 4 | ControleBancario (middleware da lacuna) | **concluída** (2026-08-30), sem commit |

---

## 11. Registro de execução e lições

Uma seção por fase. Serve ao próximo app da fila: o que se aprendeu no
primeiro não pode ser redescoberto no terceiro.

### 11.1 Fase 1 — SharedAuth `v0.8.0` + MegaSena (2026-08-30)

**Feito.** Na biblioteca: `passwords.gerar_senha_temporaria`,
`passwords.validar_troca` com três exceções novas
(`SenhaAtualIncorretaError`, `ConfirmacaoNaoConfereError`,
`SenhaNovaIgualAAtualError`) e `access.requer_troca_de_senha`. 224 testes
passam no contêiner efêmero. No MegaSena: coluna `must_change_password`
(migration `20260830_0004_change_password`), `reset_password` gerando a senha,
`change_own_password`, rota `/minha-senha` em `app/web/account.py`, portão
registrado no factory, tela de troca, bloco persistente da senha temporária na
tela de usuários, link "Minha senha" no menu, README e AGENTS.md. 98 testes
passam no perfil `quality` com `--build`, Ruff limpo.

**Validado no navegador, com dados reais** (3046 concursos): conta nova nasce
com a marca ligada; o botão Redefinir devolveu `HH7DsaShsvwQ` na tela; login
com ela cai em `/minha-senha` a partir de `/dashboard` **e** de `/contests`;
senha atual errada foi recusada; redigitar a senha temporária foi recusado;
logout funcionou de dentro da trava; a troca correta liberou o app; o login
seguinte já não pediu nada. Contas de validação (`valida-admin`,
`valida-usuario`) desativadas ao final pelo próprio serviço do projeto.

**Lições para as fases 2 e 3:**

1. **O id da revisão Alembic tem de caber em 32 caracteres.**
   `alembic_version.version_num` é `varchar(32)`. Um id maior passa pela
   geração e pela suíte e só falha no `UPDATE` do carimbo, **depois** de o DDL
   ter rodado. Aqui o DDL transacional do PostgreSQL desfez tudo junto e não
   houve o que limpar — mas contar com isso não é plano. Aconteceu com
   `20260830_0004_must_change_password` (35).
2. **A senha temporária não pode ser toast.** Nos três apps Flask o resultado
   de ação vira `data-sa-avisos`, que some sozinho — e levaria embora a única
   cópia em texto claro. Precisa de bloco persistente, e o caminho sem HTMX
   precisa **renderizar** a página em vez de redirecionar (um redirect perde
   o valor).
3. **"Nova senha diferente da atual" não é preciosismo.** Sem essa regra, quem
   é obrigado a trocar redigita a senha temporária, a marca se apaga, e a
   senha que o administrador conhece continua valendo. Foi reproduzido no
   navegador antes e depois da regra.
4. **A isenção automática de `endpoint_troca` se pagou**, e o resto da lista
   tem de trazer o logout, os **dois** endpoints de estático (`static` e
   `sharedauth_ui.static`) e o `/health`.
5. **`must_change_password` só recebe o `default=False` no flush.** Teste que
   substitui o `commit` vê `None`, não `False`. Medir "não LIGA a obrigação"
   (`is not True`) e, à parte, o padrão da coluna.
6. **A suíte do MegaSena não tem banco.** O caso "o portão deixa passar"
   precisa de rota sintética (`app.add_url_rule` dentro do teste): toda rota
   real protegida consulta o banco, e o caso "o portão barra" não expõe isso
   porque responde antes da view.
7. **Validar sem a tag publicada**: montar
   `SharedAuth/sharedauth` por cima de
   `/opt/venv/lib/python3.14/site-packages/sharedauth` no contêiner (`-v ...:ro`).
   O `requirements.txt` já aponta `v0.8.0`, mas **só constrói depois que a tag
   existir no GitHub** — a build falha em `git checkout -q v0.8.0`.
8. **O `hx-confirm` destes apps abre o modal do `sharedauth`, não o
   `window.confirm`.** Sobrescrever `window.confirm` não adianta; é preciso
   clicar no botão "Confirmar" do modal.
9. **A exceção da CLI foi validada no app real**: a conta criada por
   `flask criar-usuario` entrou direto no dashboard, sem trava.

**Mudança de contrato a repetir nos outros dois:** `reset_password` deixou de
receber a senha por parâmetro — o administrador não escolhe mais a senha de
outra pessoa. O campo de senha saiu da linha da tabela de usuários.

### 11.2 Fase 2 — ControleRendaVariavel (2026-08-30)

**Feito.** Coluna `must_change_password` (migration `20260830_0012`),
`reset_password(user_id) -> (User, senha)`, `change_own_password`, verbo
`trocar_senha` no vocabulário fechado da trilha, blueprint `account` com
`/minha-senha`, portão no factory, tela de troca, bloco persistente da senha
temporária, bloco `navbar` no `base.html` para a troca obrigatória, link
"Minha senha" na barra superior, CSS próprio, README e AGENTS.md. 180 testes
passam no perfil `quality` com `--build`, Ruff limpo.

**Validado no navegador, com dados reais**: conta nova nasce com a marca
ligada; o botão Redefinir devolveu `9syKyX7Wp7Bf` na tela; login com ela cai em
`/minha-senha` vindo de `/settings`; senha atual errada recusada com 422;
redigitar a senha temporária recusado; logout funcionou de dentro da trava; a
troca liberou o app; a tela voluntária mostra a navegação inteira sem o aviso
de obrigação. **A trilha foi conferida no banco**: `criar`,
`redefinir_senha` e `trocar_senha` registrados, `details` sem senha em nenhum
dos três. Contas de validação desativadas pela CLI do próprio projeto.

**O que foi diferente do MegaSena, e vale para a Fase 3:**

1. **A senha temporária não pode passar por `flash()`.** O `flash` do Flask
   guarda a mensagem na sessão, e a sessão é um cookie **assinado, não
   cifrado** — a senha sairia legível no cabeçalho da resposta. Vai como
   variável de contexto do template. (No MegaSena o motivo para evitar o flash
   era o toast sumir; aqui há um motivo mais forte.)
2. **O erro da troca também saiu do `flash()`**, por outro motivo: o aviso
   deste app é um toast, que desaparece sozinho. Numa tela de troca
   **obrigatória** a pessoa não tem para onde ir enquanto não trocar, e perder
   o motivo da recusa a deixa presa sem saber por quê. Erro fixo no cartão.
3. **O vocabulário da trilha é fechado e verificado por AST.** O verbo novo
   (`trocar_senha`) tinha de ser declarado em `app/auditoria.py`; um teste
   varre todas as chamadas a `registrar()` e reprova verbo não declarado.
   Verbo distinto de `redefinir_senha` de propósito: quem consulta a trilha
   precisa separar "um administrador mexeu na conta de outra pessoa" de "o
   dono trocou a própria senha".
4. **O caminho do site-packages muda por projeto.** O CRV não usa venv na
   imagem: é `/usr/local/lib/python3.14/site-packages/sharedauth`, e não
   `/opt/venv/...` como no MegaSena. Errar isso dá `ImportError` de
   `requer_troca_de_senha`, que parece regressão da biblioteca e não é.
5. **`docker compose run` sem `--build` roda a imagem anterior** — o estágio
   `quality` copia código e testes para dentro da imagem. Aconteceu nesta fase:
   quatro falhas idênticas persistiram depois de corrigidas, porque o
   contêiner rodava o código antigo.
6. **Render autenticado consulta o banco pelo tema.** O context processor de
   `app/__init__.py` lê `AppSetting` em todo render, e a suíte não tem banco;
   a saída é semear `session[CHAVE_TEMA_NA_SESSAO]` no login de teste — que é
   o mesmo cache que uma sessão real tem depois do primeiro render.
7. **Um teste de fonte com recorte por intervalo envelhece mal.**
   `test_a_senha_nunca_entra_na_trilha` recortava de `def reset_password` até
   `def set_active`; a função nova nasceu no meio e passou a estar no recorte
   sem nenhuma asserção olhando para ela. Trocado por recorte por função, com
   as duas cobertas.
8. **`change_own_password` traduz o `ValueError` da biblioteca** para
   `UserManagementError`, que é o que as rotas capturam. Sem isso a recusa
   viraria 500 na tela de troca.

### 11.3 Fase 3 — ConfortoTermico (2026-08-30)

**Feito.** Coluna `trocar_senha INTEGER NOT NULL DEFAULT 0` em
`historico.usuarios` (migration `20260830_0001_trocar_senha`),
`redefinir_senha_usuario` e `trocar_senha_propria` na camada de persistência,
`criar_usuario(..., exigir_troca=True)`, rota `auth.trocar_senha`
(`/minha-senha`) e `usuarios.redefinir_senha_rota`, portão no factory **antes**
do controle de área, tela `trocar_senha.html`, bloco persistente da senha
temporária, campo de senha removido da edição, link "Minha senha" no cabeçalho
administrativo, CSS próprio, README e AGENTS.md. 212 testes passam no perfil
`quality` com `--build`, Ruff limpo.

**Validado no navegador, com dados reais** (5 zonas, coletor online): a conta
criada pelo script de bootstrap entrou direto na SPA; a conta criada pela tela
nasceu com a marca ligada; o botão Redefinir devolveu `x3474F6y3B3m`; login com
ela caiu em `/minha-senha` vindo do login **e** de `/usuarios/`;
`GET /api/zonas` respondeu `403 {"erro": "Troca de senha obrigatória."}`; senha
atual errada e repetição da senha temporária recusadas; logout funcionou de
dentro da trava; a troca liberou a SPA; a tela voluntária mostra o subtítulo
sem o aviso de obrigação.

**O que foi diferente dos dois anteriores:**

1. **O portão vai ANTES do controle de área**, não depois. Um operador com a
   senha vencida que abre `/usuarios/` precisa cair na troca, não na recusa
   por perfil — a recusa o mandaria para a SPA e esconderia a única coisa que
   ele precisa fazer. Tem teste.
2. **A tela de troca precisa entrar em `ENDPOINTS_ABERTOS_A_QUALQUER_PERFIL`.**
   Este app nega por padrão também na camada de área: endpoint sem área
   declarada é recusado. Exigir a área "usuarios" ali deixaria todo perfil que
   não a tem preso na trava, sem a tela que a resolve. A varredura de
   `test_autorizacao_por_area.py` cobra os dois endpoints novos.
3. **`g.usuario` é um dicionário de SQL cru**, não um modelo ORM: o portão lê
   `g.usuario.get("trocar_senha")`. O `.get` (e não `[...]`) é o que mantém
   verdes as fixtures antigas de teste, que montam o dicionário à mão sem a
   chave nova.
4. **O script de bootstrap chama a mesma função da tela.** `criar_usuario`
   ganhou `exigir_troca=True` como padrão e `scripts/criar_usuario_admin.py`
   passa `False` — sem isso, o resgate do primeiro administrador nasceria
   travado. **Foi pego no navegador, não na suíte**: a primeira conta criada
   pelo script veio com a marca ligada.
5. **De novo o contêiner rodando a imagem anterior**, agora no serviço da
   aplicação e não no `quality`: o `ict` ainda tinha a imagem de antes do
   ajuste da CLI, e o script "não funcionou". `up -d --build` depois de
   qualquer mudança de código, sempre.
6. **`flash()` está fora dos dois caminhos.** A senha temporária vai no
   contexto do template (cookie de sessão é assinado, não cifrado); e o
   sucesso da troca não gera aviso nenhum, porque neste app só
   `usuarios.html` renderiza mensagem de sessão — um aviso guardado ficaria
   esperando até alguém abrir aquela tela, onde apareceria fora de contexto e
   sem CSS (só a categoria "erro" tem estilo).
7. **`alembic_version` deste projeto está em `public`**, embora as tabelas
   estejam em `historico` — conferir a revisão aplicada no schema errado dá
   "relation does not exist" e parece migração não aplicada.
8. **A tela não deixa excluir a própria conta**, então a última conta de
   validação (`valida-cli`) não tinha como sair pelo aplicativo — as outras
   duas contas de administrador do banco local têm senha desconhecida. Removida
   por `DELETE` direto no banco local, com autorização explícita do mantenedor.
   As outras duas contas de validação saíram pela própria tela.

### 11.4 Fase 4 — ControleBancario (2026-08-30)

**Feito.** `MustChangePasswordMiddleware` (`accounts/middleware.py`, registrado
depois de `AuthenticationMiddleware` e de `HtmxMiddleware`),
`reset_managed_user_password` com sorteio compartilhado,
`password_validators.current_min_length()` público, recusa de repetir a senha
atual em `change_user_password`, ação `reset_password` e bloco da senha
temporária na tela de Permissões, CSS, README e AGENTS.md. 213 testes passam no
perfil `quality` com `--build`, Ruff limpo.

**Validado no navegador, com dados reais**: conta criada pela tela nasceu com a
marca ligada; o botão Redefinir devolveu uma senha de **15** caracteres
(`q44fsC8fxPpnK9V`), o mínimo configurado nesta instalação; login com ela caiu
em `/change-password/`, e `/dashboard/` — uma tela que essa conta **tem**
permissão de ver — também; senha atual errada e repetição da temporária
recusadas; a troca liberou o Dashboard. Contas de validação excluídas pelo
serviço do próprio projeto.

**O que este app ensinou, e que os outros três não tinham como ensinar:**

1. **`sharedauth.passwords` arrastava Werkzeug no import**, e este é o único
   consumidor que instala o pacote **sem** o extra `[flask]`. O primeiro
   `import` quebrou a suíte inteira com `ModuleNotFoundError`. Corrigido **na
   biblioteca**, não aqui: o Werkzeug passou a ser importado dentro de
   `gerar_hash`/`conferir_hash`, e a política (piso, alfabeto, regras da troca)
   ficou no núcleo neutro — mesmo padrão que `sharedauth.ui` já usava. A
   alternativa seria instalar Flask, Flask-WTF e Flask-Limiter num app Django
   para gerar 12 caracteres. `test_nucleo_sem_flask.py` passou a cobrir
   `passwords`, e o README da biblioteca foi corrigido.
2. **O tamanho da senha temporária não pode ser o padrão da biblioteca.** A
   política deste app é configurável (Configurações > Parâmetros) e o banco
   local está em **15** — o sorteio de 12 era recusado pelo próprio
   `validate_password`, e a redefinição rejeitava a senha que acabara de
   sortear. `gerar_senha_temporaria` já aceitava o tamanho; quem sabe a
   política é o consumidor. Sobrou a guarda para o caso que o tamanho não
   resolve: exigência de caractere especial, que o alfabeto não tem.
3. **O `{# #}` do Django é comentário de UMA linha.** Multi-linha vaza para o
   HTML, e o projeto tem teste varrendo todos os templates. Use
   `{% comment %}`.
4. **A negação de permissão deste app já manda para "Alterar senha"** quando a
   pessoa não tem acesso a tela nenhuma (`core:inicio`). Isso mascarou a
   verificação do middleware: a conta de validação nascera sem permissão
   alguma, e todo destino caía na mesma tela por outro motivo. Só depois de
   aplicar o perfil "Consulta" ficou possível provar que é o middleware quem
   desvia.
5. **A lacuna era real e maior do que o plano supunha**: além do desvio só no
   login, faltavam a senha sorteada e a recusa de repetir a senha atual — o
   mesmo furo que os três Flask tinham.


### 11.5 Rodada seguinte — destino pós-login único (2026-08-31)

**SharedAuth `v0.9.0`**, [PR #8](https://github.com/MSPA-Coder/SharedAuth/pull/8),
mesclado e com tag. `access.url_proximo_seguro(valor)`: recebe o valor em vez
de pegá-lo da requisição, porque cada app entrega o `next` por um caminho
diferente e só a decisão de segurança é compartilhada. Devolve o **original**,
não o decodificado — `/a%2Fb` é um segmento e `/a/b` são dois. 251 testes.

**Nos três Flask.** MegaSena: `_safe_next_url` passou a ler `request.values`
(query **e** formulário) e o template ganhou o campo escondido — o destino era
descartado em todo login, e o teste que existia exercitava só a função, nunca o
POST. ControleRendaVariavel: `_local_next_url` removida; achado no caminho que
`/privacy/toggle-values` era um **segundo** consumidor do mesmo `next`, também
migrado. ConfortoTermico: a view passou a ler o campo escondido que já existia
no template desde sempre — o teste que registrava "ignora next" como decisão
foi reescrito, porque não era decisão, era implementação que faltava.

Suítes: 108 / 187 / 219. Validado por requisição real nos três, no caminho
interno e nas recusas (`https://`, `//`, `%5C%5C`).

### 11.6 Rodada seguinte — a sessão amarrada à senha (2026-08-31)

**SharedAuth `v0.10.0`**, [PR #9](https://github.com/MSPA-Coder/SharedAuth/pull/9),
mesclado e com tag. `session.marca_de_sessao` (HMAC do **hash** da senha com a
`SECRET_KEY` do consumidor), `marcas_conferem` (tempo constante; marca ausente
nunca confere), `identificador_de_sessao`/`separar_identificador`. Tudo Python
puro, no núcleo neutro, coberto por `test_nucleo_sem_flask.py` — o consumidor
de sessão própria usa as mesmas funções.

**Nos três Flask.** MegaSena e ControleRendaVariavel: `User.get_id()` passou a
devolver `id:marca`, e o `user_loader` confere. ConfortoTermico, que tem sessão
própria: a marca vai em `session["marca_senha"]` e o
`_carregar_usuario_da_sessao` confere. Nos três, a troca da própria senha
**renova a sessão de quem trocou** — o efeito desejado é derrubar as outras.

**Efeito no deploy: as sessões abertas caem uma vez**, no primeiro acesso,
porque o identificador antigo deixa de valer. Cada pessoa entra de novo, uma
vez só.

Validado com duas sessões simultâneas do mesmo usuário em cada app: a que
trocou continuou em 200, a outra caiu para o login. Suítes: 108 / 187 / 219.
O ControleBancario já tinha isso pelo `update_session_auth_hash` do Django.

**Duas armadilhas de teste que valem para o futuro:**

1. **O `_login_as` do ControleRendaVariavel vazava entre testes.** Lá o
   `@user_loader` é registrado no *import do módulo*, não dentro de
   `create_app`: substituir o callback por atribuição direta contaminava todo
   teste seguinte, e os novos — que existem para exercitar o carregador de
   verdade — falhavam só na suíte completa. Passou a usar `monkeypatch`. No
   MegaSena o registro é dentro do factory, e por isso o mesmo padrão não
   vazava lá.
2. **O Git Bash converte `/usuarios/` em `C:/Program Files/Git/usuarios/`**
   dentro de argumentos de `curl`. Uma validação por linha de comando pode
   reprovar por isso e parecer defeito da aplicação — foi o que pareceu aqui
   por alguns minutos. `MSYS_NO_PATHCONV=1`, ou o corpo num arquivo.
