# Andamento — teste funcional pelo navegador

**Rodada concluída.** Este arquivo registra o encerramento e os limites da
auditoria.

Última atualização: **2026-08-31, 14:40** — quatro sistemas concluídos,
relatórios e análise transversal fechados. **Limpeza executada e conferida.**
Nada em execução e nenhum resíduo de teste em nenhum dos quatro sistemas.

## Situação em uma linha

Quatro sistemas concluídos. **63 achados na contagem consolidada.** Os quatro
sistemas estão íntegros: nenhum dado real foi perdido em nenhum momento.

| Sistema | Porta | Blocos | Achados | Resíduo |
|---|---|---|---|---|
| MegaSena | 5101 | **7/7 concluído** | 18 | limpo |
| ConfortoTermico | 5001 | **8/8 concluído** | 13 | limpo |
| ControleRendaVariavel | 5301 | **7/7 concluído** | 16 | limpo |
| ControleBancario | 5201 | **7/7 concluído** | 16 | limpo |

## Entrega final

- `RELATORIO_ControleBancario.md`: Blocos 1–7 concluídos; `CB-16` e `CB-17`
  acrescentados; `CB-07`, `CB-14` e `CB-15` corrigidos.
- `CONCLUSOES_TRANSVERSAIS.md`: panorama final atualizado e T7 confirmado nos
  dois sistemas que têm ocultação de valores.
- `STATUS_CB.md`: estado final, sem credencial temporária e sem trabalho
  pendente.
- Lacunas conhecidas permanecem documentadas: autorização por papel exige
  login em conta comum; uploads não puderam ser exercitados; ações destrutivas
  globais foram deliberadamente evitadas.

## Correções aplicadas ao relatório do ControleBancario

As três revisões verificadas por código e banco foram aplicadas. Fundamentação
completa em `CONCLUSOES_TRANSVERSAIS.md`, seção 0.

- **CB-07** — a causa-raiz descrita está **errada**. O `<select>` sem `name` é
  proposital; um `<input type="hidden" name="operation_scope">` carrega o valor,
  espelhado por um listener de `change` religado em `DOMContentLoaded`,
  `htmx:afterSwap` e `htmx:load`. Para clique humano, funciona. O que **sobra e
  é real**: `transactions/views.py:67` faz escopo ausente ou inválido virar
  "apagar o grupo inteiro", em silêncio — padrão de falha invertido numa
  operação destrutiva sobre dado financeiro.
- **CB-15** — **não é achado do produto; é erro do agente.** O botão de
  redefinir senha tem confirmação que **nomeia o alvo**
  (`permissions/index.html:135`). O agente clicou na linha errada e confirmou
  um diálogo que dizia o nome da conta do mantenedor. Rebaixar para lição de
  método, fora da contagem. A credencial temporária antiga foi removida do
  arquivo de estado.
- **CB-14** — metade errada. `accounts/services.py:111` faz administrador
  ignorar a tabela de permissões, então as linhas de `mspa` são irrelevantes.
  A metade **confirmada por consulta ao banco**: `Claudia` é `user_type = user`,
  depende da tabela, e tem `permissions.manage`, `tables.users.manage`,
  `settings.database.optimize` e `settings.audit.view` — o conjunto de `Admin`.
  Freio real: `services.py:359` impede não-administrador de alterar usuário
  privilegiado, então ela não alcança `mspa` nem `Admin`.

Dois achados saíram da retomada final:

- **CB-16:** trilha de auditoria sem IP e sem eventos de tags, projetos e
  orçamento do Controle gerencial.
- **CB-17:** “Ocultar valores” só deixa o texto transparente; os números exatos
  permanecem no DOM, confirmando o padrão transversal T7 com RV-15.

## Limpeza — EXECUTADA E CONFERIDA (31/08, 13:40)

O mantenedor autorizou; executei por SQL, um comando por vez, conferindo o
alvo antes e o baseline depois. **Os quatro sistemas voltaram ao estado
anterior à rodada.**

