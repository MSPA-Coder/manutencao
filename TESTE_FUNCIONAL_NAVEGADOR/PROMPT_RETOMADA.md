# Prompt de retomada — para passar a outra IA

Copie tudo o que está abaixo da linha e entregue como primeira mensagem.

---

## Contexto

Você vai terminar uma auditoria funcional que já está ~95% pronta. Ela testa,
pelo navegador e em uso real, quatro sistemas do mantenedor rodando localmente
em Docker. Quatro subagentes percorreram menu por menu, criando, alterando,
excluindo, gerando relatórios e conferindo contas na mão. Produziram 61
achados. **Três sistemas estão concluídos. Falta terminar um.**

Tudo vive em `C:\Users\MSPA\Dropbox\Programacao\VSCodeProjects\_manutencao\TESTE_FUNCIONAL_NAVEGADOR\`.

**Leia primeiro, nesta ordem:**

1. `ANDAMENTO.md` — situação, roteiro de retomada, decisões e o que já foi
   limpo. É curto.
2. `STATUS_CB.md` — o estado do agente do ControleBancario, escrito por ele
   mesmo. Tem uma lista numerada de 7 itens: "Não executado — retomar a partir
   daqui". **É o seu roteiro imediato.**
3. `README.md` — o contrato de execução comum (severidades, formato do achado,
   regra de ouro dos dados, bateria transversal).
4. `PROMPT_ControleBancario.md` — o roteiro completo do sistema, blocos 6 e 7.

Só depois, se precisar de contexto: `CONCLUSOES_TRANSVERSAIS.md` (a análise) e
os quatro `RELATORIO_*.md` (a prova bruta, 3.345 linhas — não leia inteiro).

## Ambiente

Nove contêineres Docker, todos locais, todos ligados a `127.0.0.1`:

| Sistema | App | Postgres | Pilha |
|---|---|---|---|
| ConfortoTermico | 5001 | 5002 | Flask + SharedAuth |
| MegaSena | 5101 | 5102 | Flask + SharedAuth |
| ControleBancario | 5201 | 5202 | **Django + HTMX** (não usa SharedAuth) |
| ControleRendaVariavel | 5301 | 5302 | Flask + SharedAuth + Chart.js |

Confirme com `docker ps` que os nove estão `healthy` antes de começar.

**Nada nesta tarefa toca o VPS nem qualquer endereço público. Só localhost.**

## O que falta fazer — três entregas

### 1. Terminar o ControleBancario (porta 5201)

Blocos 1 a 5 concluídos, bloco 6 quase. Siga a lista de 7 itens do
`STATUS_CB.md`. Em resumo: restaurar os Parâmetros aos valores originais que o
agente anotou, fechar Trilha de auditoria (`/settings/audit-log/`), abrir
`/change-password/` só para ver a validação **sem concluir a troca**, bater
`/admin/` pela URL direta, e fazer o Bloco 7 (bateria transversal).

**Duas coisas de atenção especial no bloco 7:**

- **HTMX:** quase toda a navegação troca fragmento. Testar Voltar do navegador,
  F5 no meio de um fluxo, e conferir se o CSP não bloqueia nada no console.
- **Botão de ocultar valores:** no ControleRendaVariavel descobriu-se que ele
  borra o gráfico mas o HTML de origem continua carregando os valores exatos no
  atributo `data-values` (achado RV-15). **Verifique se o ControleBancario tem
  o mesmo furo — leia o HTML, não só a tela.** Se tiver, é achado transversal
  com correção única, e você precisa registrar isso.

Acrescente ao `RELATORIO_ControleBancario.md` a partir de `CB-16`. **Acrescente,
nunca reescreva.** Reescreva o `STATUS_CB.md` ao fim de cada bloco.

### 2. Aplicar três correções ao relatório do ControleBancario

O agente diagnosticou errado três achados. Os fatos abaixo foram verificados em
código e banco — **não precisam ser reverificados**, só aplicados ao relatório.
A fundamentação completa está na seção 0 do `CONCLUSOES_TRANSVERSAIS.md`.

**CB-07 — causa-raiz errada, risco real por outro motivo.**
O agente disse que o `<select id="deleteScopeSelect">` não tem `name` e por
isso a escolha de escopo nunca chega ao servidor, fazendo toda exclusão apagar
o grupo inteiro. Falso: o select não tem `name` de propósito; um
`<input type="hidden" name="operation_scope">` carrega o valor, espelhado por
um listener de `change` religado em `DOMContentLoaded`, `htmx:afterSwap` e
`htmx:load` (`static/js/transactions.js:69-125`, `templates/transactions/index.html:145`).
Para clique humano, funciona. O provável é que o agente tenha atribuído
`select.value` por automação sem disparar `change`.
**O que sobra e é defeito real:** `transactions/views.py:67` —
`return raw if raw in VALID_OPERATION_SCOPES else OPERATION_SCOPE_ALL`. Escopo
ausente ou inválido vira "apagar o grupo inteiro", em silêncio. Padrão de falha
invertido numa operação destrutiva sobre dado financeiro. Correção sugerida:
dar `name="operation_scope"` ao próprio select, eliminar o hidden e o
espelhamento, e inverter o padrão para o lado seguro.

**CB-15 — não é achado do produto; é erro do agente. Tirar da contagem.**
O agente registrou como Bloqueio o fato de a redefinição de senha ter atingido
a conta do mantenedor. Mas o botão tem confirmação que **nomeia o alvo**
(`templates/permissions/index.html:135`: "Redefinir a senha de {{ u.username }}?",
severidade `warning`). Ele clicou na linha errada e confirmou um diálogo que
dizia o nome da conta. Rebaixe para lição de método, severidade nenhuma.

**CB-14 — metade errada.**
`accounts/services.py:111` faz `has_function_permission` retornar `True`
imediatamente para `user_type == administrator`. Administrador não depende da
tabela de permissões, então "mspa tem menos permissões que Claudia" é leitura
errada da tela. A metade confirmada por consulta ao banco: `Claudia` é
`user_type = user`, depende da tabela, e tem `permissions.manage`,
`tables.users.manage`, `settings.database.optimize` e `settings.audit.view` —
o mesmo conjunto de `Admin`. Com `permissions.manage` ela pode conceder a si
mesma o resto. Freio real: `services.py:359` impede não-administrador de
alterar usuário privilegiado, então ela não alcança `mspa` nem `Admin`.
Rebaixe para Inconsistência de configuração da base real (decisão do
mantenedor), não defeito de código.

### 3. Fechar a análise transversal

Em `CONCLUSOES_TRANSVERSAIS.md`: atualizar a tabela do Panorama (seção 1) com
os números finais do ControleBancario, e fechar a seção **T7** com o resultado
da verificação do botão de ocultar valores.

Confira também se os sete padrões transversais continuam de pé com os achados
novos — e acrescente qualquer padrão que só apareça agora.

## Regras que não se quebram

**Regra de ouro dos dados.** Os bancos têm dado real do mantenedor, **sem
backup**: 714 lançamentos financeiros, 44 mil leituras de sensor, 3.046
concursos, uma carteira de investimentos de verdade. Você só cria, edita ou
exclui registros que **você mesmo criou**, sempre com o prefixo `ZZTESTE` no
nome ou descrição. Registro pré-existente é intocável: leia, filtre, ordene,
nunca altere. Confira o total de lançamentos antes e depois de cada bloco de
escrita. **A limpeza da rodada anterior já foi feita e conferida — os quatro
sistemas estão no baseline exato. Não deixe resíduo novo.**

**Autenticação.** O mantenedor faz o login; você herda o cookie de sessão.
**Você nunca digita senha em tela de login, nunca faz logout.** Se cair em
`/login`, pare, registre e peça ao mantenedor. Isso significa que teste de
autorização por papel (logar como operador) continua impossível — é a maior
lacuna conhecida da auditoria, e está registrada como tal.

**`optimize` do banco do ControleBancario: não rodar.** `health-check` pode.

**Nada de commit.** O mantenedor commita quando quiser. A pasta está como não
rastreada no repositório `manutencao` de propósito.

**Você observa e documenta. Você não conserta o produto.** Nenhuma alteração em
código, arquivos do repositório, contêineres, Docker ou banco por SQL. Seus
únicos arquivos de escrita são os relatórios e status desta pasta.

## Lições de método da rodada anterior — leia, economizam horas

**O que interrompe o trabalho é consumo de contexto, não o sistema testado.**
A rodada morreu cinco vezes por limite. O que resolveu: `get_page_text` com
`max_chars` apertado (1500–3000) como ferramenta padrão; `read_page` completo
só quando precisa de `ref_N` para clicar, e ainda assim com
`filter: "interactive"`; e **agrupar passos em `browser_batch`** — navegar,
preencher, submeter e ler devem ser uma chamada, não quatro. Filtre na tela
antes de ler qualquer listagem longa.

**Grave ao fim de cada bloco, nunca só no fim.** O relatório em disco é o que
sobrevive; sua memória de sessão não. Anote também notas de método para você
mesmo — foi isso que tornou cada retomada barata.

**Para escrever dado, use `form_input` e clique real via `computer`.** O
classificador de segurança do ambiente bloqueia escrita via `javascript_tool`.
Reserve `javascript_tool` para leitura e inspeção (ler `innerText`, `fetch`
GET, `checkValidity`) — e note que `get_page_text` só lê `<main>`, então toasts
e modais precisam ser lidos por JS.

**Cuidado com clique por coordenada em tabela com ação destrutiva por linha.**
Foi assim que o agente anterior redefiniu a senha do mantenedor por engano.
Antes de cada clique desses: screenshot fresco, confirmar pela coluna de nome
que a linha é a certa, e **ler o texto do diálogo de confirmação antes de
confirmar**. As confirmações desses sistemas nomeiam o alvo — use isso.

**Desconfie do que você mesmo conclui.** Dos quatro achados graves verificados
em código e banco pelo orquestrador anterior, **três tinham diagnóstico errado**
mesmo com o sintoma sendo real. Antes de subir um achado como Bloqueio, leia o
código ou consulte o banco. Um `grep` no template e uma consulta de chave
estrangeira resolveram dois casos em minutos.

**Detalhe de ambiente:** heredoc grande no Bash falha aqui — use a ferramenta
de escrita de arquivo. E no shell, cuidado com crases dentro de string entre
aspas duplas: são expandidas como comando.

## Entrega esperada

1. `RELATORIO_ControleBancario.md` completo, com as três correções aplicadas e
   os achados novos a partir de `CB-16`.
2. `CONCLUSOES_TRANSVERSAIS.md` fechado — panorama final e T7 resolvido.
3. `ANDAMENTO.md` atualizado dizendo que a rodada terminou, com qualquer
   resíduo que tenha sobrado e o caminho exato para removê-lo.
4. Um resumo ao mantenedor, em português: o que foi feito, os achados mais
   graves, o que não foi testado e por quê, e o que precisa da decisão dele.
