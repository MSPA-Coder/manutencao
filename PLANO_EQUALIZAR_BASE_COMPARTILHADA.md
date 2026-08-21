# Plano — equalizar o que sobrou de base compartilhada entre os projetos

Iniciado e concluído em 2026-08-20. **Status: as sete fases estão fechadas —
código, documentação, verificação, merge e implantação. Os quatro projetos
estão em produção com a mudança, e não sobrou nenhuma pendência aberta em
nenhum dos seis repositórios.**

Documentos irmãos:
[PLANO_UNIFICAR_AUTENTICACAO.md](PLANO_UNIFICAR_AUTENTICACAO.md) — a rodada
anterior do mesmo tipo de trabalho, concluída; é a referência de forma, de
risco e de mecânica (biblioteca privada, token de leitura, ordem de adoção).

---

## 1. O problema, em uma frase

A rodada anterior tirou login e mensagens do "cada um do seu jeito" e pôs
numa biblioteca. Ela era um plano **de autenticação** — então quatro outros
temas que sofrem exatamente do mesmo mal ficaram de fora e continuam
escritos três ou quatro vezes, com deriva já acontecendo entre as cópias.

Este plano fecha esses quatro temas. Não introduz nenhum mecanismo novo:
usa o SharedAuth que já existe, já está instalado nos três apps Flask e já
tem token de leitura, CI e versionamento por tag funcionando.

---

## 2. O que foi levantado (2026-08-20)

Conferido lendo o código de cada projeto, não por inferência.

### Tema A — cabeçalhos de segurança e CSP

| | ConfortoTermico | MegaSena | ControleBancario | ControleRendaVariavel |
|---|---|---|---|---|
| Onde mora | `app/app_factory.py:59` | `app/core/security.py` | `core/security.py` (middleware) | `app/__init__.py:145` |
| Como aplica | `@app.after_request` | `after_app_request` no blueprint | middleware Django próprio | **Flask-Talisman** + gancho para sobrescrever |
| CSP | string à mão | string à mão | string à mão | dicionário do Talisman |
| `font-src` | `'self'` | `'self'` | **`'self' data:`** | via Talisman |
| `Permissions-Policy` | 3 diretivas | 3 diretivas | 3 diretivas | **4** (`browsing-topics=()`) |

Os dicionários do ConfortoTermico e do MegaSena são idênticos — inclusive o
comentário acima deles, copiado junto, que diz *"manter igual em todos é o
que permite auditar um e confiar nos demais"*. Hoje isso é mantido na unha,
e as duas diferenças da tabela mostram que a unha já falhou. É o item de
maior risco do plano, porque é código de segurança.

O caso do ControleRendaVariavel é o mais delicado: ele registra o gancho
`_cabecalhos_defensivos` **antes** do Talisman de propósito, para que o Flask
o execute **depois** (a ordem dos `after_request` é inversa à do registro) e
consiga sobrescrever o `Permissions-Policy` que o Talisman escreve. É
correto, mas é conhecimento frágil que mora num comentário.

### Tema B — formatação de dinheiro e números em pt-BR

| | MegaSena | ControleBancario | ControleRendaVariavel |
|---|---|---|---|
| Onde mora | `app/core/formatting.py` | `core/templatetags/money_filters.py` | `app/presentation.py:47` |
| Milhar/decimal | troca `,` por `.` (sem centavos) | truque do `\x00` | **mesmo truque do `\x00`** |
| Valor zero | vazio | vazio | — |
| Valor nulo | vazio | `R$ 0,00` | `-` |
| Classe CSS por sinal | não | sim (`amount-*`, `card-*`) | sim |

As rotinas do ControleBancario e do ControleRendaVariavel são a mesma função
copiada caractere por caractere, incluindo o truque de usar `\x00` como
marcador temporário na troca de separadores. O MegaSena é uma terceira
variante, mais pobre. As regras de "o que mostrar quando não há valor"
divergem sem motivo.

