# Conclusões transversais — teste funcional pelo navegador

**Este arquivo é do orquestrador.** Os agentes não escrevem aqui. Ele reúne a
leitura dos quatro relatórios: o que é problema de um sistema só e o que é
padrão que atravessa a base compartilhada.

Estado: **aguardando os relatórios.** Esqueleto criado em 2026-08-31, logo após
o disparo dos quatro agentes, para que a análise sobreviva ao fim da sessão.

## Como preencher, quando os relatórios chegarem

1. Ler os quatro `RELATORIO_*.md` inteiros.
2. Separar cada achado em duas pilhas: **específico** (nasce de uma regra de
   negócio de um sistema só) e **transversal** (o mesmo sintoma aparece em dois
   ou mais, ou nasce de código que os quatro compartilham).
3. Para o transversal, dizer **onde mora a correção**: SharedAuth, o template
   base, a camada de formatação pt-BR, o `/health`, a CSP, ou a convenção que
   ainda não virou código.
4. Ordenar por custo × alcance. Uma correção na base compartilhada que resolve
   quatro sintomas vale mais que quatro correções locais.

## 0. Verificações do orquestrador

Achados que eu conferi por fora do navegador, para não levar à análise final
nada que o agente tenha diagnosticado errado.

### CB-07 — escopo de exclusão de parcelado/recorrente

O agente relatou Bloqueio: "excluir qualquer ocorrência apaga o grupo inteiro,
porque o `<select id="deleteScopeSelect">` não tem `name` e a escolha nunca é
enviada". **A causa-raiz está errada; o risco é real, mas por outro motivo.**

Lendo `templates/transactions/index.html:145-155` e
`static/js/transactions.js:69-125`, o desenho é:

- o `<select>` visível de propósito **não** tem `name`;
- quem carrega o valor é um `<input type="hidden" name="operation_scope">`;
- um listener de `change` no select espelha a escolha para esse hidden;
- o listener é religado em `DOMContentLoaded`, `htmx:afterSwap` e `htmx:load`
  (`transactions.js:225-262`), então sobrevive aos swaps do HTMX.

Ou seja: **para um usuário humano que clica no dropdown, a escolha é enviada.**
O mais provável é que o agente tenha atribuído `select.value` por automação sem
disparar `change`, deixando o hidden em `all` — artefato do método de teste, não
do produto. Isso precisa ser confirmado com um clique real antes de o achado
subir como Bloqueio.

**O que sobra, e é defeito de verdade:** `transactions/views.py:67`

    def _normalize_operation_scope(raw) -> str:
        return raw if raw in VALID_OPERATION_SCOPES else OPERATION_SCOPE_ALL

Escopo ausente, inválido ou corrompido vira **"apagar o grupo inteiro"**, em
silêncio. Numa operação destrutiva sobre dado financeiro, o padrão de falha
está invertido: deveria recusar a requisição, ou cair em `single`. Qualquer
coisa que impeça o `change` de disparar — erro de JS anterior na página, um
cliente que não execute o script, uma extensão — transforma "excluir esta
parcela" em "excluir as doze".

**Correção sugerida, e é pequena:** dar `name="operation_scope"` ao próprio
`<select>` e eliminar o hidden e o espelhamento. Campo dentro de container
oculto continua sendo submetido pelo navegador, então o caso "sem escopo"
(`supportsScope` falso) continua mandando `all` corretamente. Some o listener,
some a classe inteira de falha, e o valor passa a vir do campo que o usuário
enxerga. Em paralelo, inverter o padrão do `_normalize_operation_scope` para o
lado seguro.

### RV-16 — cadastros de teste que a interface não deixa excluir

O agente removeu 9 dos 12 registros `ZZTESTE` e ficou preso em três — ticker
`ZZTESTE4` (32), corretora `ZZTESTE Corretora` (7) e carteira `ZZTESTE Real`
(4) — barrado pela regra "cadastro em uso", sem que nenhuma tela mostrasse
vínculo algum. Ele suspeitou de "registro histórico invisível na UI" e acertou.

Consultei o banco. Das 19 chaves estrangeiras que apontam para `tickers`,
`brokers` e `portfolios`, **todas estão zeradas para esses três ids, exceto uma**:

    position_ledger_archive/ticker      4
    position_ledger_archive/broker      4
    position_ledger_archive/portfolio   4
    (todas as outras 16 origens: 0)

