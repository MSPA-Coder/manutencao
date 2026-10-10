# Auditoria de filtros perdidos e recargas desnecessárias — CB e CRV

Plano para aprovação, 09/10/2026. Coordenação: Opus. Execução dos testes:
subagentes Haiku 5.5. Ordem: ControleBancario (CB) e, depois,
ControleRendaVariavel (CRV).

## Decisões já tomadas

| Tema | Decisão |
|---|---|
| Escopo | Ciclo completo: levantamento → aprovação → correção → reteste local → portão final → PR → deploy |
| Quem corrige | Opus escreve; Haiku retesta e faz a regressão |
| Filtro preservado | Depois de qualquer operação, a **mesma tela volta com os mesmos filtros**, e F5, voltar e favorito também os mantêm. Fica na URL, como no contrato atual (nada em sessão ou banco, abas independentes) |
| Paralelismo | Três executores por sistema, cada um com aba própria e território exclusivo, mais uma fila serial para as operações globais. O banco é salvo antes e restaurado depois |

### Decisões tomadas durante a rodada

- **09/10, contexto que acompanha o menu (CB):** titular, instituição e conta
  passam a ser **contexto global**, como moeda e grupos.
  - Viajam na URL entre as telas que usam o mesmo seletor (`selected_context`):
    Lançamentos, Dashboard, Projeções, Próximos movimentos, Posição por conta e
    Gerencial.
  - Aparecem na faixa "Mostrando só…", com um botão para limpar.
  - Período e status **não** viajam, porque cada tela tem o seu.
  - Nada é gravado, e cada aba continua independente.
  - Telas com seletor próprio (Planejamento anual, Reclassificação,
    Fechamento) ficam de fora, salvo decisão em contrário.
- **09/10, banco do CB:** restaurar `cb_base.dump` quando o A4 terminar.

## O que já se vê no código (hipóteses para testar, não conclusões)

- **CRV:** cerca de 60 `redirect(url_for(...))` depois de POST voltam para a
  URL sem parâmetros, por exemplo em `app/routes/dividends.py:263` e
  `app/routes/options.py:315`. O sistema tem só 2 `hx-push-url`, então o
  filtro aplicado por HTMX não chega à URL e o redirect não tem de onde
  recuperá-lo.
- **CB:** o `tbody` de Lançamentos (`templates/transactions/_table_body.html:50`)
  recarrega a tabela por `tableRefresh` com a URL **congelada na
  renderização** (`request.GET.urlencode`). Se o fragmento veio de um POST, a
  URL vem vazia ou velha, o que é perda de filtro e também fonte de corrida.
- **CB:** `_monthly_close_redirect` (`core/views.py:496`) preserva só os
  filtros da própria lista. `HX-Redirect` em `transactions/views.py:553` e
  `banking/views.py:328` faz navegação cheia. Há uns 25 redirects nas views.
- **Os dois contêineres locais estão atrás do `main`:** o web do CB foi criado
  em 07/10 e o do CRV em 05/10, mas os dois têm commits de 08/10. Testar sem
  reconstruir mediria código velho.

## Definições que todos os agentes usam

Cada caso de teste recebe **um** código. Quando há mais de um, vale o mais
grave.

| Código | Significado | Como se mede |
|---|---|---|
| **R** | Recarga cheia desnecessária | O marcador `window.__sonda` sumiu depois da operação (o documento foi recarregado) |
| **M** | Troca de região grande demais | O HTMX trocou `#appMain` ou a página inteira quando bastava a linha ou a tabela (alvo registrado pela sonda) |
| **F** | Filtro perdido | O estado de filtro depois ≠ o estado antes (URL + controles de filtro), e a operação não justificava a mudança |
| **P** | Filtro parcialmente perdido | Só parte voltou, por exemplo a moeda global ficou e o filtro da coluna sumiu |
| **U** | URL dessincronizada | A tela mostra o filtro, mas a URL não o tem, de modo que F5 ou voltar perde |
| **S** | Contexto de uso perdido | Rolagem, foco, linha ou seção expandida, aba interna |
| **C** | Corrida | O resultado muda conforme a ordem ou o tempo das requisições (resposta velha sobrescreve nova, duplicidade, aba alheia afetada) |
| **OK** | Nada a apontar | — |