Detalhe importante: **isto é Python puro, sem Flask e sem Django.** É o único
tema deste plano em que o ControleBancario pode compartilhar código de fato,
e não só acompanhar a política. Ver decisão D1.

### Tema C — endpoint de saúde

| | ConfortoTermico | MegaSena | ControleBancario | ControleRendaVariavel |
|---|---|---|---|---|
| Rota | `/health` | **não existe** | `/health/` | `/health` |
| Consulta o banco | sim | — | sim | sim (`select 1`) |
| Healthcheck do Compose bate em | `/health` | **`/`** | `/health/` | `/health` |

O MegaSena é um defeito real, não uma inconsistência estética: o healthcheck
do container bate na raiz, então o Docker considera o serviço saudável
enquanto a tela de login responder — inclusive com o banco fora do ar.
Achado no levantamento deste plano, não relatado antes.

### Tema D — encanamento de CI e Docker

Os quatro seguem o mesmo padrão (perfil `quality` no Compose, CA efêmera
gerada na CI, token de leitura do SharedAuth injetado como secret de build),
escrito quatro vezes:

| | ConfortoTermico | MegaSena | ControleBancario | ControleRendaVariavel |
|---|---|---|---|---|
| Arquivo do token | `github_token.txt` | `github_token.txt` | — (não consome) | **`github_token`** |
| Grupo de concorrência | `ci-...` | sem prefixo | — | `ci-...` |
| Job de contratos de runtime | sim | não | não | sim |
| Bloco Python que valida o Postgres | **duplicado idêntico** | — | — | **duplicado idêntico** |

Aqui **não cabe biblioteca Python** — cabe convenção escrita e, onde valer a
pena, um workflow reutilizável do GitHub Actions.

---

## 3. O que este plano deliberadamente não toca

| Tema | Por que fica fora |
|---|---|
| Identidade visual / CSS | Cada app tem paleta própria de propósito (escuro industrial no ConfortoTermico, azul bancário, verde de investimentos). É diferença legítima, não deriva. O CSS de mensagens de status já é compartilhado desde a rodada anterior. |
| Modelo de autorização | Decidido e justificado na rodada anterior; continua válido. |
| Tela de administração de usuários | Decisão do mantenedor em 2026-08-20: fica fora. Depende do modelo de usuário de cada app, que é realmente diferente. Consequência aceita: o ControleRendaVariavel continua sem tela de usuários. |
| Formato do BackupRestore | É ferramenta de host, não app conteinerizado. Sua CI ser diferente das outras quatro está certo. |
| SSO / login único | Fora desde a rodada anterior. |

---

## 4. Decisões já tomadas pelo mantenedor (2026-08-20)

- **Escopo:** os quatro temas (A, B, C, D) entram nesta fase.
- **Onde mora o código novo:** ampliar o **SharedAuth**, sem renomear o
  pacote. O nome fica apertado para CSP e formatação, mas renomear
  quebraria os imports e o encanamento de token/CI dos três apps por ganho
  cosmético. Ajustar a descrição do repositório e do `README`, não o pacote.
- **Tela de usuários:** fora desta fase.

---

## 5. Decisão que ainda precisa da sua validação

**D1 — o ControleBancario (Django) deve instalar a biblioteca para o Tema B?**

Hoje o `pyproject.toml` do SharedAuth exige Flask, Flask-WTF e Flask-Limiter
para qualquer coisa. Instalar isso num projeto Django seria peso morto.

- **Recomendado:** tornar o núcleo sem dependência nenhuma e pôr o Flask
  num extra — `sharedauth` puro (formatação, constantes de CSP e
  cabeçalhos) e `sharedauth[flask]` (sessão, CSRF, rate-limit, acesso,
  mensagens). Os três apps Flask trocam a linha de requisito uma vez, no
  mesmo PR em que adotam a v0.2.0. O ControleBancario passa a compartilhar
  de verdade a formatação e os valores dos cabeçalhos, aplicando-os pelo
  seu próprio middleware.
