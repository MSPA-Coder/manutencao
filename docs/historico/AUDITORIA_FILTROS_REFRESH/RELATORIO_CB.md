# Relatório CB: filtros perdidos e recargas desnecessárias

09/10/2026. Base: 32 telas, 71 operações e 98 controles de filtro (inventário
estático), medidos no navegador por 4 executores (A1 a A4b, 257 linhas) e
contestados por 4 adversários (B1, B1b, B2 e B3).

**Como os resultados de A foram contestados:** os adversários B1 e B1b
reproduziram às cegas 77 casos (todos os achados mais uma amostra de 20% dos OK).
- 49 achados foram reproduzidos.
- 13 OK foram confirmados.
- 8 não se reproduziram e foram descartados.
- 4 falsos negativos de A apareceram, mas sem causa nova.

Todo achado abaixo tem a **causa conferida no código**.

## Os padrões (causa raiz) e a correção proposta

Os achados se agrupam em 8 padrões. A correção é **por padrão**, com um ponto
único no código, e não tela por tela.

### P1. Escrita por POST comum causa recarga cheia
**Sintoma:** toda operação recarrega a página inteira. Os filtros da tela
voltam, mas a tela pisca e perde rolagem e foco.

**Onde acontece:**
- Lançamentos: criar, editar, realizar, desfazer e excluir (CB-01);
- Gerencial (CB-05);
- tabelas cadastrais (CB-07);
- Fechamento de mês;
- Configurações (CB-08).

**Causa:** os formulários são `<form method="post">` comuns, seguidos de
`redirect`. Em Lançamentos já existe o ramo HTMX (204 + `tableRefresh`), mas os
formulários não o usam.

**Correção:** as escritas das telas com lista passam a ser `hx-post`, e o servidor
devolve só a região que muda, mais um `HX-Trigger` para quem precisa se atualizar.
O POST comum continua como alternativa sem JavaScript, com redirect que leva a
query. A ordem é Lançamentos, tabelas, Gerencial e Fechamento.

### P2. A volta perde a query
**Sintoma:** depois da operação ou do "Voltar", a tela volta sem filtro nenhum.

**Onde acontece:**
- tabelas cadastrais perdem `filter_owner_id`, `filter_institution_id` e
  `filter_type` (CB-07);
- os links "Voltar", "Voltar para Operações" e "limpar filtro" (CB-03);
- a prévia da Reclassificação perde os filtros e **troca a moeda de ALL para
  BRL** (CB-06).

**Causas:**
- `banking/views.py:325` `_respond` → `redirect(nome)` ou `HX-Redirect` sem
  query, e o mesmo em `transactions/views.py:553` e `accounts/views.py`;
- `templates/transactions/index.html:90 e :106` e `operations.html:42`;
- a prévia da Reclassificação é um POST para a URL sem query
  (`bank_statements/views.py:317`).

**Correção:**
- um ajudante único para "voltar para a tela com os filtros atuais";
- a tela manda a query viva num campo `volta`, e o servidor só aceita caminho
  relativo da própria aplicação, para não abrir redirecionamento externo;
- os links "Voltar" ganham uma template tag que monta o `href` com os filtros da
  tela;
- a prévia da Reclassificação passa a manter a query na URL.

### P3. Moeda e grupos não entram na lista de parâmetros preservados
**Sintoma esperado** (o código confirma; nos testes a moeda estava no padrão):
quem trabalha em Dólar ou com grupos marcados volta para BRL e para os grupos
padrão depois de realizar, editar ou criar um lançamento.

**Causa:** `TRANSACTIONS_QUERY_PARAMS` (`transactions/services.py:2016`) não
inclui `currency` nem `grupos`.

**Correção:** o ajudante do P2 sempre leva os parâmetros globais.

### P4. Um filtro de coluna apaga o outro
**Sintoma:** em Lançamentos, escolher a categoria apaga o filtro de tipo, e
vice-versa (CB-02; reproduzido por B1b e B3).

**Causa:** em `templates/transactions/_table_body.html:19, 25 e 31`, cada select
tem `hx-include="#contextForm"` e não inclui os outros filtros de coluna.

**Correção:** `hx-include="#contextForm, [data-table-filter]"`. É a menor
correção da lista.

### P5. Cada filtro troca `#appMain` inteiro
**Sintoma:** em toda tela com filtro, a troca leva também o cabeçalho e os
avisos. Para quem usa, parece um "refresh" (CB-04, em 9 telas).

**Causa:** é o desenho atual, `nav_filtro` com `hx-target="#appMain"`.

**Correção proposta** (ver decisão D1): nas telas com tabela, trocar só a região
de resultados. O resto da tela não muda.

### P6. Envio duplo
**Sintoma:** dois cliques rápidos criam dois lançamentos ou mandam a exclusão
duas vezes. Uma "segunda tentativa" criou uma transferência repetida (CB-10 e
L02).

