# Consolidação CB (em andamento)

Um achado só entra aqui com o sintoma medido por um executor **e** a causa
conferida no código pelo coordenador. A reprodução pelo adversário (rodada B)
vem depois.

## Confirmados

| # | Código | Sintoma | Causa (arquivo:linha) | Fonte |
|---|---|---|---|---|
| CB-01 | R | Toda escrita em Lançamentos recarrega a página inteira: editar, novo (simples, parcelado, recorrente, transferência), realizar e desfazer. Os filtros da tela voltam. | `realizeForm` e os formulários de edição e criação são POST comuns; o ramo 204 + `tableRefresh` só roda quando `quer_fragmento`, o que não acontece nesses envios | A1 1.1–1.4, 1.2p, 1.2r; medido também pelo coordenador |
| CB-02 | P | Em Lançamentos, escolher um filtro de coluna apaga os outros filtros de coluna (categoria apaga tipo) | `templates/transactions/_table_body.html:19,25,31`: cada select tem `hx-include="#contextForm"` e não inclui os irmãos `[data-table-filter]` | A1 1.F |
| CB-03 | F | "Voltar" do Novo lançamento zera todos os filtros de contexto | `templates/transactions/index.html:90`: `href` sem query. O mesmo vale para `:106` ("limpar filtro" ou "Voltar para Operações") e `operations.html:42` | A1 1.2 cancelar |
| CB-04 | M | Cada filtro de tela (Lançamentos, Operações, Dashboard, Próximos movimentos, Projeções, Fechamento) troca `#appMain` inteiro, mais o cabeçalho e os avisos | Desenho atual (`docs/architecture.md`: filtros de página trocam `#appMain`). Avaliar se vale trocar só a região de resultados | A1 1.F, 2.F, 3.F, 4.F, 5.F; A3 1.F |

| CB-05 | R | Toda escrita no Gerencial recarrega a página inteira: criar tag ou projeto, salvar orçamento, vincular, arquivar. Os 4 filtros voltam | `management/views.py:20` `_redirect_to_panel` preserva a query (`redirect_qs` ou `QUERY_STRING`), mas os formulários são POST comuns | A2 1.1–1.7 |
| CB-06 | **F** | A prévia da Reclassificação mostra a lista filtrada, mas a URL fica sem os filtros, e F5 reenviaria o POST. **Reproduzido pelo B1 (R006):** a moeda global cai de ALL para BRL na prévia, porque a moeda é lida da query do request e o POST vai para a URL sem query | `bank_statements/views.py:317`: a prévia é renderizada na resposta do POST para `templates/banking/reclassificacao.html:26` (sem query). Os filtros viajam no campo `voltar`. Depois de aplicar, volta com a query (OK) | A2 3.1 |

| CB-07 | R+F | Tabelas cadastrais (contas, bancos, categorias, grupos, titulares): criar, editar ou excluir recarrega a página e **perde o filtro da tabela** (`filter_owner_id`, `filter_institution_id`, `filter_type`). É a hipótese H-CB1 | `banking/views.py:325` `_respond`: `redirect(nome)` ou `HX-Redirect` para `reverse(nome)` sem query. O mesmo padrão em `transactions/views.py:553` (categorias e grupos) e `accounts/views.py` (titulares) | A4 1.1–4.3 |
| CB-08 | R | Configurações, perfil (tema, rolagem) e verificação de saúde: salvar recarrega a página. Essas telas não têm filtro, então o custo é só a recarga | `core/views.py` com `redirect('core:...')` | A4 5.x, 6.x, 8.1. **Prioridade baixa** |

| CB-10 | C | **Envio duplo:** dois cliques rápidos em "Confirmar exclusão" geram 2 POSTs (os dois respondem 200), e duas confirmações seguidas criam 2 lançamentos iguais. Risco de **duplicar dados** | `static/js/core/application.js:168`: a trava `data-submitting` só existe para `[data-global-currency-form]`. Os formulários POST de escrita (criar, excluir, realizar) não têm trava, e o modal da SharedAuth (`sharedauth-ui.js`, `confirmar`) também não trava o reenvio. A correção pode morar na SharedAuth e valer para a frota | B2 K1 |

