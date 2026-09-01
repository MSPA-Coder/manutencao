# Status — CT (ConfortoTermico)

**RODADA CONCLUÍDA.** Blocos 1 a 8 executados. Nada pendente de execução —
só a leitura do orquestrador e o cruzamento com os outros três sistemas.

Blocos concluídos: 1, 2, 3 (bloqueado no CT-07), 4 (só inspeção), 5, 6 (só
inspeção), 7 (completo), 8 (completo).

Achados por severidade: Bloqueio 2 (CT-07, CT-09) | Defeito 5 (CT-02, CT-03,
CT-05, CT-08, CT-12) | Inconsistência 2 (CT-01, CT-11) | Melhoria 2 (CT-10,
CT-13) | Observação 1 (CT-06).

Limpeza pendente: NENHUMA. No início desta 3ª sessão havia um resíduo
(`ZZTESTE-ct` id 15, criado pela 2ª tentativa que morreu por limite de sessão
antes de atualizar este arquivo) — foi excluído. O `ZZTESTE-ct` recriado
nesta sessão (id 16) para testar o Bloco 7 também foi excluído ao final,
confirmado fora da lista de usuários. Nenhum outro registro `ZZTESTE` existe
em nenhuma tela do sistema. Todo campo de configuração tocado em qualquer
bloco (intervalo de leitura, porta SMTP, latitude da zona 1) foi restaurado
e confirmado via API/tela.

## Resumo de achados

- **CT-01** Inconsistência — `<main>` só cobre o Dashboard; as outras 7 abas
  ficam fora do landmark (afeta ferramentas que leem "conteúdo principal").
- **CT-02** Defeito — "Habilitar sons de alerta" existe e funciona, mas fica
  permanentemente invisível por uma classe `oculto` sem condição.
- **CT-03** Defeito — rota "destrutiva" `consolidar-historico` dispara
  sozinha na navegação comum (boot da página, abrir/filtrar Histórico), não
  só por clique deliberado. Idempotente (não duplica), mas roda sem aviso.
- **CT-04** Defeito — aba Análises pode travar em "Nenhuma zona cadastrada
  ainda" depois de reloads seguidos, sem se recuperar sozinha.
- **CT-05** Defeito — Dashboard mostra status colorido (PERIGO/ALERTA) com
  leitura de 15 dias de atraso, sem indicar a idade do dado (só hora, sem
  data); "Qualidade: boa" também não considera a idade.
- **CT-06** Observação de baixa confiança — troca de zona no Histórico
  devolveu ao Dashboard uma vez, não reproduzido.
- **CT-07** Bloqueio — botão "Salvar zona" não cria zona nenhuma, falha
  100% silenciosa (sem erro de console, sem requisição de rede, diálogo
  não fecha). Bloqueou partes dos Blocos 3, 4 e 6. **Contraste importante:**
  o CRUD de usuário (Bloco 7) funciona de ponta a ponta sem esse problema —
  o defeito é específico do formulário de zona, não geral do sistema.
- **CT-08** Defeito — porta SMTP fora de faixa (99999) é gravada como 65535
  em vez de recusada, sem avisar que o valor foi alterado.
- **CT-09** Bloqueio — "Exportar todas em CSV" sempre falha
  (`net::ERR_EMPTY_RESPONSE`); exportação de execução isolada grande (43.200
  medições) também falha; funciona até ~14.400 medições. **Atualizado nesta
  sessão:** o orquestrador confirmou via `docker inspect` que o contêiner
  `conforto-termico-ict-1` tem `RestartCount=3` com saída limpa (exit 0, sem
  OOM) — ou seja, a exportação grande **derruba o processo do servidor**,
  que o Docker reergue automaticamente. Não é só uma operação que falha para
  quem pediu, é uma queda de disponibilidade para todos os usuários
  conectados. Não reproduzir de novo — a evidência já fecha o achado.
- **CT-10** Melhoria — botão Voltar do navegador não desfaz troca de aba
  (a SPA nunca muda a URL nem empilha histórico); Voltar pula para fora do
  app inteiro, para a página anterior real no histórico do navegador. Não
  existe link direto para abrir numa aba específica.
- **CT-11** Inconsistência — coluna "Último login" na tela de Usuários
  mostra timestamp ISO 8601 cru (`2026-08-30T14:50:36`), não o formato
  pt-BR usado no resto do sistema.
- **CT-12** Defeito — evento de auditoria `LOGIN_SUCESSO` grava
  `usuario.login`/`usuario.perfil` = `"unknown"` mesmo com o login real
  disponível em `detalhes` no mesmo evento (evidência de segunda mão, via
  `docker logs`, fornecida pelo orquestrador). **Confirmado em primeira mão
  por mim:** o ConfortoTermico não tem nenhuma tela ou endpoint de auditoria
  acessível pela interface web (Sistema/SPA sem seção de log; ~13 rotas
  prováveis testadas, todas 404) — a trilha só existe no log bruto do
  contêiner, inacessível a qualquer usuário do produto.
- **CT-13** Melhoria — `:focus { outline: none }` global no CSS, substituído
  só por `border-color`; pode ser indicador de foco insuficiente em
  elementos sem borda visível ou no tema escuro.

## Duas pistas do orquestrador — resultado