**Causas:**
- a trava `data-submitting` só vale para o formulário de moeda
  (`static/js/core/application.js:168`);
- o modal da SharedAuth não impede o reenvio;
- o servidor não tem idempotência, e o aviso de "movimentos semelhantes"
  (`transactions/views.py:309`) só aparece depois de gravar.

**Correção:**
- trava de reenvio para todo formulário POST, colocada na SharedAuth para valer
  nos três sistemas;
- no CB, `submit_token` de uso único na criação de lançamento e de
  transferência.

### P7. O contexto não acompanha o menu
**Decisão já tomada:** titular, instituição e conta passam a ser contexto global,
como moeda e grupos. Período e status não viajam.

**Onde mexer:** a propagação já existe para moeda e grupos
(`application.js:176`, no clique dos links). Ela passa a incluir os três
parâmetros nas telas que usam `selected_context`, mais a faixa "Mostrando só…"
com um botão para limpar.

### P8. Histórico: o código declara uma coisa e faz outra
**Sintoma:** o "voltar" do navegador sai da tela em vez de desfazer o último
filtro (CB-09).

**Causa:** `nav_filtro` declara `hx-push-url`, mas o middleware
`core/navegacao.py:78` responde com `HX-Replace-Url`, que prevalece. O efeito
real (uma entrada de histórico por tela) é o mesmo que o **CRV adota de
propósito** (`app/templates/index.html:2`).

**Correção** (ver decisão D2): declarar `hx-replace-url` e eliminar a
contradição, sem mudar o comportamento.

## Laterais

- **L01, defeito:** desfazer a realização de um lançamento com vencimento futuro
  grava `vencidos`, e o lançamento **some de "A vencer" e de "Vencidos"**. O
  mesmo acontece ao desfazer conciliação ou importação. Correção: usar
  `_normalize_open_entry_status`, ajustar o texto do diálogo e criar um teste de
  visão.
- **L02:**
  - a duplicidade é o P6;
  - a descrição vazia é aceita desde a V2.0 (`blank=True`); ver a decisão D3.
- **K2, prioridade baixa:** trocar o filtro com o diálogo Realizar aberto faz o
  envio não sair. A correção é fechar o diálogo quando `#appMain` é trocado.

## Comportamento esperado (não é defeito)

- **Grupos padrão fora da URL:** "todos menos Administradas" não aparece na URL
  (`application.js:125`).
- **`currency=BRL` sumindo da URL:** BRL é o padrão.
- **Painel de filtros globais e período da conta:** recarregam por GET comum.
  Isso troca a página inteira por desenho; o filtro global vale para a tela toda.
- **Drilldowns de Projeções e Próximos movimentos:** levam o mês, não o intervalo.
  O destino (Lançamentos) trabalha por mês.

## Sem teste no navegador: cobrir por teste automatizado na Fase 2

- Gravar permissão: o classificador de segurança negou a ferramenta, e o agente
  não contornou.
- Conciliação, porque não havia linhas pendentes no território.
- Upload de extrato e de anexo, porque o navegador embutido não faz upload.
- Seleção múltipla do Planejamento anual.

## Portão 1: decidido em 09/10/2026

- **D1:** trocar só a região de resultados em **Lançamentos e nas tabelas
  cadastrais**.
- **D2:** *replace*. O voltar sai da tela, e o `nav_filtro` passa a declarar
  isso.
- **D3:** descrição **obrigatória** no formulário manual (criar e editar). Os
  lançamentos importados não mudam.
- **D4:** Configurações e perfil ficam fora desta rodada.
- **D5:** trava de reenvio na **SharedAuth** (nova versão, atualizada em CB,
  CRV e MegaSena), mais o `submit_token` no CB.
- **Ordem:** o levantamento do CRV roda **em paralelo** com a correção do CB.

## Decisões para você (Portão 1)

| | Pergunta | Recomendação |
|---|---|---|
| **D1** | Trocar só a região de resultados ao filtrar (P5)? | **Sim** em Lançamentos e nas tabelas cadastrais, onde a queixa de "refresh" pesa mais. Nas demais telas, só se sobrar tempo |
| **D2** | Histórico ao filtrar (P8): "voltar" sai da tela ou desfaz filtro a filtro? | **Sai da tela** (*replace*), como o CRV já faz. É só tornar oficial |
| **D3** | Descrição do lançamento obrigatória? | **Obrigatória** no formulário manual. A sugestão de conciliação compara descrições, e uma linha sem descrição fica cega para ela. Lançamentos importados não mudam |
| **D4** | Configurações e perfil (P1, sem filtro): deixar de recarregar? | **Não agora.** Ganho pequeno; fica fora desta rodada |
| **D5** | Trava de envio duplo na SharedAuth (vale para CB, CRV e MegaSena) ou só no CB? | **Na SharedAuth.** É uma correção para a frota, mas exige nova versão da biblioteca e atualização nos apps |