- **Alternativa mais conservadora:** o ControleBancario não instala nada e
  só acompanha a política, como já faz no piso de senha. Mais simples, mas
  deixa a formatação de dinheiro duplicada entre Django e biblioteca — que
  é justamente a cópia caractere por caractere que motivou o Tema B.

Sem essa decisão, as Fases 1 e 5 não podem começar. As Fases 2, 3 e 4 não
dependem dela.

---

## 6. Fases de execução

| Fase | O que é | Status |
|---|---|---|
| 0 | Conferir o que ficou por verificar (abaixo) | ✅ |
| 1 | SharedAuth ganha `security`, `formatting` e `health`; tag `v0.2.0` | ✅ mesclado, `v0.2.0` publicada |
| 2 | MegaSena adota + ganha `/health` de verdade | ✅ mesclado e implantado |
| 3 | ControleRendaVariavel adota (Talisman saiu) | ✅ mesclado e implantado |
| 4 | ConfortoTermico adota | ✅ mesclado e implantado |
| 5 | ControleBancario — só o núcleo | ✅ mesclado e implantado |
| 6 | Tema D: convenção de CI/Docker | ✅ parcial, com um item recusado por julgamento |
| 7 | Documentação nos `README`/`AGENTS.md` | ✅ mesclado nos quatro |

Legenda: ⬜ pendente · 🔄 em andamento · ✅ concluído · ⏭️ pulado · ⚠️ bloqueado.

A ordem repete a que deu certo na rodada anterior: o app de menor risco
primeiro, o de mecanismo mais divergente por último.

### Fase 0 — conferir antes de mexer

- Confirmar que o MegaSena realmente não tem rota de saúde (o levantamento
  não achou nenhuma em `app/web/` nem em `app/core/`).
- Ler a política completa do Talisman no ControleRendaVariavel e comparar,
  diretiva por diretiva, com a string à mão dos outros dois — o levantamento
  comparou só o que estava visível.
- Verificar se o ConfortoTermico tem alguma formatação de número em pt-BR
  (o Tema B não achou nenhuma; se existir, entra na tabela).
- Confirmar se o `font-src 'self' data:` do ControleBancario é necessário
  (alguma fonte embutida em base64?) ou se é sobra.

### Fase 1 — SharedAuth v0.2.0

Três módulos novos, todos extraídos do que já existe, nenhum inventado:

- `sharedauth.security` — `SECURITY_HEADERS`, `CONTENT_SECURITY_POLICY` e
  uma função que registra ambos num app Flask. As duas constantes são
  Python puro, importáveis também pelo Django.
- `sharedauth.formatting` — número pt-BR, moeda, percentual, com as regras
  de valor nulo e zero decididas uma vez só.
- `sharedauth.health` — rota `/health` que consulta o banco e devolve JSON
  no mesmo formato nos três.

Cada módulo com teste, como os seis atuais. A CI do SharedAuth já é verde e
não muda.

### Fase 2 — MegaSena

Menor risco: é o app cujo `security.py` é o mais próximo do que vai para a
biblioteca. Além da troca, ganha a rota `/health` e o `healthcheck:` do
`compose.yaml` passa a apontar para ela. Corrigir isso aqui é o que dá valor
imediato à fase.

Aproveitar a passagem para avaliar o `restart: unless-stopped` que falta no
`compose.yaml` do MegaSena — pendência antiga registrada em
[PLANO_MANUTENCAO.md](PLANO_MANUTENCAO.md), seção "Pendências gerais".

### Fase 3 — ControleRendaVariavel

**A decisão de forma desta fase:** sair do Flask-Talisman ou mantê-lo?

Recomendação: **sair**. O Talisman só está sendo usado para CSP, HSTS e
cookie seguro; o CSP e os defensivos passam a vir da biblioteca, o cookie já
vem do `sharedauth.session`, e sobra o `force_https` — que o proxy reverso
já faz. Sair elimina uma dependência, elimina a inversão de ordem de
registro que hoje depende de um comentário para não quebrar, e é o que torna
os três apps de fato iguais neste tema. Se o `force_https` do Talisman
estiver cobrindo algo que o proxy não cobre, mantê-lo e só remover a parte
de CSP — decidir na Fase 0, olhando o Caddy/nginx.