1. **Auditoria "unknown"** — confirmada a lacuna do dado (via evidência do
   orquestrador) e confirmada em primeira mão a ausência total de tela de
   auditoria no produto. Vira CT-12.
2. **Usuário `valida-sessao` (id 14)** — **NÃO encontrado no
   ConfortoTermico.** A lista de usuários deste sistema só tem 2-3 contas
   (`Admin`, `mspa`, e o `ZZTESTE-ct` que eu mesmo criei/removi);
   `/usuarios/14/editar` redireciona para a lista (id inexistente); sem
   paginação escondendo linha nenhuma (confirmado via contagem de `<tr>` no
   DOM). Repassado ao orquestrador como divergência a reconciliar — talvez
   pertença a outro sistema (README já documenta esse padrão `valida-*` para
   MegaSena e ControleRendaVariavel, não para ConfortoTermico), ou já tenha
   sido removido entre a leitura do log e esta checagem. Não registrei como
   Observação por não conseguir sustentar o achado pela própria tela.

## Notas de método (mantidas da sessão anterior + novas desta)

- `get_page_text` só lê `<main>`, fixo no Dashboard (CT-01). Usar
  `javascript_tool` para ler `innerText`/`textContent` do painel
  `#aba-<nome>`.
- `read_page` filter:"interactive" só enxerga elementos dentro de `<main>`.
- Aba própria desta sessão: `tab-3`. Viewport: `resize_window` 1400x900
  após cada navigate/reload (senão cliques por coordenada podem falhar).
- Evitar reload da página principal fora de necessidade: cada reload da SPA
  dispara CT-03 de novo (idempotente, mas gera ruído de rede). Navegar
  direto para páginas administrativas (`/usuarios/*`, `/minha-senha`,
  `/health`) não dispara CT-03 — só a SPA principal (`/`) dispara.
- CT-07 confirmado (3 tentativas na sessão anterior) — não repetir teste de
  criação de zona.
- **NOVO — cliques por `ref` não confiáveis nesta sessão inteira:** usar
  `computer` com `coordinate`, não `ref`, sempre que possível. Em
  `/usuarios/*` e `/minha-senha`, coordenada direta do screenshot funciona.
- **NOVO — na SPA principal (`/`), nem `ref` nem coordenada direta do
  screenshot acertam o alvo.** É preciso calibrar: pegar
  `getBoundingClientRect()` do elemento via `javascript_tool`, dividir x e y
  por ~5,08, clicar nessa coordenada, e **confirmar o resultado** (classe
  `.ativo`, `aria-selected`, texto renderizado) — não confiar no screenshot
  para mirar. Prendi um listener de `click`/`pointerdown` em `document` para
  calibrar o fator (`event.clientX/clientY` reais contra a coordenada
  pedida). Causa provável: `devicePixelRatio` 2 na aba combinado com algo no
  layout da SPA — não investigado a fundo (fora do escopo do agente de
  observação).
- **NOVO — screenshots da SPA principal podem mostrar overflow horizontal
  falso** (mesmo artefato de escala do item acima). Antes de reportar
  "conteúdo cortado"/"responsividade quebrada" nessa página, confirmar via
  `getBoundingClientRect()` contra `window.innerWidth` — no teste desta
  sessão (viewport mobile), o screenshot mostrava cartões cortados que na
  medição real não excediam a viewport.
- Modais de confirmação do sistema são customizados (SharedAuth UI,
  atributo `data-sa-confirmar`), não `window.confirm()` nativo — texto e
  botões (`Cancelar`/`Confirmar` ou `Cancelar`/<ação>) aparecem como um
  cartão na própria página, clicáveis normalmente por coordenada. Não
  precisa (e não adianta) sobrescrever `window.confirm` para eles.
- Downloads de arquivo (CSV) deliberadamente evitados a rodada toda — testei
  conteúdo via `fetch` em memória, nunca cliquei no link que dispara
  download real (exigiria autorização explícita impossível de pedir no meio
  da tarefa).
- Para qualquer escrita de dado (formulário), usar `form_input`/`computer`
  (clique real); reservar `javascript_tool` para leitura/inspeção
  (innerText, fetch GET, checkValidity, getBoundingClientRect). O
  classificador do "Auto mode" bloqueia escrita de valor de formulário via
  `javascript_tool`.

## Remediação das prioridades imediatas — 01/09/2026

- **CT-09 — resolvido:** a exportação CSV passou a ser entregue por streaming
  e a consulta ao banco é percorrida em lotes, sem montar o arquivo inteiro e
  uma segunda cópia em memória.
- **CT-07 — resolvido:** salvar zona/equipamento não abre mais uma confirmação
  concorrente sobre o modal de edição. Confirmações foram preservadas nas
  ações destrutivas.
- **CT-05 — resolvido:** a API agora informa idade e atualidade da leitura. A
  interface marca dado vencido como `DADO DESATUALIZADO`, mostra o horário da
  última leitura e não representa atuação térmica como se fosse atual.
- **Validação:** Ruff aprovado, **223 testes** aprovados, imagem operacional
  reconstruída, `ict`, coletor e PostgreSQL saudáveis. Verificação do banco:
  5 zonas, 2 usuários, 44.642 leituras e 6 execuções.
- **Smoke no navegador:** aplicação alcançável; a aba nova redirecionou para
  login, pois não havia sessão autenticada herdada. Os contratos autenticados
  alterados foram cobertos pela suíte automatizada.