| Sistema | Removido | Baseline conferido depois |
|---|---|---|
| MegaSena | 5 apostas (ids 53-57) + usuário `ZZTESTE-ms` | 0 apostas, 3.046 concursos, 2 usuários |
| ControleRendaVariavel | 4 linhas de `position_ledger_archive` (ids 3-6), ticker 32, carteira 4, corretora 7 | 21 posições, 19 transações, 100 proventos, 31 tickers, 5 corretoras, 3 carteiras |
| ControleBancario | fechamento da conta 12, orçamento, conta 12, titular 6, instituição 9, categoria 22, tag, projeto, 31 permissões e o usuário `ZZTESTE-cb` | 714 lançamentos, 3 titulares, 10 contas, 21 categorias, 4 usuários |
| ConfortoTermico | nada a fazer | 5 zonas, 44.642 leituras, 2 usuários |

Nenhum registro real foi tocado em nenhum dos quatro. Zero `ZZTESTE` restante.

Duas observações que saíram da própria limpeza:

- **O resíduo "permanente" do Painel gerencial não era permanente no banco.**
  Tag, projeto e orçamento saíram com um `DELETE` simples, sem nenhuma
  dependência. Ou seja: o T2 (criar é fácil, desfazer não existe) é **falta de
  tela**, não restrição do modelo de dados. Isso barateia muito a correção.
- **As cotações do RendaVariavel subiram de 7.329 para 7.524.** Não é resíduo:
  é dado real de mercado que o agente atualizou pelo Yahoo Finance para tickers
  do mantenedor, ao exercitar a importação. Fica.

## Incidente da rodada (resolvido)

Durante o bloco 6 do ControleBancario, um clique por coordenada acertou a linha
errada da tabela de Permissões e redefiniu a senha da conta `mspa`, derrubando
a sessão. **O mantenedor já entrou com a senha temporária e definiu a nova**
(`must_change_password` de volta a `f`, verificado no banco). Nenhum dado
financeiro afetado. O produto agiu corretamente — ver CB-15 acima.

## O que esta rodada aprendeu sobre o método

Vale para qualquer rodada futura deste tipo:

- **O que interrompe os agentes é consumo de contexto, não o sistema testado.**
  `read_page` completo e uma chamada por passo esgotam o orçamento antes do
  bloco 3. `get_page_text` com `max_chars` apertado e `browser_batch` agrupando
  passos foi o que levou os agentes ao fim.
- **Cookies de sessão sobrevivem ao fechamento do painel do navegador.** Não é
  preciso pedir login novo a cada retomada.
- **Para escrever dado, `form_input` e clique real.** O classificador de
  segurança do ambiente bloqueia escrita via `javascript_tool`.
- **Gravar `STATUS_<sigla>.md` ao fim de cada bloco foi o que salvou a rodada.**
  Sobrevivemos a cinco interrupções por limite. As notas de método que cada
  agente escreveu para si mesmo tornaram cada retomada barata.
- **Um agente por arquivo de estado.** Quatro agentes editando o mesmo arquivo
  se atropelariam.
- **Conferir os achados dos agentes por fora.** Dos quatro que verifiquei em
  código e banco, **três estavam parcial ou totalmente errados** no
  diagnóstico — mesmo quando o sintoma observado era real.

## Decisões desta rodada

1. Autenticação: o mantenedor faz os logins; os agentes herdam a sessão.
   Nenhum agente digita senha em tela de login. **Consequência:** autorização
   por papel ficou sem teste nos quatro sistemas — a maior lacuna da rodada.
2. Alvo: somente local, em Docker. Nada tocou o VPS.
3. Sem backup prévio — a regra de ouro dos dados foi a única proteção, e
   funcionou: nenhum dado real perdido.

## Resíduos anteriores a esta rodada

- MegaSena e ControleRendaVariavel guardam `valida-admin`, `valida-usuario` e
  `valida-next`, desativados, da rodada de reset de senha (30/08).
