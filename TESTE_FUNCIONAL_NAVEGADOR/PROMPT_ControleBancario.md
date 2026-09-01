# Prompt do agente — ControleBancario (sigla CB)

Alvo: `http://127.0.0.1:5201`. Relatório: `RELATORIO_ControleBancario.md`.
Ler `README.md` deste diretório antes de começar: o contrato de execução vale
integralmente e não se repete aqui.

Único Django dos quatro (os outros são Flask). Controle bancário e fluxo de
caixa **em uso real pelo mantenedor**: há 714 lançamentos, 10 contas, 3
titulares e 21 categorias de verdade no banco local. É o sistema onde a regra
de ouro pesa mais — dado financeiro real não se mexe.

Sessão emprestada: `mspa`, tipo `administrator`, com 30 permissões funcionais e
acesso a 2 titulares. **`mspa` não é `is_staff`** — o item de menu
"Administração" (`/admin/`) deve ser negado a ele. Esse é um bom caso de teste
de autorização: tentar `/admin/` pela URL direta e registrar a resposta.

## Bloco 1 — Varredura do menu

Estrutura completa da barra lateral, com submenus:

- **Dashboard** — `/dashboard/`
- **Movimentação**
  - Lançamentos — `/transactions/`
  - Lançamentos n+1 — `/operations/`
  - **Banking**
    - Importação de extrato — `/banking/imports/`
    - Conciliação — `/banking/reconciliation/`
    - Comprovantes — `/banking/attachments/`
    - Fechamento mensal — `/settings/monthly-close/`
- **Relatórios**
  - Próximos movimentos — `/reports/upcoming-movements/`
  - Projeções — `/reports/projections/`
  - Posição por conta — `/reports/account-position/`
  - Planejamento anual — `/reports/annual-planning/`
  - Controle gerencial — `/management/`
- **Cadastros**
  - Titulares — `/tables/owners/`
  - Instituições — `/tables/banks/`
  - Contas — `/tables/accounts/`
  - Categorias — `/tables/categories/`
- **Configurações**
  - Perfil e tema — `/settings/profile/`
  - Contas em análises — `/settings/account-visibility/`
  - Parâmetros — `/settings/`
  - Banco de dados — `/settings/database/`
- **Segurança**
  - Alterar senha — `/change-password/`
  - Permissões — `/permissions/`
  - Trilha de auditoria — `/settings/audit-log/`
- **Administração** — `/admin/` (só `is_staff`)

Abrir todos, confirmar carga, rótulo coerente, marcação do item ativo e
comportamento de abrir/fechar dos submenus. Registrar divergências.

## Bloco 2 — Cadastros (inclusão, alteração, exclusão)

Ciclo completo, sempre com registro próprio prefixado `ZZTESTE`:

1. **Titular** `ZZTESTE Titular`: criar, editar, excluir.
2. **Instituição** `ZZTESTE Banco`: criar, editar, excluir.
3. **Conta** `ZZTESTE Conta`, vinculada ao titular e à instituição de teste:
   criar com saldo inicial, editar, e **tentar excluir com lançamento
   vinculado** (depois do bloco 3) — deve barrar ou explicar.
4. **Categoria** `ZZTESTE Categoria`: criar, editar, excluir.

Em cada um, antes de gravar o válido: enviar em branco, com nome duplicado do
próprio registro de teste, com texto no limite do campo e além dele, com valor
negativo onde não cabe. Registrar cada validação ausente.

**Nunca editar nem excluir os 3 titulares, 10 contas e 21 categorias reais.**

## Bloco 3 — Lançamentos (o núcleo)

Todos os lançamentos criados vão para a conta `ZZTESTE Conta` e a categoria
`ZZTESTE Categoria`, com descrição começando em `ZZTESTE`.

- **Lançamento simples:** criar receita e despesa, editar valor e data,
  marcar como realizado (`mark_realized`), desmarcar se possível, excluir.
- **Lançamento parcelado:** criar com 3 parcelas. Conferir se gera 3 registros,
  se as datas avançam mês a mês, se o valor total fecha com a soma das
  parcelas (incluindo o arredondamento do último centavo), e o que a exclusão
  de uma parcela faz com as demais.
- **Lançamento recorrente:** criar, conferir a projeção, rodar
  `/settings/recurring-projection/run/` **somente se a tela deixar limitar ao
  registro de teste** — se for global, não rodar e registrar o motivo.
- **Transferência interna:** exige duas contas — criar `ZZTESTE Conta 2` para
  isso. Conferir se gera o par débito/crédito, se o saldo dos dois lados fecha
  e se a exclusão de uma perna leva a outra.
- **Lançamentos n+1** (`/operations/`): entender o que a tela faz, exercitar
  com registro de teste e descrever o contrato observado.
- Filtros da listagem: por período, conta, categoria, titular, tipo, situação.
  Combinar dois filtros. Conferir se os cartões de resumo batem com a soma da
  tabela filtrada — **fazer a conta**.
- Datas: 29/02 em ano não bissexto, data no passado distante, data no futuro
  distante, campo vazio.