## A conferir

- **A1 1.5x** "voltar depois de excluir" zera os filtros: pode ser o histórico apontando para a entrada anterior ao filtro. Reproduzir.
- **A1 1.X2** "Ver operação" leva à tela da operação sem os filtros: navegação para outra tela; por decisão, só moeda e grupos precisam ir junto. Verificar o caminho de volta.
- **A1 1.F** Dashboard→Lançamentos pelo menu perde titular, instituição e conta: é outra tela e, pela decisão, isso não precisa ser preservado. **Pergunta de produto** para o Portão 1: o contexto de titular e conta deveria acompanhar o menu como a moeda acompanha?
- **A1 4.F e 5.F**: os drilldowns de Próximos movimentos e Projeções não levam o intervalo de datas e meses (levam só o mês). Avaliar.
- **A1 1.1** "o formulário de edição reabre depois de salvar": reproduzir (pode ser S ou estado restaurado de propósito).
- **A1 1.2t** transferência "recusada com confirmação visual": a mensagem só existe na edição com escopo `current_future` (`_fields.html:131`). Provável confusão do agente. **Reproduzir na rodada B**: criar uma transferência entre contas próprias e editar com "Este registro e os próximos".
- **A3**: recarga cheia no painel global e no período da conta (GET comum). Desenho ou desperdício?
- **A3**: `currency=BRL` sumindo da URL é o valor padrão. **Não é perda.**
- **A2**: "voltar" deixa a URL sem moeda e grupos, mas as caixas continuam marcadas (7×, em telas de banking). Pode ser o navegador restaurando o formulário pelo cache de página (bfcache), e não o app. Reproduzir: se a tela também mostra os dados sem o filtro, é incoerência real.
- **A2**: Posição por conta e Gestão perdem titular e instituição pelo menu. É a mesma **pergunta de produto** do A1 sobre o contexto acompanhar o menu.
- **A2 9.F**: voltar perdeu só a instituição na Posição por conta. Reproduzir.
- **CB-09: "voltar" sai da tela em vez de desfazer o último filtro.** Fontes: A2 1.F e 9.F; A4 1.F, 7.F, 8.F e 9.F.
  - **Mecânica:** os filtros declaram `hx-push-url="true"` (`core/templatetags/navegacao.py:61`), mas o middleware `core/navegacao.py:78` responde com `HX-Replace-Url`, que prevalece. O efeito real é *replace*: uma entrada de histórico por tela.
  - **O CRV faz o mesmo de propósito**, e documenta o motivo em `app/templates/index.html:2`: com *push*, ajustar três filtros exigiria três cliques em "voltar" para sair da tela.
  - **Conclusão:** o comportamento do CB é igual ao desenho deliberado do CRV. O defeito é só a **contradição** entre o que o CB declara (*push*) e o que acontece (*replace*).
  - **Pergunta de produto para o Portão 1, com recomendação:** manter o *replace* nos dois sistemas (o "voltar" sai da tela, F5 e favorito continuam valendo) e trocar o `nav_filtro` do CB para `hx-replace-url`, eliminando a contradição sem mudar o comportamento. A alternativa é o *push* (o "voltar" desfaz filtro a filtro) nos dois sistemas.
  - Com o *replace*, os casos "voltar perdeu o filtro" deixam de ser achado e passam a ser **comportamento de projeto**.