**Sonda** (`sonda.js`, escrita na Fase 0): um trecho só de leitura que o
agente injeta antes da operação com `javascript_tool`. Ela grava o marcador,
fotografa a URL e todos os controles de filtro (forms GET,
`[data-table-filter]`, `hx-include`, moeda e grupos), a rolagem e o foco.
Também escuta `htmx:beforeRequest`, `htmx:afterSwap` e `htmx:oobAfterSwap`
para registrar método, URL, alvo, `swap` e os cabeçalhos `HX-Redirect`,
`HX-Refresh`, `HX-Trigger` e `HX-Push-Url` da resposta. Depois da operação,
uma segunda chamada devolve o diff em JSON compacto. Escrita de dados nunca
passa por JS: só clique real e `form_input`.

## Fase 0 — Preparação (Opus, sem Haiku)

1. **Reconstruir** os dois sistemas locais em `main` com `--build` e conferir
   o commit servido.
2. **Snapshot** com `pg_dump -Fc` dos dois bancos locais, guardado fora dos
   repositórios. Restaurar no fim da Fase 1 e antes da regressão da Fase 3.
3. **Inventário estático** por script Python que varre URLs e rotas, templates
   e JS e gera duas matrizes:
   - `tela × controle de filtro` (cada filtro de cada tela, global ou local);
   - `operação × origem × resposta` (cada POST, `hx-post` ou `hx-delete`, de
     cada tela que o oferece, e o que o servidor devolve: redirect com ou sem
     query, fragmento, `HX-Redirect`, `HX-Refresh`, `HX-Trigger`, reload em
     JS).

   É essa lista que define "todas as opções", e a cobertura passa a ser
   medida: toda linha tem de ser visitada por alguém.
4. **Territórios** para os três executores, com base nos dados locais:
   - CB: contas e meses disjuntos por agente (o fechamento é por conta).
   - CRV: carteiras, corretoras e tickers disjuntos.

   Tudo o que um agente cria leva o prefixo `[AUD-A1]`, `[AUD-A2]` ou
   `[AUD-A3]` na descrição.
5. **Fila serial** para o que afeta outros territórios: categorias, bancos,
   instituições, titulares, permissões, preferências e modo discreto,
   importação de extrato, configurações e tabelas do CRV. Ela roda só depois
   que os três paralelos terminam.
6. **Lotes:** cada agente recebe `LOTE_<id>.md` com as linhas do inventário,
   o protocolo e o território, e escreve só os próprios arquivos
   (`STATUS_<id>.md` e `ACHADOS_<id>.csv`).

**Saída:** o sistema serve o commit do `main`, há snapshot, o inventário está
gerado e os lotes estão fechados.

## Fase 1 — Levantamento adversarial (CB inteiro, depois CRV inteiro)

O mesmo desenho roda uma vez por sistema.

### Rodada A — executores (3 Haiku em paralelo, depois 1 Haiku na fila serial)

Protocolo de cada linha do lote:

1. Abrir a tela de origem com **filtros fora do padrão**: no mínimo dois
   filtros locais, mais moeda e grupos diferentes do padrão, e a página rolada.
2. Injetar a sonda.
3. Executar a operação por clique real.
4. Ler o diff da sonda e registrar código, evidência e passos.
5. Desfazer o que for desfazível, como excluir o que criou ou reabrir o mês.

Variações obrigatórias de cada operação:

- sucesso, erro de validação e cancelar (o formulário inválido costuma perder
  o filtro ao ser renderizado de novo);
- edição inline e modal, quando existirem as duas;
- cada tela de origem que oferece a mesma operação;
- depois da operação, F5 e voltar.

Navegar pelo menu para **outra** tela não precisa preservar os filtros locais,
só moeda e grupos.

### Rodada B — adversários (2 Haiku em paralelo, territórios novos)

- **Reproduzir às cegas** cada achado da rodada A numa aba nova. O adversário
  recebe só os passos, não o diagnóstico, e responde se reproduz ou não.
- **Caçar falso negativo:** refazer uma amostra de 20% das linhas OK, sorteada
  por mim.
- **Ataques de corrida:**
  - duplo clique em Salvar;
  - trocar o filtro e operar antes de a resposta chegar;
  - duas operações em sequência rápida;
  - a mesma tela em duas abas com filtros diferentes, operando numa e
    conferindo que a outra não mudou (e o inverso);
  - operar enquanto um `tableRefresh` está pendente;
  - voltar no meio de uma requisição.