- Valores: zero, negativo, com centavos, muito grande, com vírgula e com ponto
  como separador decimal.

Apagar todos os `ZZTESTE` ao fim do bloco e conferir que os 714 lançamentos
reais continuam intactos (conferir o total antes e depois).

## Bloco 4 — Banking

- **Importação de extrato:** montar arquivo de extrato pequeno e sintético,
  todos os lançamentos marcados `ZZTESTE`, contra a `ZZTESTE Conta`. Conferir
  a tela de status do lote, o que acontece com arquivo malformado, com formato
  não suportado e com arquivo vazio. Conferir se a reimportação do mesmo
  arquivo duplica ou detecta.
- **Conciliação:** conciliar linha do extrato de teste com o lançamento de
  teste; usar "criar lançamento" a partir da linha; testar conciliação em lote
  e o desfazer; testar "ignorar" linha. Conferir que nada disso encosta em
  linha ou lançamento real.
- **Comprovantes:** anexar um arquivo pequeno a um lançamento `ZZTESTE`,
  baixar de volta, conferir o nome e o tipo. Testar arquivo grande demais e
  tipo não permitido. **Conferir se o download de comprovante de outro usuário
  é barrado** — tentar pela URL direta com id vizinho.
- **Fechamento mensal:** este é sensível. Fechar e reabrir mês **altera dado
  real**. Preferir um mês **sem nenhum lançamento real** (procurar um mês vazio
  no acervo, ou usar um mês futuro distante). Fechar, conferir o efeito na
  edição de lançamentos daquele mês, e **reabrir em seguida**, registrando o
  estado antes e depois. Se não existir mês seguro, **não fechar nada**:
  descrever a tela e registrar o teste como não executado, com o motivo.

## Bloco 5 — Relatórios

Com 714 lançamentos reais, os relatórios têm massa. São só leitura — explorar à
vontade.

- **Próximos movimentos:** horizonte, agrupamento, o que entra e o que não.
- **Projeções:** conferir se a projeção parte do saldo atual e se a soma
  projetada bate com a lista que a sustenta.
- **Posição por conta:** somar os saldos exibidos e comparar com o total.
- **Planejamento anual:** tela analítica por titular; trocar de titular e de
  ano, incluir ano sem dado, conferir o contrato de contexto documentado em
  `ControleBancario/docs/annual-planning-report.md` — **ler esse documento** e
  comparar com o que a tela entrega.
- **Controle gerencial** (`/management/`): tags, projetos, orçamentos,
  atribuição de tag e de projeto. Criar tag e projeto `ZZTESTE`, atribuir a um
  lançamento de teste, conferir o reflexo no relatório, e apagar.
- Em todos: exportação, se houver; formato de número e data; comportamento com
  filtro que não retorna nada.

## Bloco 6 — Configurações e Segurança

- **Perfil e tema:** trocar tema, conferir persistência; rolagem de tabela.
- **Contas em análises**: tirar e repor uma conta, conferir o efeito nos
  relatórios. **Restaurar o estado original.**
- **Parâmetros** (`/settings/`): política de senha e bloqueio por tentativa.
  **Anotar todos os valores originais antes de mexer e restaurá-los ao final.**
  Testar mínimo abaixo do piso de 8, valor não numérico, valor absurdo. Não
  testar o bloqueio na prática — exigiria errar senha de propósito e travaria a
  conta do mantenedor.
- **Banco de dados** (`/settings/database/`): rodar o `health-check`. **Não
  rodar o `optimize`** sem necessidade — registrar que existe, o que promete e
  se avisa do custo.
- **Permissões** (`/permissions/`): é a tela de multiusuário. Conferir a
  matriz de permissões, o que `mspa` tem, o que `Claudia` e `Esther` têm.
  **Não alterar permissão de conta real.** Criar `ZZTESTE-cb`, conceder e
  revogar permissões nele, conferir o botão **Redefinir senha** (senha
  temporária mostrada uma vez só; conferir que **não** vaza por mensagem flash,
  HTML subsequente ou URL — a sessão do Django é assinada, não cifrada), e
  excluir ao final.
- **Trilha de auditoria** (`/settings/audit-log/`): conferir se **tudo o que
  este agente fez nesta rodada** apareceu na trilha, com usuário, IP, data e
  ação. O que não apareceu é achado. Conferir o IP registrado: deve ser o do
  cliente, não o gateway do Docker.
- **Alterar senha** (`/change-password/`): abrir, conferir validação, **sem
  concluir a troca**.
- **`/admin/` pela URL direta:** `mspa` não é staff. Registrar a resposta
  exata (403? redirecionamento? tela de login do admin?).

## Bloco 7 — Bateria transversal

Conforme a seção "Bateria transversal" do `README.md`. Aqui, atenção especial a
**HTMX**: quase toda a navegação troca fragmento. Conferir Voltar do navegador,
F5 no meio de um fluxo, e se o CSP não bloqueia nada no console — houve
correção de CSP do HTMX em 20/08 e vale confirmar que continua limpa.