- **B2 K3** (dois filtros de coluna em sequência rápida: o tipo some): **não é corrida.** É o CB-02, porque o select de categoria não inclui o de tipo, com ou sem pressa.
- **B2 K1 "Realizar"**: o "Confirmar" do modal não enviava, e "Cancelar" não fechava. **Suspeita de erro do agente:** no teste do coordenador, o Realizar abre um **segundo** diálogo ("Confirmar realização"), que fica por cima e intercepta os cliques. Reproduzir pessoalmente quando o navegador estiver livre.
- **Permissões** (A4 9.1): o classificador de segurança negou o `javascript_tool` nessa tela, e o agente não contornou, que era o certo. A gravação de permissão fica **sem teste no navegador**. Cobrir por teste automatizado na Fase 2: o POST de permissão volta com `user_id`.

## Reproduções da rodada B (às cegas)

- **B1:** 14 de 61 casos, interrompido por volume.
  - **CB-07** reproduzido: criar categoria derruba `filter_type` (R016).
  - **CB-06** reproduzido e agravado (R006).
  - **CB-04** (M) reproduzido (R004 e R007).
- **Incidente do B1:** um `ref` errado abriu a exclusão da categoria **real** "Viagem". O agente cancelou e nada foi excluído. Lição para a Fase 3: **antes de confirmar uma exclusão, ler o texto do diálogo e conferir o nome `[AUD-…]`**. Vai para o protocolo.

- **B3:**
  - **K6** reproduz o CB-02: trocar um filtro de coluna remove o outro.
  - **K4** (duas abas): sem vazamento entre abas. O contrato "filtro só na URL" se sustenta.
  - **K2** (C, prioridade baixa): trocar o filtro com o diálogo Realizar aberto faz o envio não sair. A troca de `#appMain` descarta o formulário referenciado pelo diálogo. Cenário raro.
  - **G2:** a edição "Este registro e os próximos" pede confirmação e grava; a exclusão "Todos do grupo" funciona.
  - **G1:** descrição vazia gravada, e a transferência foi criada 2× por "duas tentativas". Abertas como **L02**.
  - **G4:** não concluído (seleção múltipla).

## Descartados

- **B3 G3: "moeda e grupos voltam ao padrão pelo menu."** Erro de método: o agente usou `navigate` para o `href`. A propagação ocorre no **clique** do link (`static/js/core/application.js:176`). O coordenador clicou no link "Lançamentos" a partir do Dashboard com `currency=USD&grupos=…` e os dois chegaram. Isso coincide com o A3.

- **"URL perde `grupos` com 4 de 5 grupos marcados"** (B1 R010 e R011; casos U de "voltar" do A2): é o padrão. Grupos padrão = todos menos Administradas, e o padrão não vai para a URL (`static/js/core/application.js:125`, `data-default-value`).

- "Filtro global persistido na sessão do navegador" (A3): falso. O CB não guarda moeda nem grupos no navegador nem na sessão; `sessionStorage` guarda só a rolagem e `localStorage` só o modo discreto.

## Laterais

- **L01**: defeito confirmado (ver `PLANO.md`).

## Lacunas que sobraram depois da rodada B (cobrir na regressão da Fase 3)

- **B2 não fez:**
  - K2 e K6 (dependiam do Realizar);
  - K4 (duas abas);
  - G1 a G4 (compra no cartão, transferência com escopo, filtros globais em todas as telas, seleção múltipla).
- Na Fase 3, com as correções no lugar, um executor dedicado faz esses itens.

## Lacunas de cobertura para a rodada B

- A3 não criou nem excluiu a compra no cartão 20.
- O G.* cobriu 6 telas.
- A1 não alcançou os drilldowns por clique: conferiu pelo `href`.
- A2 não testou a seleção múltipla do Planejamento anual: `form_input` com lista falhou. Tentar marcar por clique em cada opção.
- A2 deixou sem testar conciliação, gravar a reclassificação e atualizar saldo. **Passados ao A4**, que roda sozinho.
- **Resíduo do A2**: tag e projeto `[AUD-A2]` ficaram arquivados, vinculados aos movimentos 616 e 639, porque a tela não oferece desvincular. Restam também um orçamento sem prefixo (Outros, 09/2026), que o A4 deve retirar. A restauração de `cb_base.dump` no fim da Fase 1 limpa tudo.