### Fase 4 — ConfortoTermico

Mesma troca, sem nada de especial: o dicionário e a string dele já são
idênticos ao do MegaSena. É o app mais arriscado da rodada anterior, mas
neste tema é o mais simples dos três.

### Fase 5 — ControleBancario

Conteúdo depende de D1. Em qualquer cenário, alinhar o `font-src` e o
`Permissions-Policy` com os outros três (ou justificar a diferença por
escrito, no próprio arquivo).

### Fase 6 — convenção de CI e Docker

- Renomear `.secrets/github_token` para `github_token.txt` no
  ControleRendaVariavel (os outros dois já usam `.txt`); ajustar
  `compose.yaml`, `ci.yml` e o checkout do VPS na mesma passada.
- Padronizar o grupo de concorrência (`ci-${{ github.workflow }}-...`) nos
  quatro.
- Resolver o bloco Python duplicado que valida o contrato do Postgres —
  workflow reutilizável ou script versionado; decidir na hora, olhando qual
  dá menos cerimônia.
- Padronizar o nome dos arquivos de exemplo de ambiente (hoje há
  `.env.example`, `.env.docker.example` e `.env.vps.example` distribuídos
  de forma desigual entre os quatro).

**Cuidado operacional:** renomear arquivo de segredo mexe em produção. O
checkout do VPS precisa do arquivo novo antes de o deploy rodar, exatamente
como aconteceu com o token do SharedAuth na rodada anterior.

### Fase 7 — documentação

Uma frase curta no `README.md`/`AGENTS.md` de cada projeto, no mesmo formato
já usado para o SharedAuth na Fase 6 da rodada anterior: o que passou a vir
da biblioteca e o que continua próprio.

---

## 7. Riscos

| Risco | Por quê | Mitigação |
|---|---|---|
| Afrouxar o CSP sem perceber | Consolidar quatro políticas numa tende a virar a união delas, e a união é mais permissiva que cada uma | Partir da política mais restritiva e abrir só o que quebrar, com o motivo escrito |
| Quebrar o `Permissions-Policy` do ControleRendaVariavel | A ordem de registro dos ganchos é o que faz funcionar hoje | Teste de regressão que lê o cabeçalho na resposta, não o código |
| Renomear segredo e travar o deploy | O VPS precisa do arquivo novo antes | Copiar o arquivo novo antes do merge, mesma sequência da rodada anterior |
| Mudar o layout de dependências (D1) | Os três apps Flask instalam por linha de requisito com tag | Trocar a linha no mesmo PR da adoção da v0.2.0, nunca antes |

---

## 8. Pendências soltas encontradas no levantamento

Não fazem parte deste plano; registradas para não se perderem.

- `BackupRestore`: `main` local tem **3 commits sem push**.
- `MegaSena`: branch `fix/htmx-indicator-csp` commitado e **sem push**
  (já registrado na rodada anterior; segue pendente).

---

## 9. Log de sessões

### Sessão 1 — 2026-08-20

Levantamento dos quatro temas, lendo o código dos seis repositórios. Escopo
e formato decididos pelo mantenedor (seção 4). Plano escrito. Nenhum arquivo
de projeto alterado. Próximo passo: validar D1 e começar a Fase 0.

### Sessão 2 — 2026-08-20 (mesma conversa)

**D1 aprovado** (núcleo sem dependência, Flask no extra `[flask]`), junto com
as demais recomendações. Autorizadas as Fases 0 a 3 em sequência.

**Fase 0 — concluída.** Os quatro pontos, conferidos no código:

1. **MegaSena não tem rota de saúde nenhuma** — confirmado varrendo todas as
   rotas registradas (`app/web/*.py`): só `/`, `/dashboard`, `/login`,
   `/bets`, `/contests`, `/settings`, `/usuarios` e derivadas. O
   `healthcheck:` batia em `/`, que sem sessão redireciona para `/login`; o
   `urlopen` segue o redirect e recebe 200. Daí o container se declarar
   saudável com o banco fora.