### Rodada C — consolidação (Opus)

- Um achado só entra no relatório se **B reproduziu e eu confirmei a causa no
  código** (arquivo e linha). Na rodada de 31/08, três de quatro diagnósticos
  de agente estavam errados.
- Os achados são agrupados por **causa raiz** (padrão), não por tela. Uma
  correção de padrão resolve dezenas de telas.
- Sai `RELATORIO_<sistema>.md` com a matriz de cobertura, os achados
  confirmados e a correção proposta para cada padrão.
- O snapshot é restaurado.

**Portão 1 — sua aprovação:** quais padrões corrigir e qualquer decisão de
produto que apareça, por exemplo uma tela em que a recarga cheia seja
justificável.

## Fase 2 — Correção e reteste local

- Uma branch por repositório (`fix/filtros-e-recargas`). Commit por marco
  testado, sem push até o Portão 2.
- A correção é **por padrão**, com um único ponto por sistema:
  - POST que volta para a tela carrega a query **atual** (`hx-include` do
    formulário vivo ou parâmetro `volta`), e o servidor a valida: só caminho
    relativo da própria aplicação (`url_has_allowed_host_and_scheme` no
    Django, verificação equivalente no Flask), para não abrir redirect aberto;
  - operação HTMX responde com fragmento mais `HX-Trigger`, sem
    redirect nem refresh, quando a tela já está aberta;
  - filtros aplicados por HTMX levam `hx-push-url` (CRV), para F5, voltar e
    favorito funcionarem;
  - nada de URL congelada na renderização: a recarga lê o estado no momento da
    requisição, o que também fecha a corrida do `tbody`.
- **Testes automatizados novos**, no nível que prova o contrato:
  - test client verificando que o `Location` e os cabeçalhos HX preservam a
    query;
  - um teste-guarda que percorre todas as rotas de escrita, para que um
    endpoint novo que esqueça o filtro quebre a suíte.

  Sem asserção de texto literal.
- **Reteste local:** o loop rápido roda no venv. Um Haiku refaz no navegador
  só as linhas dos achados e as vizinhas.

## Fase 3 — Portão final antes do deploy

1. Reconstruir com `--build` e restaurar o snapshot, para a regressão partir
   de uma base conhecida.
2. Rodar o `quality` completo (ruff e pytest) nos dois repositórios, mais o
   `manage.py check` do CB.
3. **Regressão completa no navegador:** o inventário inteiro de novo (três
   executores mais a fila serial) e a rodada de corrida do adversário. A meta
   é zero R, F, U e C nas linhas aprovadas, zero erro de console, nenhum 4xx
   ou 5xx inesperado e nenhuma violação de CSP (o HTMX já tropeçou nisso em
   20/08).
4. Rodar `/code-review high` no diff, com atenção a redirect aberto e CSRF.
5. Para cada repositório: PR, CI verde (CB com `Qualidade` e `CodeQL`; CRV com
   `Qualidade`, `Contratos de runtime` e `CodeQL`) e squash merge.
6. **Portão 2 — deploy:** com o CI do `main` verde, entrego os comandos
   `~/deploy.sh`. O classificador nega o ssh de deploy, e cada deploy precisa
   da sua autorização.
7. Fazer só a conferência de leitura no VPS: abrir as telas com filtros. Nada
   de escrita sobre dado real.

## Achados laterais (fora do escopo de filtros e recargas)

Pedido do mantenedor em 09/10: um defeito encontrado de passagem **não fica só
como observação**. Cada um vira uma tarefa `L<nn>` para um Haiku, com estas
regras:

- o Haiku trabalha só com código, Git e o banco local em leitura, sem
  navegador, para não disputar com os executores;
- não altera o repositório;
- entrega `status/LATERAL_L<nn>.md` com veredito (defeito, intencional ou
  indeterminado), evidência, caminhos afetados e uma proposta de correção e de
  teste.

Eu confiro cada veredito. O que for defeito entra na Fase 2 junto com o resto e
passa pelos mesmos portões.