`position_ledger_archive` guarda o rastro de cada posição que existiu
(`source_position_id`, `resulting_signed_quantity`, `occurred_on`), e as três
FKs são `ON DELETE RESTRICT`. Excluir a posição **não** apaga o arquivo — o que
está correto para uma trilha histórica.

**O defeito não é o arquivo existir, é o beco sem saída.** Qualquer ticker,
corretora ou carteira que **um dia** teve posição fica impossível de excluir
para sempre, e a interface não dá pista alguma: diz "em uso", mas nenhuma tela
do produto mostra o que o está usando. O usuário fica olhando para listas
vazias sem entender por que a exclusão é recusada.

Não é problema só do dado de teste. Vale para uma corretora real que o
mantenedor deixe de usar, ou um ticker que ele nunca mais vá negociar.

**Correções possíveis, da mais barata à mais completa:**
1. A mensagem de recusa dizer **o que** está segurando ("4 registros de
   histórico de posição") em vez de um "em uso" genérico. Resolve a confusão,
   não o beco.
2. Oferecer **desativar/arquivar** o cadastro em vez de excluir — o histórico
   segue íntegro e o item some das listas de seleção.
3. Tornar o arquivo tolerante à perda do cadastro (desnormalizar o nome no
   próprio arquivo, ou `ON DELETE SET NULL` com o texto preservado), aí a
   exclusão passa a ser possível sem perder a trilha.

### CB-15 — NÃO é achado do produto. Erro do agente.

O agente registrou como Bloqueio o fato de a redefinição de senha ter atingido
a conta `mspa` em vez da conta de teste. **O produto agiu corretamente.** Em
`templates/permissions/index.html:135` o botão carrega confirmação que **nomeia
o alvo**:

    data-sa-confirmar="Redefinir a senha de {{ u.username }}? O sistema vai
    gerar uma senha temporária, mostrada uma única vez."
    data-sa-severidade="warning"

O agente clicou na linha errada **e confirmou um diálogo que dizia o nome da
conta do mantenedor**. Severidade correta: nenhuma — remover da contagem do
ControleBancario. Fica como lição de método: clique por coordenada em tabela
com uma ação destrutiva por linha exige reler o texto da confirmação antes de
confirmar, justamente porque a confirmação existe e diz o alvo.

Consequência operacional (resolvida pelo mantenedor, não é defeito): `mspa`
ficou com `must_change_password=t`, conta ativa e administradora.

### CB-14 — permissões de `Claudia`: metade errada, metade confirmada

O agente disse que `Claudia` "equivale a um administrador completo" e que
`mspa` teria menos permissões. **A segunda metade é leitura errada da tela:**
`accounts/services.py:111` faz `has_function_permission` retornar `True`
imediatamente para `user_type == administrator`. Administrador não depende da
tabela; as linhas de `mspa` são irrelevantes.

**A primeira metade se confirma por consulta ao banco.** `Claudia` é
`user_type = user` — depende inteiramente da tabela — e tem concedidas
`permissions.manage`, `tables.users.manage`, `settings.database.optimize` e
`settings.audit.view`: o mesmo conjunto da conta `Admin`.

Com `permissions.manage` ela pode conceder a si mesma qualquer permissão
restante, o que esvazia o significado do tipo `user`. **O freio existe e é
real:** `accounts/services.py:359` impede usuário não-administrador de alterar
usuário privilegiado, então ela não alcança `mspa` nem `Admin`.

Severidade: Inconsistência de configuração da base real, não defeito de código.
Decisão do mantenedor — conversa direto com o plano de padronizar multiusuário
e permissões.

## 1. Panorama

Rodada concluída: **63 achados na contagem consolidada** dos quatro sistemas. O
ControleBancario terminou os blocos 6 e 7 com dois achados novos (`CB-16` e
`CB-17`). `CB-15` é lição de método, não achado do produto, e está fora da
contagem.

| Sistema | Blocos | Achados | Blq | Def | Inc | Mel | Obs |
|---|---|---|---|---|---|---|---|
| MegaSena | 7/7 | 18 | 1 | 2 | 7 | 2 | 5 |
| ConfortoTermico | 8/8 | 13 | 2 | 6 | 3 | 0 | 2 |
| ControleRendaVariavel | 7/7 | 16 | 0 | 5 | 2 | 5 | 6 |
| ControleBancario | 7/7 | 16 | 2 | 8 | 5 | 1* | 1 |

\* A Melhoria do ControleBancario não recebeu número e, por isso, não entra
nos 16 achados válidos do sistema; a coluna a preserva como decisão pendente.

O ControleRendaVariavel não teve nenhum Bloqueio e é o mais maduro dos quatro:
as regras de domínio mais delicadas (preço médio ponderado, resultado
realizado, carteira simulada que não gera movimento e não deixa encerrar)
passaram todas. O ConfortoTermico é o mais frágil: dois bloqueios, e um deles
derruba o processo do servidor.

## 2. Achados transversais

Sete padrões aparecem em mais de um sistema. Estão em ordem de alcance × custo
de correção — os dois primeiros valem mais que qualquer correção pontual.

### T1 — O sistema corrige o valor do usuário em silêncio, em vez de recusar

O padrão mais difundido da rodada: entrada inválida não é rejeitada, é
**substituída** por outra coisa, sem aviso, e gravada.

| Sistema | Sintoma |
|---|---|
| ConfortoTermico | porta SMTP fora de faixa é gravada como 65535 (CT-08) |
| MegaSena | `generation_amount` negativo vira piso 1 (MS-16); campos numéricos aceitam texto e caem no padrão (MS-12) |
| ControleRendaVariavel | cotação aceita R$ 0,00 (RV-10); vírgula decimal rejeitada sem aviso (RV-07); datas futuras aceitas (RV-05) |
| ControleBancario | `min` do HTML preso ao valor atual impede reduzir a política (CB-13) |

**Por que importa:** o usuário digita um valor, o sistema diz "salvo", e o que
ficou gravado é outro. Não há como perceber sem reabrir e conferir. É pior que
um erro, porque um erro se vê.

**Onde mora a correção:** é convenção, não biblioteca. O contrato a
estabelecer, e a valer nos quatro: **fora de faixa, tipo errado ou formato
inválido devolvem erro com o campo destacado — nunca coerção silenciosa.**
Onde a coerção for deliberada (aparar espaço, aceitar vírgula ou ponto como
decimal), ela precisa ser explícita e informada. O caso da vírgula no
RendaVariável é o inverso dos outros: aceitar seria o certo, e ele recusa.

### T2 — Criar é fácil; desfazer não existe

Três sistemas deixam o usuário criar registros que depois não há como remover
pela interface. Esta rodada esbarrou nisso em todos os três, e a limpeza dos
dados de teste ficou incompleta **por limitação do produto**, não do método.

| Sistema | O que não se apaga |
|---|---|
| MegaSena | apostas salvas — só a rota `/reset`, que leva junto os 3.046 concursos reais (MS-14) |
| ControleRendaVariavel | ticker, corretora e carteira que um dia tiveram posição, presos por `position_ledger_archive` (RV-16) |
| ControleBancario | tags, projetos e orçamentos do Controle gerencial — sem tela nem endpoint |

**Por que importa:** todo cadastro errado vira permanente. Numa base de uso
pessoal e longo, isso acumula lixo que nunca sai.

**Onde mora a correção:** decidir uma política única para os quatro —
**arquivar/desativar em vez de excluir**, quando houver histórico a preservar,
com o item sumindo das listas de seleção. Onde a exclusão for possível, ela
precisa existir na tela. E a recusa precisa **dizer o que está segurando**: o
RV-16 recusa com um "em uso" genérico enquanto nenhuma tela do produto mostra o
que usa.

### T3 — Formatação pt-BR ficou pela metade

Quatro sistemas, e este é o achado que mais surpreende, porque a unificação de
formatação pt-BR consta como projeto **concluído**.

- MegaSena: contagens sem separador de milhar (MS-03); formato de data
  inconsistente **entre telas do mesmo sistema** (MS-18)
- ConfortoTermico: "Último login" em ISO cru (CT-11)
- ControleRendaVariavel: nomes de mês em inglês no histórico (RV-13);
  mensagem do Yahoo Finance repassada crua em inglês (RV-12)
- ControleBancario: mensagens de validação nativas do HTML5 em inglês (CB-04)

**Onde mora a correção:** a unificação anterior cobriu o que passa pelos
helpers de formatação. Escapou tudo o que **não passa por eles**: mensagem
nativa do navegador (que se resolve com validação própria, já que o atributo
`lang` não traduz), texto de terceiro repassado sem tradução, e telas que
formatam à mão. Vale uma varredura dirigida a esses três casos, não uma
reescrita.

### T4 — Gravou? Ninguém sabe

Não existe contrato de retorno depois de uma escrita, e isso varia **dentro do
mesmo sistema**.

- ConfortoTermico: "Salvar zona" falha 100% das vezes **sem nenhuma
  mensagem** — nem sucesso, nem erro (CT-07). É o pior caso da rodada.
- MegaSena: "Calcular parâmetros" devolve 500 em toda chamada (MS-10); e o
  mecanismo de notificação muda entre ações da **mesma tela** (MS-17)

**Onde mora a correção:** um único componente de aviso, já existente no
`sharedauth-ui.js` (`.sa-aviso`), aplicado de forma consistente. A regra a
firmar: **toda ação de escrita termina em confirmação visível ou erro
visível** — silêncio nunca é resposta aceitável.

### T5 — A trilha de auditoria não sabe quem fez

Dos dois sistemas que têm auditoria, os dois têm buraco no mesmo lugar: a
identidade de quem agiu.

- ConfortoTermico: o registro de login grava `login` e `perfil` como
  `"unknown"` **com o dado real disponível ao lado**, em `detalhes`. E não há
  nenhuma tela para revisar a trilha — ela só existe no log do contêiner
  (CT-12).
- ControleBancario: `cash_flow_entry` nunca registra o usuário em criação e
  exclusão, embora outras entidades registrem; a ação "marcar como realizado"
  **não aparece na trilha** (CB-05); a grade não exibe IP e não há eventos de
  tags, projetos ou orçamento do Controle gerencial (CB-16).

**Por que importa:** auditoria que não identifica autor não serve ao propósito
de auditoria. No sistema financeiro, com três titulares e permissões
compartilhadas, é justamente onde ela precisaria funcionar.

**Onde mora a correção:** o ControleBancario já tem o modelo certo — outras
entidades dele registram autor corretamente. É estender a cobertura e corrigir
o preenchimento, mais dar ao ConfortoTermico uma tela mínima de leitura.

### T6 — "Sem dado", "dado velho" e "zero" viram a mesma coisa

Os sistemas não distinguem ausência de informação de informação desatualizada,
e às vezes apresentam a segunda como se fosse atual.

- ConfortoTermico: o Dashboard mostra status **PERIGO** em vermelho a partir de
  uma leitura de **15 dias atrás**, sem qualquer indicação de que o dado é
  velho (CT-05). Num sistema de alerta de conforto animal, isso é grave: a tela
  afirma uma condição presente que não foi medida.
- ControleRendaVariavel: o pulso do coletor mostra horário 13 dias no passado
  sem dizer que o coletor está desligado (RV-02); e posição sem cotação vira
  três comportamentos diferentes, um deles afirmando "Nenhuma posição
  encontrada" — o que é falso (RV-14).

**Onde mora a correção:** convenção compartilhada de frescor — um limite de
idade por tipo de dado, e um estado visual próprio para "desatualizado" e para
"indisponível", distinto de zero.

### T7 — Privacidade de valores é cosmética

- ControleRendaVariavel: "Ocultar valores" borra o gráfico, mas o atributo
  `data-values` no HTML de origem carrega o patrimônio exato (RV-15).
- ControleBancario: confirmado o mesmo problema por um caminho ainda mais
  direto. O botão deixa os números exatos nos nós `data-sensitive-value` e
  apenas muda a cor computada para transparente; o texto continua íntegro no
  DOM (CB-17).

**Onde mora a correção:** ocultar tem de acontecer **antes** de o dado chegar
ao HTML, no servidor — não por CSS depois. Os dois sistemas precisam do mesmo
contrato de privacidade: persistir o modo privado de forma que a resposta não
renderize valores exatos, inclusive séries de gráficos. Se a intenção for só
evitar leitura por alguém olhando a tela, o produto deve declarar esse escopo;
como proteção contra vazamento pelo HTML, o comportamento atual não funciona.

## 3. Achados específicos, por sistema

Os que não se generalizam e valem por si.

### ConfortoTermico — o mais frágil dos quatro

- **CT-09 (Bloqueio):** exportar CSV grande **derruba o processo do servidor**
  (`RestartCount=3`, saída limpa, sem OOM). Funciona até ~14.400 medições,
  falha em 43.200. Não é exportação que falha: é serviço que cai para todos.
- **CT-07 (Bloqueio):** "Salvar zona" não cria zona nenhuma, em silêncio.
  Confirmado 3 vezes. O CRUD de usuário funciona, o que isola o defeito ao
  formulário de zona.
- **CT-03 (Defeito):** a rota `/api/zonas/<id>/consolidar-historico`, tratada
  como destrutiva no roteiro, **é acionada sozinha pela navegação comum**. Ou
  ela não é destrutiva e o nome engana, ou é, e está sendo disparada sem
  intenção. Precisa de decisão do mantenedor sobre qual das duas.
- **CT-02 (Defeito):** "Habilitar sons de alerta" é funcional, mas invisível
  por uma classe CSS `oculto` esquecida — recurso pronto que ninguém alcança.

### MegaSena

- **MS-11 (Defeito, o mais sério do sistema):** filtro contraditório não é
  detectado; a geração diz "sucesso" e devolve apostas que **violam o filtro
  pedido** (pediu no máximo 4 pares, saiu com 6). Falha silenciosa que entrega
  resultado errado com aparência de certo.
- **MS-10 (Bloqueio):** "Calcular parâmetros" — 500 em 100% das chamadas.
- Positivo confirmado: o fechamento matemático está correto, e `/rationale` é
  honesto — em nenhum momento promete vantagem probabilística.

### ControleRendaVariavel

- **RV-06 (Defeito):** deixa abrir posição de opção em contrato **já vencido**.
- Positivos que merecem registro: preço médio ponderado e resultado realizado
  conferidos na mão, corretos; e a regra da **carteira simulada** — a mais
  importante do sistema — passou nos três pontos, com o servidor bloqueando
  ativamente o encerramento.

### ControleBancario

- **CB-07:** ver seção 0. O diagnóstico do agente está errado; o risco residual
  (padrão de falha invertido no `_normalize_operation_scope`) é real.
- **CB-06 (Defeito):** parcelamento "Dividir valor" perde R$ 0,01 — 100,00 ÷ 3
  dá 33,33 × 3 = 99,99, sem ajuste da última parcela.
- **CB-12 (Inconsistência):** sinal de despesa invertido no Painel gerencial.
- **CB-10 (Defeito):** saldo de Projeções muda conforme o filtro Modo, para o
  mesmo mês.
- **CB-16 (Defeito):** trilha sem IP e sem cobertura de tags, projetos e
  orçamento.
- **CB-17 (Defeito):** ocultação conserva os números exatos no DOM.
- **CB-14:** ver seção 0 — configuração de permissões da base real, decisão do
  mantenedor.

## 4. O que não foi testado

A fronteira do que esta rodada pode afirmar. Importa tanto quanto os achados:
**silêncio aqui não é aprovação.**

**Por decisão de sessão emprestada** (nenhum agente digita senha), ficaram fora
nos quatro sistemas: login como usuário recém-criado, fluxo de troca de senha
obrigatória, comparação "senha atual × nova", e **autorização por papel** —
todo teste de "o operador consegue fazer o que só o admin deveria" ficou por
fazer. É a maior lacuna da rodada, e é estrutural: exigiria contas de teste com
senha conhecida.

**Por limitação da ferramenta:** todo upload de arquivo. Isso tirou a
importação de concursos por planilha (MegaSena), a importação de extrato e o
ciclo de comprovantes (ControleBancario).

**Por prudência com dado real:** o fechamento mensal do ControleBancario só foi
exercitado em mês seguro; `optimize` do banco não foi rodado; as rotas
destrutivas do ConfortoTermico foram documentadas, não acionadas.

## 5. Recomendação

Ordem sugerida. Nada aqui é implementado sem o aval do mantenedor.

**Primeiro, o que quebra ou mente:**

1. CT-09 — exportação que derruba o servidor.
2. CT-07 — "Salvar zona" silenciosamente inoperante.
3. MS-11 — geração que desrespeita o próprio filtro e diz que deu certo.
4. MS-10 — "Calcular parâmetros" em 500.
5. CB — inverter o padrão de falha do `_normalize_operation_scope` e dar
   `name` ao `<select>` de escopo. Correção pequena, elimina uma classe
   inteira de risco sobre dado financeiro.
6. CT-05 — status de alerta baseado em leitura de 15 dias sem aviso.

**Depois, os transversais, por ordem de alcance:**

7. T1 (coerção silenciosa) — convenção de validação para os quatro.
8. T4 (retorno de escrita) — usar o componente de aviso que já existe.
9. T2 (arquivar em vez de excluir) — política única.
10. T5 (autoria na auditoria) — estender o modelo que o Bancário já acerta.
11. T7 (privacidade no servidor) — confirmado no RendaVariavel e no Bancário;
    uma convenção/correção compartilhada atende os dois.
12. T3 (pt-BR nos três casos que escaparam) e T6 (convenção de frescor).

**E uma recomendação de método, não de código:** criar contas de teste com
senha conhecida em cada sistema, dedicadas a esse tipo de rodada. Foi a única
coisa que impediu de testar autorização por papel — que, num conjunto que
acabou de ganhar multiusuário e permissões, é justamente o que mais precisa de
teste.

## 6. Revalidação do plano geral após as correções do ControleBancario

O lote autorizado para o ControleBancario foi concluído e não ocupa mais a
fila de correções imediatas. A prioridade geral passa a ser:

1. CT-09, CT-07, MS-11 e MS-10, que ainda quebram fluxos ou apresentam sucesso
   falso nos outros sistemas;
2. CT-05, por apresentar estado baseado em dado defasado sem explicação;
3. expandir T1, T3 e T5 aos demais sistemas, reutilizando as convenções agora
   validadas no Bancário;
4. decidir produto/UX para T2 (arquivar ou oferecer remoção) antes de alterar
   modelos;
5. criar contas de teste com senha conhecida e executar autorização por papel,
   que continua sendo a principal lacuna transversal.

Efeito nos padrões transversais:

- **T1:** parcialmente mitigado no Bancário: escopo destrutivo inválido agora
  falha fechado com HTTP 400 e nomes duplicados são recusados também no banco.
- **T3:** os casos conhecidos do Bancário foram corrigidos para pt-BR.
- **T5:** o Bancário agora registra ator estável, timestamp com timezone, ação,
  entidade/id, IP de cliente, proxy confiável, request ID, sucesso/falha e
  resumo mínimo para lançamentos e fechamento mensal. O escopo não inclui
  tags, projetos ou orçamento por decisão explícita.
- **T7:** no Bancário deixa de ser tratado como fronteira de segurança. O
  requisito aceito é “Modo discreto” contra observação casual da tela; os
  gráficos ficam invisíveis e os valores visuais mascarados, enquanto o
  contrato documenta que os dados permanecem no DOM. Isso não resolve o caso
  do RendaVariavel nem serve como autorização/confidencialidade.

Os achados CB-01 a CB-08 e CB-10 a CB-13 foram corrigidos; CB-11 foi
reclassificado após investigação; CB-14 deixou de ser requisito relevante por
se tratar de dado de teste; CB-16 e CB-17 foram encerrados conforme o escopo
decidido. CB-09 e autorização por papel permanecem lacunas conhecidas.

## 7. Revalidação após as sete prioridades imediatas — 01/09/2026

As sete prioridades solicitadas foram implementadas e validadas:

1. CT-09 — exportação CSV em streaming e leitura em lotes;
2. CT-07 — salvamento de zona/equipamento sem modal de confirmação concorrente;
3. MS-11 — filtros inválidos/contraditórios recusados com HTTP 400;
4. MS-10 — cálculo de parâmetros sem erro 500;
5. CT-05 — leitura vencida explicitamente desatualizada;
6. RV-14 — posição sem cotação separada de totais e exibida com estado claro;
7. RV-05/RV-06/RV-10 — datas futuras, contrato vencido e cotação zero recusados
   segundo o significado de cada evento.

O ControleBancario também foi revalidado junto do lote. Resultado combinado:
Ruff aprovado nos quatro projetos; 223 testes no ConfortoTermico, 115 no
MegaSena, 239 no ControleBancario e 192 no ControleRendaVariavel — **769 testes
aprovados**. As quatro pilhas operacionais foram reconstruídas e ficaram
saudáveis. O smoke não autenticado confirmou os quatro redirecionamentos para
login; a sessão autenticada não estava disponível no navegador interno nesta
revalidação.

### Nova ordem recomendada

1. Criar contas de teste estáveis por papel e executar a matriz de autorização
   no servidor — continua sendo a maior lacuna de segurança.
2. Revalidar os fluxos autenticados destas sete correções no navegador e cobrir
   uploads de concursos, extratos e comprovantes.
3. Expandir autoria/contexto de auditoria (T5) ao ConfortoTermico, MegaSena e
   RendaVariavel, começando por CT-12.
4. Completar a política transversal de recusa explícita (T1) nos formulários
   que ainda fazem coerção silenciosa fora deste lote.
5. Uniformizar os formatos pt-BR remanescentes (T3) e indicadores de foco.
6. Decidir a política de arquivamento/exclusão (T2), incluindo MS-14 e RV-16,
   antes de alterar modelos ou apagar históricos.
7. Tratar o modo discreto do RendaVariavel (T7) conforme a intenção já definida:
   proteção apenas contra observação casual, com contrato e implementação
   coerentes.

As prioridades de quebra, sucesso falso e dado enganoso estão encerradas. A
fila seguinte concentra validação de autorização, cobertura de uploads,
auditoria transversal e consistência de produto.

## 8. Execução das decisões de produto — retomada em 01/09/2026

O mantenedor aprovou as recomendações de produto e autorizou a implementação
completa, preservando a decisão anterior de não configurar ou validar a conta
de teste `Claudia`. A implementação local ficou assim:

1. **Acesso por papel:** continua como lacuna explícita. A configuração da
   conta de teste deixou de ser requisito; a matriz completa depende de contas
   estáveis, com credenciais conhecidas, e de login manual do mantenedor.
2. **Falha fechada em operações financeiras:** o ControleBancario já recusa
   escopo ausente ou inválido com HTTP 400 e mantém as defesas de servidor.
3. **Modo discreto:** RendaVariavel e ControleBancario assumem explicitamente
   o objetivo de evitar leitura casual da tela. No RendaVariavel, números são
   mascarados e os canvases dos gráficos são ocultos; não é uma promessa de
   confidencialidade contra inspeção do HTML.
4. **Eventos auditáveis:** o escopo decidido para lançamentos e fechamento
   mensal permanece no Bancário. MegaSena ganhou uma trilha persistente para
   apostas, importações, configurações, gestão de contas e senhas. O
   ConfortoTermico passou a registrar e expor a revisão administrativa de
   cadastros, configurações, limpeza de histórico e atualização de agregados,
   sempre com ator e contexto mínimo, sem segredos.
5. **Ciclo de vida dos cadastros:** MegaSena permite excluir aposta salva sem
   apagar concursos; RendaVariavel exclui referência sem uso ou a arquiva se
   tiver histórico, com reativação; ControleBancario exclui tag, projeto ou
   orçamento sem dependência e arquiva o item que preserva histórico.
6. **Histórico e frescor:** no ConfortoTermico, a ação agora atualiza somente
   agregados pendentes, sem apagar leituras brutas. O limite de frescor é
   configurável por zona entre dois e três ciclos, com padrão de três.

### Validação final desta retomada

| Sistema | Verificação | Resultado |
|---|---|---|
| ControleRendaVariavel | Quality Docker, migração aplicada e fluxo autenticado | Ruff e 195 testes aprovados; health saudável; modo discreto conferido no navegador |
| ControleBancario | Quality Docker e bootstrap PostgreSQL isolado | lint e 243 testes aprovados; migrate e collectstatic concluídos |
| MegaSena | Quality Docker e ciclo de migração em PostgreSQL isolado | Ruff e 115 testes aprovados; upgrade, downgrade e novo upgrade aprovados |
| ConfortoTermico | Quality Docker e bootstrap PostgreSQL isolado | Ruff e 225 testes aprovados; pilha saudável e `verificar_postgres` aprovado |

Total desta validação: **778 testes aprovados**, além dos lint, health checks e
bootstraps documentados acima. Não foi feito backup do RendaVariavel, por
decisão expressa do mantenedor e com aceitação do risco; as demais validações
de banco usaram somente ambientes temporários já removidos. A próxima etapa
autorizada é commitar localmente, publicar os ramos e atualizar o VPS a partir
de `main`.