- O ConfortoTermico **não** tem resíduo: o `valida-sessao` que aparece no log do
  contêiner foi criado e apagado pelo próprio script de validação. Verificado
  no banco — só existem `mspa` (1) e `Admin` (7).

## Execução posterior de correções — 2026-08-31

O mantenedor autorizou corrigir o ControleBancario e revalidar o plano geral.
O lote foi concluído localmente, sem VPS e sem commit:

- 239 testes e lint aprovados no contêiner de qualidade;
- três migrations novas aplicadas;
- aplicação reconstruída e saudável na porta 5201;
- revalidação funcional concluída no navegador interno;
- parcelamento temporário `ZZTESTE-REVALIDACAO-100-3` criado e removido;
- baseline reconfirmado em 714 lançamentos e zero lançamento `ZZTESTE`.

O perfil Operador foi aplicado à Claudia antes de o mantenedor esclarecer que
essa configuração de teste não precisava de validação adicional. Ela continua
como `user`; nenhuma senha foi tocada.

O estado corrigido por achado está em `STATUS_CB.md`. A nova ordem transversal
está em `CONCLUSOES_TRANSVERSAIS.md`, seção 6. As lacunas remanescentes são
autorização por papel e uploads; não há trabalho pendente no lote de correções
do ControleBancario.

## Execução das sete prioridades imediatas — 01/09/2026

O lote seguinte foi implementado e validado localmente:

- ConfortoTermico: CT-09, CT-07 e CT-05;
- MegaSena: MS-11 e MS-10;
- ControleRendaVariavel: RV-14, RV-05, RV-06 e RV-10;
- ControleBancario: revalidação integral do lote anterior.

Resultado de qualidade: Ruff aprovado nos quatro projetos e **769 testes**
aprovados (CT 223, MS 115, CB 239, RV 192). As quatro aplicações foram
reconstruídas com Docker, migrações concluíram e todos os serviços operacionais
ficaram saudáveis. Os quatro endpoints locais responderam com o redirecionamento
de autenticação esperado. O navegador interno não possuía uma sessão autenticada
herdada nesta etapa; portanto, os fluxos protegidos foram revalidados pelos
testes de rota, serviço e contrato, sem tentativa de usar credenciais.

Commits locais dos sistemas:

- ConfortoTermico `f9c8d90` — Corrigir exportacao, cadastro e frescor no
  ConfortoTermico;
- MegaSena `b8f7d9f` — Recusar filtros invalidos e restaurar calculo de
  parametros;
- ControleRendaVariavel `16661c3` — Validar eventos e explicitar posicoes sem
  cotacao;
- ControleBancario `2325200` — Concluir correcoes da auditoria funcional.

Nenhum commit foi enviado a remoto e nenhum VPS foi alterado. A análise geral
foi revalidada em `CONCLUSOES_TRANSVERSAIS.md`, seção 7; a próxima prioridade é
montar contas estáveis por papel e executar a matriz de autorização.

## Retomada: decisões de produto e validação final — 01/09/2026

As seis decisões de produto aprovadas foram implementadas localmente e
consolidadas em `CONCLUSOES_TRANSVERSAIS.md`, seção 8. A configuração de
`Claudia` foi retirada do escopo por decisão do mantenedor; a lacuna de teste
por papel permanece registrada, sem simular credenciais.

Validação final: **778 testes aprovados** (RV 195, CB 243, MS 115, CT 225),
Ruff aprovado nos quatro repositórios, migrações de todos os sistemas
verificadas em pilhas saudáveis, e upgrade/downgrade/upgrade do MegaSena
confirmado em PostgreSQL isolado. A pilha do RendaVariavel também foi
confirmada autenticada no navegador, incluindo o modo discreto. Os ambientes
temporários foram removidos; nenhum dado existente foi usado nos bootstraps.

Backup do RendaVariavel foi deliberadamente omitido com autorização expressa
do mantenedor e aceitação do risco. Aguardam-se somente commits locais,
publicação dos ramos e atualização do VPS a partir de `main`, já autorizados.