2. **Talisman do ControleRendaVariavel é descartável.** A política efetiva
   dele é idêntica, diretiva por diretiva, à string escrita à mão nos outros
   dois — as diretivas que ele não declara caem em `default-src 'self'`, que
   dá o mesmo resultado. A única diferença real é `img-src`, e para *menos*:
   o Talisman não libera `data:`. Quanto ao resto do que ele faz, o
   `deploy/nginx/controle-renda-variavel.conf` já redireciona 80→443
   (`return 301`) e já emite `Strict-Transport-Security max-age=31536000`, e
   o cookie `Secure` já vem do `sharedauth.session`. Não sobra função.
3. **ConfortoTermico não tem formatação pt-BR de saída** — os
   `replace(",", ".")` espalhados por `database_*.py`/`thermal_indices.py`
   são *leitura* de entrada com vírgula decimal, o contrário de formatar. O
   projeto não registra nenhum filtro Jinja. Fica fora do Tema B, como o
   levantamento supunha.
4. **`font-src 'self' data:` do ControleBancario é sobra** — o projeto não
   tem `@font-face` nem nenhum arquivo de fonte versionado. Não subiu para o
   conjunto comum.

Achado extra da Fase 0, que muda uma decisão do Tema A: **`img-src data:` é
necessário de verdade**, mas só em dois dos quatro, e por um motivo só —
MegaSena e ControleBancario declaram o favicon como SVG embutido no
`<link rel="icon">` do `base.html`. ConfortoTermico e ControleRendaVariavel
não têm favicon nenhum. Consolidar as quatro políticas numa só não podia
virar a união delas (mais permissiva que qualquer uma), então `data:` virou
exceção explícita por parâmetro, e não regra.

Achado extra sem ação: o `restart: unless-stopped` que o
`PLANO_MANUTENCAO.md` listava como faltando no MegaSena **já está lá**, nos
dois serviços. Pendência velha, resolvida em algum momento e não riscada.