| Id | Sistema | Sintoma | Estado |
|---|---|---|---|
| L01 | CB | Desfazer a realização de um lançamento com vencimento futuro grava `vencidos` | **defeito confirmado pelo coordenador**. `transactions/services.py:335` grava `STATUS_PENDING` sem olhar a data. A listagem (`reports/services.py:1251`) só mostra `vencidos` com vencimento no passado, então o lançamento **some de "A vencer" e de "Vencidos"** e só aparece em "Todos". O mesmo acontece ao desfazer conciliação ou importação (`bank_statements/reconciliation.py:612`). Correção: `_normalize_open_entry_status`, mais os textos do diálogo e um teste de visão. Vai para a Fase 2 |
| L03 | CRV | Carteira Simulada não aparece no seletor de carteira de Performance e Exposição | **Exclusão intencional** (`performance.py:58`, `positions.py:892`, `models.py:307`; desde a versão inicial). Defeito de **comunicação**: com `portfolio_id=3` a tela mostra "Todas" e lista vazia, sem dizer por quê. A doc de "Todas" (`planilha-acoes.md:444`) diverge do código. Com a Simulada excluída (ver L06), sobra só o ajuste da doc, com prioridade baixa |
| L06 | CRV | A Simulada tem 10 movimentos `OPEN`, contra a regra "simulada não gera movimento" | **Dado legado**: uma reconstrução em lote em 12/08, anterior ao repositório. O fluxo atual não cria esses movimentos. **Brecha de código confirmada**: o detalhe `/positions/<id>` mostra os movimentos, e editar ou excluir movimento (`positions.py:714` e `:763`) não verifica `simulated`. A regra está no `AGENTS.md:178`. Correção: extrato vazio e recusa de edição para simulada. **Resolvido em produção em 09/10, 16:50 UTC, a pedido do mantenedor ("deletar todos os dados da carteira simulada, inclusive a própria carteira").** Foi usado o script `excluir_simulada.py`: ensaio no local, ensaio na produção, dump fresco no VPS (`~/backups/manual/crv_antes_excluir_simulada_20261009_165006.dump`, sha256 `0da7bbdf…`) e só então `--executar`. Saíram 10 posições, 10 movimentos, 10 associações de ticker e a carteira. Conferido no banco: nenhuma carteira simulada, nenhum movimento órfão, auditoria registrada, app 200. A brecha de código (editar movimento de simulada) continua na correção do CRV, com prioridade baixa: não há mais carteira simulada |
| L04 | CRV | Clique em "Risco" no menu Análise abriria "Alocação por Ativo" (C3, 2×). Os links estão certos no código (`base.html:92`). Suspeita: sobreposição visual dos cartões do menu | **descartado**: o coordenador clicou no cartão "Risco" (1366 px) e caiu em `/risk`. `elementFromPoint` no centro de cada um dos 5 cartões devolve o próprio link, sem sobreposição. Foi erro de clique do agente |
| L05 | CRV | O seletor de nova posição de opção oferece contrato vencido, e o servidor recusa ao salvar | **defeito confirmado pelo coordenador**. `_contracts()` (`app/routes/options.py:150`) não filtra por data. A criação recusa contrato vencido (`:189`), e a regra está em `docs/planilha-opcoes.md:74`. Correção: na criação, oferecer só `exercise_date >= hoje`; na edição, manter também o contrato atual. Teste de conteúdo do seletor. Hipótese a verificar na correção: a edição deixaria mover uma posição viva para um contrato vencido |
| L07 | CRV | Editar contrato de opção "não salva e não avisa" | **Indeterminado, provável erro de leitura do agente**: toda saída da rota gera mensagem (toast de 6 s). Reproduzir na regressão da Fase 3 |
| L08 | CRV | `/quotes?benchmark_ticker_id=…` responde 404 | **Defeito confirmado pelo coordenador** (`app/routes/quotes.py:108`). Um benchmark escolhido que sai da lista de candidatos gera `abort(404)`. Isso acontece quando ele é igual ao ticker principal e também quando o **filtro de moeda** o exclui. No HTMX o 404 não troca a tela, então ela fica parada sem mensagem. Correção: tratar como "Nenhum", sem 404, e teste. Entra na correção do CRV |
| L09 | CRV | Duplo clique em "Confirmar" de novo provento devolve **500** (BCK K1) | **Corrida confirmada pelo coordenador, pelo traceback**. O segundo POST bate na restrição única `import_key` (titular, ticker, corretora, tipo, data, valor), e `create_dividend` (`app/routes/dividends.py:258`) não trata o `IntegrityError`. O banco segura a duplicata, mas a pessoa vê erro 500. Correção: tratar como "já cadastrado", com rollback e mensagem, mais um teste de duplo POST. A trava de envio único no cliente (SharedAuth) evita o segundo envio |
| L02 | CB | Compra no cartão gravada sem descrição; transferência criada duas vezes ("duas tentativas") | Conferido pelo coordenador. **Descrição vazia: intencional até hoje** (`description` com `blank=True` desde a V2.0, `transactions/models.py:150`). Fica como **pergunta de produto** para o Portão 1: tornar obrigatória, ou só rotular como "Opcional". **Duplicidade: defeito**, o mesmo do CB-10. O servidor não tem idempotência, e o aviso de "movimentos semelhantes" (`transactions/views.py:309`) só aparece depois de gravar. Correção: trava no cliente e `submit_token` no servidor, junto com o CB-10 |