**Fase 1 — código pronto, publicação bloqueada.** Três módulos novos no
SharedAuth (`security`, `formatting`, `health`), o núcleo sem dependência
nenhuma e o Flask movido para o extra `[flask]`. 75 testes passam (eram 36),
incluindo regressão da isenção de rate-limit em `/health` e um teste que
importa o núcleo num interpretador limpo para garantir que ele não voltou a
arrastar Flask. PR aberto e **CI verde**:
[SharedAuth#1](https://github.com/MSPA-Coder/SharedAuth/pull/1). O merge foi
**recusado pelo classificador do modo automático** — sem o merge não há tag
`v0.2.0`, e sem a tag as Fases 2 e 3 não têm o que instalar.

**Fase 2 — código pronto, não verificado.** MegaSena: `core/security.py` e
`core/formatting.py` viraram adaptadores finos sobre a biblioteca (assinaturas
preservadas, nenhum dos ~15 pontos de chamada foi tocado); rota `/health` com
sonda de banco, isenta de rate-limit e adicionada a `PUBLIC_ENDPOINTS`;
`healthcheck:` do Compose repontado para ela; `requirements.txt` em
`sharedauth[flask]@v0.2.0`; `tests/test_health.py` novo. Só a sintaxe foi
conferida — a suíte roda no perfil `quality` do Docker, que precisa da tag.

**Próximo passo:** mesclar o SharedAuth#1, publicar a tag `v0.2.0`, e então
rodar o `quality` do MegaSena.

### Sessão 3 — 2026-08-20 (mesma conversa, após o mantenedor mesclar)

**Fase 1 concluída.** [SharedAuth#1](https://github.com/MSPA-Coder/SharedAuth/pull/1)
mesclado pelo mantenedor, tag `v0.2.0` publicada.

**Fase 2 concluída** —
[mega-sena#26](https://github.com/MSPA-Coder/mega-sena/pull/26), CI verde.
49 testes no `quality` (eram 46). O conserto do health check foi **provado
com o banco parado de propósito**, e a tabela abaixo é o levantamento inteiro
deste plano condensado numa linha:

| | antes (`/`) | agora (`/health`) |
|---|---|---|
| banco no ar | 200 | 200 `{"status":"ok"}` |
| banco parado | **200** | **503** `{"status":"erro"}` |

Navegador com dados reais: `/contests` com o filtro `brl0` formatando
`R$ 42.842.470` e deixando vazio onde não há prêmio, `/bets` com
`50.063.860` e `0,00000999%`. Nenhuma mudança visual, console limpo.

Detalhe de processo: as alterações foram feitas por engano sobre o branch
`fix/htmx-indicator-csp` (que estava com checkout ativo e tem um commit sem
push) e movidas para um branch a partir do `main` antes do commit. O
`fix/htmx-indicator-csp` segue pendente, intocado.

**Fase 3 concluída** —
[ControleRendaVariavel#19](https://github.com/MSPA-Coder/ControleRendaVariavel/pull/19),
CI verde nos dois jobs. 122 testes (eram 119). **O Flask-Talisman saiu**,
como a Fase 0 indicava: a política efetiva dele era idêntica diretiva por
diretiva, e nginx + `sharedauth.session` já cobriam o resto. Sumiu junto a
inversão de ordem de registro dos `after_request` de que o arquivo dependia
— era correto, mas era conhecimento que morava num comentário.

Navegador com dados reais: tela de Posição nas duas moedas, `R$ 14,20`,
`R$ -5.399` (com `trim`), `US$ 476,58`, quantidade fracionária `1,5636`,
`-37,80%`, HHI `0,227`. Nenhuma mudança visual.

**Achado à parte, não corrigido:** o console do ControleRendaVariavel acusa
violação de `style-src 'self'`. É **pré-existente** — a política efetiva não
mudou no PR, já que o Talisman não declarava `style-src` e caía em
`default-src 'self'` — e tem a mesma causa já diagnosticada e corrigida no
MegaSena: `htmx.config.includeIndicatorStyles` é `true` por padrão e o HTMX
injeta um `<style>` sem nonce no carregamento. Ruído de console sem efeito
visível; a correção é a mesma de uma linha, mas é bug pré-existente e merece
verificação visual própria. Candidato natural a entrar junto da Fase 4
(ConfortoTermico não usa HTMX, então lá não se aplica).

**Próximo passo:** mesclar os dois PRs e implantar no VPS (`~/deploy.sh
megasena` e `~/deploy.sh renda`) antes de começar a Fase 4.


---

## 10. Estado final da rodada (2026-08-20)

### O que está em produção

| Projeto | Commit | Saúde |
|---|---|---|
| MegaSena | `eefedf7` | HTTP 200, `/health` respondendo `ok` |
| ControleRendaVariavel | `bbf903f` | HTTP 200, `/health` respondendo `ok` |
| ConfortoTermico | `cf31803` | HTTP 200, ICT e coletor `healthy` |
| ControleBancario | `422a9f9` | HTTP 200 |

`~/deploy.sh --status` mostra os quatro com VPS e GitHub no mesmo commit e
árvore limpa.

### Prova de que o conjunto ficou de fato igual

Conferido na resposta HTTP dos quatro endereços públicos, não no código:

```
Permissions-Policy: camera=(), microphone=(), geolocation=(), browsing-topics=()
```

idêntico nos quatro. E a única diferença de CSP é a que foi pedida por nome,
com motivo escrito no ponto da chamada:

| | `img-src` |
|---|---|
| ControleBancario | `'self' data:` — favicon SVG embutido |
| MegaSena | `'self' data:` — favicon SVG embutido |
| ConfortoTermico | `'self'` |
| ControleRendaVariavel | `'self'` |

### O secret que faltava

`SHAREDAUTH_READ_TOKEN` criado pelo mantenedor em
`MSPA-Coder/sistema-financeiro` às 01:02 de 2026-08-21. A CI ficou verde na
primeira re-execução e o merge saiu em seguida
([sistema-financeiro#24](https://github.com/MSPA-Coder/sistema-financeiro/pull/24)).
O `~/deploy.sh bancario` rodou sem passo extra, como previsto — o
`.secrets/github_token.txt` já estava no VPS —, e levou junto o commit de
documentação da rodada anterior, que nunca tinha sido implantado.

### Defeitos reais encontrados e corrigidos no caminho

Nenhum deles era o objetivo da rodada; todos apareceram por rodar as
aplicações de verdade, não pela suíte.

1. **Health check do MegaSena mentia.** Batia em `/`, que sem sessão
   redireciona para `/login`; o `urlopen` seguia o redirect e recebia 200.
   Provado com o banco parado: `/` respondia 200 e `/health` responde 503.
2. **Isenção de rate limit do coletor do ConfortoTermico nunca funcionou.**
   `limiter.exempt(health)` com o retorno descartado — `exempt` devolve
   função nova. **Terceiro** ponto com essa causa-raiz nestes projetos
   (login do MegaSena, polling do dashboard do ConfortoTermico, este).
   Achado só porque o app do coletor não sobe na suíte e quebrou ao subir.
3. **As IBM Plex do ConfortoTermico nunca carregaram.** `_layout_auth.html`
   e `index.html` linkavam o Google Fonts, que a CSP `style-src 'self'` do
   projeto sempre bloqueou. A tela sempre mostrou o fallback. Links
   removidos: sem mudança visual, um erro de console a menos.
4. **`<style>` do HTMX violando a CSP** no MegaSena e no
   ControleRendaVariavel (`includeIndicatorStyles`, `true` por padrão, sem
   nonce). Corrigido nos dois; no ControleRendaVariavel o estilo era peso
   morto puro — o projeto não usa `hx-indicator` em lugar nenhum.

### Sobras de política que saíram

- `img-src data:` do ConfortoTermico — nada no projeto usa URI `data:`.
- `font-src data:` do ControleBancario — o projeto não tem `@font-face` nem
  arquivo de fonte.
- `img-src data:` continua em MegaSena e ControleBancario, agora **pedido por
  nome** (`imagens_data_uri=True`), pelo favicon SVG embutido no `<link>`.

### Fase 6: o que foi feito e o que foi recusado

**Feito:** prefixo `ci-` no grupo de concorrência dos cinco projetos;
`.secrets/github_token` do ControleRendaVariavel renomeado para
`github_token.txt`, com o arquivo novo criado no VPS **antes** do merge, os
dois nomes coexistindo durante a troca e o antigo removido depois de
implantado.

**Recusado — deduplicar o bloco Python que valida o contrato do Postgres.**
O plano previa. São ~15 linhas de asserção duplicadas entre a CI do
ConfortoTermico e a do ControleRendaVariavel, e como são **repositórios
diferentes**, compartilhar exigiria um workflow reutilizável hospedado num
terceiro repositório. Isso acopla a CI de dois projetos a um terceiro para
economizar 15 linhas, e as duas cópias nem são idênticas (o serviço se chama
`postgres` num e `db` no outro). O acoplamento custa mais que a duplicação.

**Recusado — uniformizar os nomes dos arquivos de exemplo de ambiente.**
Hoje: ConfortoTermico tem `.env.example` + `.env.docker.example`;
ControleBancario e MegaSena têm `.env.docker.example` + `.env.vps.example`;
ControleRendaVariavel tem só `.env.example`. Parece deriva, mas o conteúdo
difere porque a forma de operar difere, e renomear arquivo que um operador
consulta é churn com risco de confusão real. Se for para uniformizar, o que
falta primeiro é decidir *quais* ambientes cada projeto documenta — decisão
de conteúdo, não de nome de arquivo.

### Pendência separada, fora deste plano — resolvida

[BackupRestore#7](https://github.com/MSPA-Coder/BackupRestore/pull/7) publicou
os quatro commits que estavam só locais (Camada 2 do backup do VPS) e
**foi mesclado**. Os testes passam e o `main` está com CI verde.

O bloqueio eram 11 alertas do CodeQL: 10 `py/path-injection` e, depois do
merge, um `py/command-line-injection` **crítico** em `motor.py` que só
apareceu na análise do `main`. Todos dispensados como falso positivo (os de
teste, como "used in tests"), cada um com a justificativa no comentário de
dispensa. O repositório tem **zero alertas abertos**.

A dispensa se sustenta em quatro barreiras, e as duas do lado do servidor
foram **conferidas no VPS**, não deduzidas da documentação:

1. `motor._rodar` chama `subprocess.run` com lista, sem `shell=True`.
2. `authorized_keys` prende a chave com
   `command="/home/ubuntu/backup-agent.sh"` mais `no-pty`,
   `no-port-forwarding`, `no-agent-forwarding` e `no-X11-forwarding` — a
   string que o cliente monta nunca roda como comando remoto.
3. O agente quebra `SSH_ORIGINAL_COMMAND` com `read -r -a` (sem `eval`, sem
   substituição), aceita quatro verbos e recusa o resto; `resolver_dump`
   ainda confere com `realpath`.
4. Do lado do cliente, `_PADRAO_LISTAGEM` (que não admite barra, `..` nem
   metacaractere de shell) e `caminho_sob_raiz`.

O raciocínio ficou no repositório, não só no comentário de dispensa:
[BackupRestore#8](https://github.com/MSPA-Coder/BackupRestore/pull/8) põe a
nota no topo de `vps.py`, incluindo **o que invalidaria as dispensas** —
afrouxar `_PADRAO_LISTAGEM`, tirar o `command=`, ou o agente passar a avaliar
`SSH_ORIGINAL_COMMAND`.

**Tentativa de trocar a dispensa por uma correção que a ferramenta
confirmasse — não deu certo, e o registro do porquê vale mais que a
tentativa.** A ideia era escapar o argumento com `shlex.quote` antes de ele
entrar na linha do `ssh`, para o CodeQL reconhecer o sanitizador sozinho em
vez de depender de um julgamento humano guardado num comentário de dispensa.
O escape entrou ([BackupRestore#9](https://github.com/MSPA-Coder/BackupRestore/pull/9),
4 testes novos), mas **não silenciou o alerta**. Verificado sem margem para
dúvida: o alerta foi reaberto de propósito depois da correção, a análise
rodou no commit `7d2dd3e` já com o escape, e continuou apontando
`motor.py:88`.

O motivo é que a preocupação do CodeQL é outra, anterior: dado não confiável
chegando a um `subprocess.run`, e um argumento controlado por terceiro
podendo virar *flag* do programa invocado. `shlex.quote` escapa metacaractere
de shell, não injeção de argumento — não é barreira para essa regra. O
`shlex.quote` ficou assim mesmo, porque protege o shell remoto de verdade,
que é preocupação real e diferente; a nota em `vps.py` foi corrigida para
parar de prometer o que não entrega
([BackupRestore#10](https://github.com/MSPA-Coder/BackupRestore/pull/10)).

**Conclusão prática para a próxima vez que um alerta destes aparecer:** neste
projeto a dispensa com justificativa escrita no código é o caminho, não uma
etapa provisória. Duas coisas não funcionam e já foram testadas — comentário
`# codeql[...]` (o code scanning do GitHub ignora supressão por comentário;
só a CLI do CodeQL a honra) e `shlex.quote` como sanitizador reconhecido.

### Faxina final (2026-08-20)

As oito branches locais de PRs já mesclados foram apagadas, local e remoto,
depois de confirmar pelo estado do PR (não pelo `git log`, que diverge quando
o merge é *squash*). Os seis repositórios ficaram com `main` só, árvore
limpa, nada sem push e nenhum PR aberto.