## Corrida — os três riscos e o controle de cada um

| Onde | Controle |
|---|---|
| **Entre agentes** (um banco e um navegador para todos) | Cada agente fixa o próprio `tabId` e nunca usa a aba da frente. Os territórios são disjuntos e as operações globais ficam na fila serial. Tudo o que é criado leva o prefixo `[AUD-xx]`. Há um arquivo de estado por agente, e só eu consolido. Eu não mexo no navegador enquanto os agentes rodam |
| **Na aplicação** | A bateria de ataques da rodada B é repetida na Fase 3. As correções não podem criar URL congelada nem uma segunda requisição de acerto (`application.js:515` registra que isso já foi corrida uma vez) |
| **Entre código e teste** | Reconstrução com `--build` antes de cada rodada de navegador, conferindo o commit servido |

## Como os Haiku trabalham (vai no prompt de cada um)

- Usam `browser_batch` para encadear navegar, sonda, operar e ler. Leem com
  `get_page_text` e `max_chars` baixo. Screenshot só como evidência de achado,
  em escala 0,5.
- Regravam `STATUS_<id>.md` **ao fim de cada tela**, com a linha atual, os
  achados e o que falta desfazer, para retomar barato se a sessão cair.
- Não corrigem nada nem tiram conclusão sobre valores, porque os dados locais
  são de teste. Também não entram em nenhuma tela fora do lote.
- Se uma operação não puder ser desfeita, param e registram. A restauração do
  snapshot resolve no fim.
- **O CRV local tem dados reais**, uma cópia da produção de 09/10/2026 06:00
  trazida do BackupRestore. Os agentes não transcrevem valores, quantidades nem
  nomes de ativo em `STATUS`, `ACHADOS` ou relatório. Evidência é estrutural:
  URL, nome do filtro, alvo do swap, cabeçalho HX. A restauração entre rodadas
  usa `crv_base.dump`, que é essa cópia.

## Estrutura

```
_manutencao/AUDITORIA_FILTROS_REFRESH/   (não versionado até o fim)
  PLANO.md          este arquivo
  sonda.js          instrumentação só de leitura
  inventario/       matrizes geradas na Fase 0 (CB e CRV)
  lotes/            LOTE_<id>.md
  status/           STATUS_<id>.md e ACHADOS_<id>.csv, um por agente
  RELATORIO_CB.md   RELATORIO_CRV.md
```

## Restauração derruba o login

As sessões do CB ficam no banco (`django_session`). Restaurar um snapshot
**desconecta todo mundo**, e foi assim que, em 09/10, os três adversários caíram
no login. Depois de qualquer restauração, pedir ao mantenedor que entre de novo
**antes** de soltar agentes. O CRV guarda a sessão em cookie assinado, mas a
marca de sessão depende do hash da senha, que também vem no dump.

## Limites conhecidos

- O navegador embutido não simula rede lenta. A corrida é provocada por
  sequência rápida e por duas abas, não por atraso artificial.
- O relatório de cada Haiku é matéria-prima: o achado só vale depois de
  reproduzido e confirmado no código.
- Os dados locais são de teste e servem para forma e comportamento, nunca para
  conclusões sobre valores.
