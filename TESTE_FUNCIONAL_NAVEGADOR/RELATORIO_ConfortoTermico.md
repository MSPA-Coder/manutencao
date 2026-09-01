# Relatório — ConfortoTermico (CT)

Alvo: http://127.0.0.1:5001. Sessão herdada como `mspa`.
Início: 2026-08-31 (2ª tentativa — 1ª morreu no bloco 1 por limite de sessão, zero resíduo).

Regra de ouro observada: acervo real de 5 zonas, 42 equipamentos, 44.642
leituras, 65.088 medições. Todo registro de teste usa prefixo `ZZTESTE`.

---

## Bloco 1 — Varredura do menu

Estrutura real encontrada bate exatamente com a esperada no prompt:
- **Monitoramento:** Dashboard · Análises · Histórico
- **Operação:** Operação
- **Administração:** Cadastro · Configurações · Sistema
- **Dados:** Dados de entrada

Todas as 8 abas abriram, conteúdo corresponde ao rótulo, e a aba ativa fica
marcada corretamente (`aria-selected="true"` + classe `ativo` no botão —
conferido via inspeção de DOM). Carregamento perceptivelmente instantâneo em
todas (é troca de painel local via JS, sem requisição de página).

Nota de método: a interface é de aba única (SPA) e a URL nunca muda
(`http://127.0.0.1:5001` fixo em todas as abas) — aprofundar isso no Bloco 8.
Também nota-se que cada painel de aba tem seu próprio elemento raiz
(`aba-dashboard` implícito, `aba-analises`, `aba-historico`, `aba-operacao`,
`aba-zonas` para Cadastro, `aba-configuracoes`, `aba-sistema`,
`aba-dados-entrada`), todos alternando `display:none`/visível corretamente.

### [CT-01] `<main>` só envolve o conteúdo do Dashboard; as outras 7 abas ficam fora do landmark
- **Severidade:** Inconsistência
- **Onde:** toda a navegação por abas — estrutura de DOM (`div.app-shell`)
- **Passos:** 1. Carregar a página (Dashboard ativo). 2. Inspecionar o DOM: `document.querySelectorAll('main').length` = 1, e esse único `<main>` contém só os 4 painéis do Dashboard (`entradas-grafico-painel`, `dashboard-status-painel`, `linhas-zonas-principal`, `secao-email`). 3. Clicar em qualquer outra aba (testado com Análises, Histórico, Operação, Cadastro, Configurações, Sistema, Dados de entrada). 4. Inspecionar onde vive o painel ativo: `#aba-analises` (e os demais `#aba-*`) são **irmãos** de `<main>` dentro de `div.app-shell`, não descendentes dele.
- **Esperado:** o conteúdo principal de qualquer aba ativa deveria estar dentro do landmark `<main>` (ou a app deveria trocar o que `<main>` envolve conforme a aba).
- **Obtido:** `<main>` é fixo e só contém o Dashboard. Nas outras 7 abas, o conteúdo relevante está fora do `<main>`, direto em `div.app-shell`.
- **Evidência:** `document.getElementById('aba-analises')` tem cadeia de pais `SECTION#aba-analises.grade aba-conteudo → DIV.app-shell → BODY` (sem `<main>` no meio). Efeito colateral prático: uma ferramenta que lê "o conteúdo principal da página" via `<main>` (inclusive a `get_page_text` usada nesta própria varredura) sempre devolve o Dashboard, não importa qual aba está ativa na tela.
- **Vale para os outros sistemas?** talvez — sistemas com layout de abas única via JS (não é o caso dos outros 3, que usam navegação por página/HTMX) têm o mesmo risco; vale checar se algum dos outros reaproveita `<main>` de forma parecida.

### [CT-02] Aba Configurações > "Habilitar sons de alerta" é um controle real, funcional, mas fica invisível por uma classe CSS `oculto` esquecida
- **Severidade:** Defeito
- **Onde:** Administração > Configurações > "Preferências do app"
- **Passos:** 1. Clicar na aba Configurações. 2. Ler o conteúdo visível do painel (`innerText`): só aparecem "Preferências do app" (título, sem nenhum controle visível abaixo) e a seção "Alertas por e-mail". 3. Inspecionar o DOM completo (`textContent`, que inclui elementos ocultos) e achar o checkbox `#cfg-sons`. 4. Examinar seu elemento pai: `<label class="check oculto"><input type="checkbox" id="cfg-sons"><span>Habilitar sons de alerta</span></label>`.
- **Esperado:** "Preferências do app" deveria mostrar (conforme o Bloco 5 do roteiro) controles como habilitar sons, habilitar equipamentos, intervalo de leitura e modo simulado por zona. Pelo menos o de sons deveria estar nesta aba, visível e clicável.
- **Obtido:** o checkbox "Habilitar sons de alerta" existe de fato no HTML, tem `id`, responde a leitura via API/DOM (`checked:false`), mas está **permanentemente invisível** porque seu `<label>` traz a classe `oculto` (mesma classe usada, à parte, para esconder o campo "Enviar avisos para" quando os alertas por e-mail estão desligados — mas o de sons não tem essa lógica condicional, está com `oculto` fixo). Isso não é um caso de "aba vazia" — é um controle funcional escondido por engano, tornando impossível para qualquer usuário (mesmo admin) ligar ou desligar o som de alerta pela tela. Os outros 3 campos que o roteiro esperava aqui (intervalo de leitura, habilitar equipamentos, modo simulado por zona) de fato não pertencem a esta aba — ficam em Sistema (intervalo de leitura, modo simulado por zona) e em Operação (habilitar equipamentos = "Permitir acionamento físico global").
- **Evidência:** `document.getElementById('cfg-sons').parentElement.outerHTML` = `'<label class="check oculto"><input type="checkbox" id="cfg-sons"><span>Habilitar sons de alerta</span></label>'`; `getComputedStyle` desse `<label>` = `display:none`. O mesmo padrão de classe `oculto` aparece no wrapper de "Enviar avisos para" (`#wrap-email-destino`), mas ali faz sentido (o campo só deve aparecer quando "Enviar e-mails de aviso" está marcado) — no de sons não há essa condição, é sempre oculto.
- **Vale para os outros sistemas?** talvez — vale procurar por classes de utilidade tipo `oculto`/`hidden` aplicadas sem a lógica condicional correspondente nos outros três sistemas.

Achados que serão detalhados em blocos específicos (só registrados aqui como
pista encontrada durante a varredura, não fechados):
- Dashboard mostra leitura "recente" às 22:58 para todas as zonas, mas o
  heartbeat do coletor mostra hora bem diferente (~02:1x) e o painel Análises
  relata "Sem leituras no período (24h)" / "Sem leituras hoje" para a mesma
  zona. Investigar coerência no Bloco 2.
- Aba Dados de entrada expõe a ação "Copiar para histórico" e um bloco
  "Confirmação para exclusão / Apagar medições do histórico" — são as rotas
  destrutivas do roteiro. Inspecionar sem clicar no Bloco 6.
- Aba Sistema tem botão "Consolidar histórico pendente" — também rota
  destrutiva (`/api/consolidar-historico` ou por zona). Não acionar.

---

## Bloco 2 — Dashboard, Análises e Histórico (leitura)

### [CT-03] A rota "destrutiva" `/api/zonas/<id>/consolidar-historico` é acionada sozinha pela navegação comum, não só por clique deliberado
- **Severidade:** Defeito
- **Onde:** toda a navegação de leitura — Dashboard (carga da página) e Histórico (troca de zona no filtro)
- **Passos:** 1. Carregar a página do zero (`navigate` para `http://127.0.0.1:5001`). 2. Observar `read_network_requests`: aparece `POST /api/zonas/1/consolidar-historico → 200 OK` no meio do boot, sem qualquer clique em botão de consolidação. 3. Recarregar de novo: o mesmo POST se repete para a zona 1. 4. Abrir a aba Histórico (só ler, nenhum clique em "Copiar para histórico"): novo `POST /api/zonas/1/consolidar-historico`. 5. Trocar a zona do filtro do Histórico para a zona 2: `POST /api/zonas/2/consolidar-historico`.
- **Esperado:** conforme o texto da própria aba "Dados de entrada" ("Use a ação 'Copiar para histórico' em uma geração concluída") e conforme o roteiro deste teste, esta é uma rota que só deveria rodar por ação explícita e consciente do usuário, pelo risco de escrever no schema histórico de 44 mil leituras.
- **Obtido:** a rota roda automaticamente, em segundo plano, toda vez que a página carrega e toda vez que se abre/filtra o Histórico por zona — quatro disparos observados nesta sessão sem que o agente clicasse em nenhum botão de consolidação. O aviso de risco na tela ("Confirmação para exclusão", texto sobre "Copiar para histórico") dá a entender que é uma ação manual e pontual; na prática é um efeito colateral automático de navegação comum.
- **Evidência:** `read_network_requests` mostrando, entre outras, `POST http://127.0.0.1:5001/api/zonas/1/consolidar-historico → 200 OK` (3x, em cargas/aberturas distintas) e `POST http://127.0.0.1:5001/api/zonas/2/consolidar-historico → 200 OK` (ao trocar o filtro de zona no Histórico). O próprio texto da aba Dados de entrada afirma que "repetições não duplicam medições" — a operação parece ter sido projetada para ser idempotente, o que evita perda/duplicação de dado, mas não muda o fato de que a rota roda sem aviso nem ação deliberada.
- **Vale para os outros sistemas?** talvez — vale conferir se os outros três sistemas têm alguma rota classificada como "destrutiva/sensível" no prompt que, na prática, seja disparada por telas de leitura comuns.

### [CT-04] Aba Análises pode ficar travada mostrando "Nenhuma zona cadastrada ainda" mesmo com 5 zonas cadastradas, sem se recuperar
- **Severidade:** Defeito
- **Onde:** Monitoramento > Análises
- **Passos:** 1. Recarregar a página (`navigate`). 2. Esperar de 0 a 4 segundos (testado nas duas pontas). 3. Clicar na aba Análises. 4. Painel mostra "Nenhuma zona cadastrada ainda" nas três seções (Painel executivo, Percentual de tempo em cada condição térmica, Índice mínimo/médio/máximo). 5. Tentar destravar: voltar ao Dashboard, esperar, voltar a Análises — mesmo resultado. Trocar a zona no seletor interno de Análises (`#zona-executivo`) via evento `change` — mesmo resultado.
- **Esperado:** o painel deveria mostrar os dados das 5 zonas reais (como mostrou na primeira carga da sessão, antes de qualquer reload — ver evidência).
- **Obtido:** uma vez travado nesse estado (reproduzido em 2 recargas de página seguidas), nenhuma interação dentro da própria aba (nem trocar zona, nem esperar, nem revisitar outras abas) o destrava. Nenhum erro aparece no console (`read_console_messages` limpo) nem na rede (nenhuma chamada nova é sequer disparada ao clicar em Análises — os dados de zona já estavam disponíveis via `/api/zonas`, retornado 200 OK no boot). Isto sugere cache de estado no JavaScript do cliente (`analises.js`) que fica vazio na primeira renderização e nunca é re-populado.
- **Evidência:** antes do primeiro reload desta sessão, o painel funcionou (mostrou "Painel executivo por zona", tendências 15/30/60min, "Tempo contínuo no status atual: 339h19min" etc., para Aviário 1). Depois de dois reloads seguidos, o mesmo painel virou consistentemente `"Nenhuma zona cadastrada ainda."` nas três seções, com `innerText` total de 750 caracteres.
- **Vale para os outros sistemas?** não avaliado.

### [CT-05] Dashboard mostra status colorido (PERIGO/ALERTA) com base em leitura de 15 dias atrás, sem indicar que o dado está velho
- **Severidade:** Defeito
- **Onde:** Monitoramento > Dashboard (cartões por zona) e Operação > Status
- **Passos:** 1. Ler a hora real do servidor (`fetch('/')` + header `Date`): 31/08/2026 02:20 (America/Sao_Paulo, confirmado por `Intl.DateTimeFormat().resolvedOptions().timeZone`). 2. Ler "Última leitura registrada às" em cada cartão de zona no Dashboard: todas cravadas em "22:58" sem data visível. 3. Recarregar a página: os mesmos horários se mantêm. 4. Chamar diretamente `fetch('/api/operacao/status')` e ler o JSON completo.
- **Esperado:** ou a leitura avança (o coletor roda em modo simulado e deveria gerar leituras periodicamente, a julgar pelo "Intervalo entre leituras" configurável na aba Sistema), ou, se não há leitura recente, o Dashboard deveria sinalizar isso com destaque — do jeito que a aba Análises sinaliza ("Sem leituras no período", "Sem leituras hoje") para a mesma zona/situação.
- **Obtido:** o JSON de `/api/operacao/status` revela a extensão real do problema: `"coletor":{"heartbeat_em":"2026-08-31T02:38:40","iniciado_em":"2026-08-30T23:01:56","online":true,"proximo_ciclo_em":"2026-08-31T02:39:40","status":"online","ultimo_ciclo_em":"2026-08-31T02:38:40"}` — o coletor (nível global) está com ciclo corrente, atualizando a cada ~60s, normalmente. Mas **cada zona**, no mesmo payload, mostra `"ultimo_ciclo_em":"2026-08-16T22:58:24"` (zona 1), `"...-16T22:58:27"` (zona 2), `"...-16T22:58:31"` (zona 3) etc. — **16 de agosto**, não 31. Ou seja, o processamento por zona está parado há **15 dias**, não algumas horas como a hora sozinha (sem data) sugeria à primeira vista na tela. O Dashboard, mesmo assim, exibe o índice ITU 81,88 com badge vermelho "PERIGO" para o Aviário 1 (e ALERTA para outras duas zonas) tratando a leitura como atual, só com "Última leitura registrada às 22:58:22" — sem data e sem qualquer destaque de que o dado tem 15 dias. A aba Análises (quando funciona) capta a ausência de leitura recente ("Sem leituras no período", "Sem leituras hoje") mas também não menciona os 15 dias explicitamente. O resumo de status da aba Operação mostra "Qualidade: boa" para essa mesma leitura de 15 dias — o indicador de qualidade não considera a idade do dado.
- **Evidência:** JSON de `/api/operacao/status`: coletor com `ultimo_ciclo_em` de hoje (`2026-08-31T02:38:40`) contra `zonas[].ultimo_ciclo_em` de `2026-08-16` para as 5 zonas. Isso também explica um achado de leitura anterior: a aba Histórico mostrava "Período exibido: 16/08/2026" para o gráfico mais recente — não é um bug de exibição, é literalmente a última data com dado real.
- **Vale para os outros sistemas?** não se aplica diretamente (são domínios diferentes), mas o padrão "status colorido de urgência sem indicar idade do dado, e sem data visível — só hora" vale como lente para os outros três.

### [CT-06] (baixa confiança) Troca de zona no filtro do Histórico devolveu a tela ao Dashboard uma vez, não reproduzido na repetição
- **Severidade:** Observação
- **Onde:** Monitoramento > Histórico > filtro de zona
- **Passos:** 1. Na aba Histórico, trocar o seletor de zona para "Aviário 2" via evento `change`. 2. Alguns segundos depois (após outras leituras de rede), a tela apareceu no Dashboard (`aba-principal` com `display:grid`, `aba-historico` com `display:none`), sem clique em nenhuma aba. 3. Repetindo o teste (trocar para "Confinamento Bovino 1"), a tela permaneceu em Histórico normalmente.
- **Esperado:** trocar a zona do filtro não deveria mudar de aba.
- **Obtido:** ocorreu uma vez, não reproduzido na segunda tentativa. Pode ser efeito colateral do próprio agente (uso de evento sintético via JavaScript em vez de clique real) — registrado como observação de baixa confiança, não como defeito fechado.
- **Vale para os outros sistemas?** não aplicável.

### Testes de período no Histórico (positivo)
- **Período sem dados** (2020-01-01 a 2020-01-02): tabela e gráfico ficam vazios, contador mostra "Sem leituras". Comportamento correto.
- **Período invertido** (De: 30/08/2026, Até: 01/08/2026): a tela recusa com mensagem clara em português: "A data inicial não pode ser posterior à data final." Sem chamada de API disparada para o backend validar — validação client-side. Comportamento correto.
- **Período muito longo** (2000-01-01 a 2026-08-31, 26 anos): respondeu em bem menos de 1,5s, paginado corretamente ("Leituras 8901-8930 de 8930"). Sem problema de desempenho perceptível.

---

## Bloco 3 — Cadastro de zonas e equipamentos (inclusão, alteração, exclusão)

### [CT-07] Botão "Salvar zona" não cria zona nenhuma — falha 100% silenciosa
- **Severidade:** Bloqueio
- **Onde:** Administração > Cadastro > "+ Nova zona" — diálogo `#dialog-zona`, formulário `#form-zona`, botão `#btn-salvar-zona`
- **Passos:** 1. Abrir Cadastro. 2. Clicar em "+ Nova zona" (abre o diálogo nativo `<dialog>` com campos Nome da zona, Espécie, Índice, Zona ativa). 3. Preencher nome "ZZTESTE Zona", espécie "Avicultura (frangos de corte)", índice "Índice de Temperatura e Umidade" — `form.checkValidity()` confirma `true`, todos os campos obrigatórios preenchidos corretamente. 4. Clicar em "Salvar zona".
- **Esperado:** a zona é criada (`POST` para a API de zonas), o diálogo fecha e "ZZTESTE Zona" aparece na lista "ZONA CADASTRADA".
- **Obtido:** nada acontece. Testado 3 vezes, em 2 aberturas distintas do diálogo, com clique via `elemento.click()` (JavaScript) e com clique real de mouse (via `computer`/coordenada, confirmado por `document.elementFromPoint` que o clique realmente acerta o botão `#btn-salvar-zona`): em nenhum dos casos houve requisição de rede nova (`read_network_requests` sem nenhum `POST` a `/api/zonas` em nenhuma tentativa), nenhuma mensagem de erro no console (`read_console_messages` vazio), nenhuma mudança visual, e o diálogo permanece aberto. Um listener de teste confirmou que o evento `submit` do formulário **dispara normalmente** (`submitFired: true`) — ou seja, o problema não é o clique não chegar ao botão; é o manipulador do formulário não produzir efeito nenhum: sem chamada de API, sem erro, sem fechamento do diálogo.
- **Evidência:** `read_network_requests` antes/depois do clique idêntico (nenhum `POST /api/zonas`); `read_console_messages` sempre vazio; `document.getElementById('dialog-zona').open` permanece `true` após o clique; `document.elementFromPoint(x,y)` confirma que o clique atinge `#btn-salvar-zona`.
- **Impacto:** bloqueia por completo o restante do Bloco 3 e do Bloco 4 conforme o roteiro — sem conseguir criar a zona `ZZTESTE`, não foi possível testar edição de zona, criação de equipamentos, ativar/desativar zona nem exclusão em cascata (ver notas abaixo). Também não foi possível gerar dados de entrada nem rodar ciclo de operação restritos à zona `ZZTESTE` pedidos nos Blocos 4 e 6 — essas partes ficam como "não verificado" por dependência direta deste bloqueio.
- **Limpeza:** nada foi persistido — não há resíduo `ZZTESTE` no sistema (o próprio bug impediu a criação).
- **Vale para os outros sistemas?** talvez — vale conferir se os outros três sistemas têm alguma tela de criação via `<dialog>` nativo com o mesmo padrão de formulário que possa sofrer do mesmo tipo de falha silenciosa (handler que não fecha o diálogo nem reporta erro).

### Consequência: Bloco 3 passos 2–6 e trechos dos Blocos 4/6 não puderam ser executados
Como não existe forma alternativa de criar uma zona pela interface (a aba "Dados de entrada" só edita localização/lote de zonas **já existentes** — não cria zonas), e a regra de ouro proíbe tocar nas 5 zonas reais, os seguintes itens do roteiro ficam **não verificados** por causa do CT-07:
- Validação de quantidade de animais negativa, peso zero, latitude fora de -90..90 e código IBGE inválido — esses campos nem aparecem no diálogo "Nova zona" (só nome/espécie/índice/ativa); pertencem à seção "Localização e lote animal por zona" da aba Dados de entrada, que só lista **zonas ativas já cadastradas**. Sem uma zona `ZZTESTE`, esses campos não puderam ser exercitados com dado próprio — ver Bloco 6.
- Editar a zona criada (mudar espécie/densidade e conferir se limites/índice acompanham) — não verificado.
- Criar ventilador e nebulizador na zona `ZZTESTE`, testar endereço duplicado e fator de escala zero com um salvamento real — não verificado quanto ao comportamento do servidor. Verificado apenas o lado cliente: o campo "Fator de escala" (`#equip-fator-escala`, `type=number`, `step=0.001`) **não tem atributo `min`**, então `checkValidity()` aceita o valor `0` sem reclamar — se o servidor também aceitar, um fator de escala zero passaria despercebido (dividiria/multiplicaria leituras por zero). Isto foi conferido abrindo o diálogo "+ adicionar" de um ventilador da zona real Aviário 1 e cancelando sem salvar (nenhum dado foi alterado).
- Ativar/desativar a zona `ZZTESTE` e ver efeito no Dashboard/Operação — não verificado.
- Excluir equipamentos e depois a zona, e conferir se a exclusão com equipamento vinculado é barrada ou cascateia — não verificado.

### Observações adicionais do Bloco 3
- O diálogo "Nova zona" reage normalmente ao botão "Cancelar" (fecha sem problema) — o defeito é específico do caminho de salvar, não do diálogo como um todo.
- A validação nativa do campo obrigatório "Nome da zona" (`required`) funciona (bloqueia envio com o campo vazio), mas a mensagem do navegador aparece em inglês ("Please fill out this field.") nesta sessão de teste — isso é porque o Chrome usado pelo agente está configurado como `en-US` (`navigator.language`), não porque o app force inglês; o `<html lang="pt-BR">` está correto. Em um Chrome real com o SO em português, a mensagem nativa sairia em pt-BR automaticamente. Registrado como nota metodológica, não como achado do produto.
- O campo "Índice" do diálogo de zona é dinâmico: ao escolher "Avicultura (frangos de corte)" como espécie, uma terceira opção aparece ("Índice de Temperatura, Umidade e Velocidade" / ITUV), ausente para as outras espécies. Comportamento correto (é o que se vê nas zonas reais: Aviário 2 usa ITUV).
- O diálogo "Novo equipamento" tem campos ricos e corretos: Tipo (Sensor/Ventilador/Nebulizador), Nome/Identificação, Campo medido, Modo de conexão (Modbus TCP / RTU serial), Host/Porta ou Porta serial/Baud rate, ID do dispositivo, Tipo de registrador (Holding/Coil), Endereço do registrador, Tipo de dado, Fator de escala, e um botão "Testar conexão" — estrutura consistente com o que se vê nos equipamentos reais cadastrados.

---

## Bloco 4 — Operação

**Decisão de escopo:** por causa do CT-07 (bloqueio na criação de zona), não há
zona `ZZTESTE` disponível. O roteiro deste bloco pede para operar a zona
`ZZTESTE` especificamente — ligar/desligar equipamentos e rodar ciclo manual
são ações que alteram o estado runtime (comando desejado/confirmado) de
equipamentos, e a única forma de exercitá-las seria usando uma das 5 zonas
reais. Optei por **não fazer isso**: mudar o modo operacional ou o
desejado/confirmado de um ventilador/nebulizador de uma zona real, mesmo
sendo reversível e mesmo o roteiro dizendo que acionar é seguro (modo
simulado, sem hardware físico), ainda é mexer no estado de um registro
preexistente que não foi criado por este agente — o que a regra de ouro
proíbe. Portanto, a parte interativa deste bloco fica **não verificada**,
registrada como consequência direta do CT-07, e o bloco foi coberto apenas
por inspeção (leitura de tela e de API, sem gravação).

### Estrutura observada (leitura, zona Aviário 1 como referência, nada alterado)
- **Modo operacional:** seletor com Desligado / Manual / Automático /
  Manutenção — Aviário 1 está em "Desligado" (`operacao-modo` = `desligado`).
- **Chaves de segurança:** "Permitir acionamento físico global" e "Permitir
  acionamento físico desta zona" — ambas **desmarcadas** no momento da
  inspeção (confirmado via DOM: `cfg-equipamentos` e
  `operacao-acionamento-zona` com `checked:false`). "Usar sensores remotos no
  ciclo manual" está marcada. Isso é consistente com o texto do roteiro: o
  sistema não aciona hardware físico.
- **Dados processados do ciclo:** mostra os 4 campos de entrada (TBS, TBU,
  ponto de orvalho, UR) — em modo Desligado aparecem vazios (só rótulos, sem
  valor), coerente com "no automático, mostram os últimos valores
  processados".
- **Equipamentos da zona:** lista igual à do Cadastro, mas aqui mostrando
  também "Comando desejado" e "Estado confirmado" por equipamento (todos
  "desligado" para Aviário 1) e o resumo agregado da zona: "Desejado —
  ventilador: desligado, nebulizador: desligado | Confirmado — ventilador:
  desligado, nebulizador: desligado · Qualidade: boa".
- **Comandos coletivos da zona:** botões "Ligar ventilador", "Desligar
  ventilador", "Ligar nebulizador", "Desligar nebulizador" — existem e têm
  rótulo claro, não clicados (ver decisão de escopo acima).
- **Eventos recentes de operação:** lista temporal com tipo de evento
  (`controle alterado`, `calculo concluido`) — geram entrada e descrevem o
  que aconteceu, na medida do que a leitura permite avaliar. Últimos eventos
  de Aviário 1 também travados em 22:58 (mesma defasagem do CT-05).
- **Status (via `/api/operacao/status`):** o JSON confirma por zona os campos
  `modo`, `qualidade`, `desejado`/`confirmado`, `falhas` (vazio para as 5
  zonas), `ultimo_ciclo_em` e, a nível de coletor, `heartbeat_em`,
  `iniciado_em`, `online`, `proximo_ciclo_em`, `ultimo_ciclo_em` — ver CT-05
  para a discrepância entre o `ultimo_ciclo_em` do coletor (hoje) e das
  zonas (16/08).

Nenhum dado foi alterado nesta inspeção — apenas leituras de tela e de API.

---

---

## Bloco 5 — Configurações e Sistema

**Nota de estrutura real:** os campos de "Preferências do app" que o roteiro
esperava num só lugar estão espalhados por três abas: Configurações (só
"Habilitar sons de alerta" — ver CT-02), Sistema ("Intervalo entre leituras",
"Modo simulado", "Gravar no banco a cada (minutos)", cálculo de parâmetros) e
Operação ("Permitir acionamento físico global" = habilitar equipamentos). A
seção "Banco de dados" da aba Sistema **não mostra nenhuma contagem** (zonas,
equipamentos, leituras) como o roteiro presumia — só tem o campo "Gravar no
banco a cada (minutos)" e o botão "Consolidar histórico pendente". Não há
tela de status com "5 zonas, 42 equipamentos" em lugar nenhum encontrado.

**Método de gravação descoberto:** nem Configurações nem Sistema têm botão
"Salvar" — os campos salvam sozinhos ao perder o foco (`blur`/`change`),
confirmado testando `Intervalo entre leituras`: mudar de 5 para 6 e sair do
campo já reflete em `GET /api/configuracoes` (`intervaloLeituraSegundos:6`)
sem nenhum clique em botão de salvar. **Valor original anotado (5) e
restaurado ao final do bloco**, confirmado de volta em 5 via API.

### [CT-08] Porta SMTP fora da faixa é salva com um valor diferente do digitado, sem avisar
- **Severidade:** Defeito
- **Onde:** Administração > Sistema > Servidor SMTP > "Porta SMTP" (`#cfg-smtp-porta`, `min=1 max=65535`)
- **Passos:** 1. Digitar `99999` no campo Porta SMTP (usando `form_input`, equivalente a digitação real). 2. Tirar o foco do campo (clique fora). 3. Conferir a validade nativa do campo (`checkValidity()`) e o valor salvo via `GET /api/configuracoes`.
- **Esperado:** ou a tela recusa o valor fora de faixa e mantém a porta anterior (587) até o usuário corrigir, ou mostra uma mensagem clara pedindo correção.
- **Obtido:** `checkValidity()` do próprio campo confirma que o navegador considera o valor inválido (`"Value must be less than or equal to 65535."`), mas o auto-save ignora essa invalidade e grava silenciosamente **65535** (não 99999, nem o valor anterior) — ou seja, o valor foi arbitrariamente truncado/grampeado para o teto da faixa sem avisar o usuário que o que ele digitou (99999) foi alterado. Restaurado para 587 (valor original) ao final do teste, confirmado via API.
- **Evidência:** `GET /api/configuracoes` → `"smtpPorta":65535"` logo após digitar 99999 e sair do campo, apesar de `validationMessage: "Value must be less than or equal to 65535."` no mesmo elemento.
- **Vale para os outros sistemas?** talvez — vale conferir se outros campos numéricos com `min`/`max` nos quatro sistemas têm o mesmo padrão de "grampear em vez de recusar, sem avisar".

### Testes de validação e segurança (positivos)
- **Senha SMTP nunca volta em texto claro:** o HTML bruto da página (`fetch('/').then(r=>r.text())`) não tem atributo `value` no campo `#cfg-smtp-senha` (`type="password"`, `placeholder="Deixe em branco para manter a senha atual"`, `autocomplete="new-password"`). A API `GET /api/configuracoes` também nunca devolve a senha real: retorna `"smtpSenha":""` mais uma flag separada `"smtpSenhaConfigurada":false` — padrão correto (nunca expõe o segredo, só informa se um está configurado). Como não há host SMTP configurado neste ambiente, não foi possível testar o comportamento com uma senha real já salva, mas o padrão observado é o certo.
- **Host vazio:** `cfg-smtp-host` está vazio por padrão; a própria tela informa "Sem host SMTP configurado, o envio funciona em modo simulado" — comportamento e aviso corretos, sem tentar validar/enviar nada.
- **`email-destino`** é `type="email"` (validação nativa de formato ativada), mas fica escondido por uma classe `oculto` condicional enquanto "Enviar e-mails de aviso" está desmarcado (esse `oculto` aqui é condicional/correto, ao contrário do de `cfg-sons` no CT-02) — não testado com o campo digitável porque ativar alertas por e-mail poderia sinalizar uma mudança de configuração de envio real; optei por não mexer nessa chave para não arriscar habilitar envio de e-mail global, mesmo em modo simulado.
- **Nenhum e-mail foi disparado** em momento algum deste bloco — não foi tocado o host SMTP nem a chave "Enviar e-mails de aviso".


---

## Bloco 6 — Dados de entrada

**Decisão de escopo:** o roteiro pede para gerar uma execução pequena
restrita à zona `ZZTESTE`. Como o CT-07 impede criar essa zona, e a tela de
geração só lista **zonas ativas já cadastradas** (as 5 reais) para configurar
localização/lote antes de gerar, **não gerei nenhuma execução nova** — rodar
o gerador teria necessariamente produzido dados vinculados às zonas reais
(mesmo que depois apagáveis, a regra de ouro pede para não criar nada em
registro preexistente, e uma "geração" fica associada a todas as zonas ativas
no momento, não dá para isolar só numa zona de teste). Cobri o bloco por
inspeção: dos formulários e validações (sem clicar em salvar/gerar) e das
execuções **já existentes**, criadas antes desta rodada (não fui eu quem
gerou).

### [CT-09] "Exportar todas em CSV" nunca funciona — e exportar uma execução grande também falha
- **Severidade:** Bloqueio
- **Onde:** Administração > Dados de entrada > "Gerações realizadas" > "Exportar todas em CSV" (`GET /api/dados-entrada/exportar.csv`) e exportação por execução (`?execucao_id=N`) quando a execução é grande
- **Passos:** 1. Localizar o link "Exportar todas em CSV" (`href="/api/dados-entrada/exportar.csv"`, sem parâmetro). 2. Buscar o conteúdo (via `fetch`, para não desencadear download no navegador sem autorização prévia). 3. Repetir com `?execucao_id=7` (execução de 43.200 medições, a maior das 6 existentes) e depois com `?execucao_id=6` (14.400 medições) e `?execucao_id=4` (1.152 medições).
- **Esperado:** as três formas de exportação devolvem um CSV válido (a tela nem avisa de nenhum limite de tamanho).
- **Obtido:** "Exportar todas" falha **sempre** (reproduzido 2x): `net::ERR_EMPTY_RESPONSE` — o servidor aceita a conexão e não devolve nada (nem cabeçalho, nem corpo, nem erro HTTP). Exportar a execução 7 isoladamente (43.200 medições) falha do mesmo jeito. Exportar a execução 6 (14.400 medições, CSV de ~14,9 MB) funciona perfeitamente (`200 OK`), assim como a execução 4 (1.152 medições). Ou seja, há um limite de tamanho entre 14.400 e 43.200 medições (aprox. entre 15 MB e 45 MB de CSV) a partir do qual o endpoint quebra por completo — e "Exportar todas" (65.088 medições no total, muito acima desse limite) **nunca vai funcionar** enquanto o volume de dados for este.
- **Evidência:** `read_network_requests` mostra `GET .../exportar.csv [FAILED: net::ERR_EMPTY_RESPONSE]` (2 ocorrências) e `GET .../exportar.csv?execucao_id=7` com o mesmo erro. Em contraste, `execucao_id=6` devolveu `status:200`, `content-type: text/csv; charset=utf-8; charset=utf-8` (nota: o charset aparece **duplicado** no header, outro detalhe a corrigir) e corpo de 14.878.560 caracteres.
- **Não testado por segurança:** não cliquei no link de exportação de nenhuma execução pela tela (isso dispara download de arquivo pelo navegador, que exige autorização explícita do mantenedor que este agente não tem como pedir no meio da tarefa) — toda a verificação foi feita lendo o corpo da resposta via `fetch` diretamente, sem salvar nada em disco.
- **Vale para os outros sistemas?** talvez — vale conferir limites de exportação/relatório com volume grande nos outros três, especialmente ControleBancario (714 lançamentos, provavelmente ok) e ControleRendaVariavel (7.329 cotações, mais parecido em escala).
- **Atualização (retomada, 31/08, antes do Bloco 7):** o orquestrador leu `docker logs`/`docker inspect` do contêiner `conforto-termico-ict-1` e encontrou `RestartCount=3`, com saída limpa (exit code 0, sem OOM killer). Isto muda o diagnóstico: `net::ERR_EMPTY_RESPONSE` não é timeout do navegador nem do proxy — **o processo do servidor está caindo e sendo reerguido pelo Docker** durante a tentativa de exportação grande. Ou seja, o achado não é apenas "a exportação de execução grande falha para quem pediu", é **"a exportação de execução grande derruba o serviço para todos os usuários conectados"** — um bloqueio de disponibilidade, não só uma operação individual malsucedida. Elevo a leitura do impacto por isso, mantendo a severidade Bloqueio já registrada. Não tentei reproduzir de novo nesta retomada (cada tentativa já é uma queda confirmada do serviço) — a evidência do orquestrador já fecha o achado.

### Conteúdo do CSV (a partir da execução 4, que exportou com sucesso, sem download — só leitura do corpo da resposta)
Cabeçalho: `zona_id,zona_nome,especie,indice,timestamp_utc,timestamp_local,fuso_horario,tbs_externa_c,ur_externa_pct,ponto_orvalho_c,tbu_c,velocidade_vento_ms,precipitacao_mm,pressao_hpa,radiacao_w_m2,nebulosidade_pct,valor_indice,status_termico,area_util_m2,densidade_categoria,densidade_animais_m2,quantidade_animais,...` (mais colunas). Separador é vírgula. Os números usam ponto decimal (formato técnico/internacional), diferente do padrão pt-BR das telas (vírgula decimal) — razoável para um arquivo de dados de máquina, mas registrado como inconsistência de formato entre tela e exportação.

### Validações de campo testadas nas zonas reais (sem clicar em salvar — só validação client-side)
Os campos de "Localização e lote animal por zona" (aba Dados de entrada) têm
restrições nativas (`min`/`max`) definidas por campo, iguais para as 5 zonas:
latitude (`-90` a `90`), longitude (`-180` a `180`), altitude (`-500` a
`9000`), peso médio (`0.01` a `2000`), área útil (`0.1` a `10000000`).
Testado com a zona real Aviário 1 (zona 1), **sem nunca clicar em "Salvar
parâmetros das zonas"**: mudei a latitude para `999` via preenchimento de
campo, confirmei `checkValidity()` retornando `false` com a mensagem nativa
"Value must be less than or equal to 90.", conferi que nenhuma requisição de
rede foi disparada (essa tela não salva sozinha ao perder o foco — precisa do
botão "Salvar parâmetros das zonas", diferente da aba Sistema), e **restaurei
o valor original (`-21.92194`) antes de continuar**. Nenhum dado real foi
alterado.
- **Quantidade de animais negativa / peso zero:** o campo "Quantidade de
  animais" e "Densidade de animais/m²" são **somente leitura**
  (`readOnly:true`) — calculados a partir de espécie, peso médio e densidade
  escolhida, não editáveis diretamente. O teste de "quantidade negativa" não
  se aplica a este campo tal como existe hoje; o campo que aceita entrada
  direta é "Peso médio (kg)" (`min=0.01`), então zero seria rejeitado pela
  validação nativa (não testado ao vivo para não mexer mais que o necessário
  em zona real).
- **Código IBGE inválido:** o campo de cidade é um `<select>` com lista
  fechada de municípios (não texto livre) — não existe como digitar um
  código IBGE inválido; a interface previne isso estruturalmente. O teste do
  roteiro não se aplica.
- **Data final da geração:** o campo `dados-entrada-data-final` tem `max` de
  `2026-08-23` (8 dias antes de hoje, 31/08) — bate exatamente com o aviso da
  própria tela ("serão usados os dados consolidados até oito dias atrás").
  Comportamento correto.

### Rotas destrutivas — inspecionadas, não clicadas (conforme instrução)
- **"Copiar para histórico"** — mencionada no texto de ajuda da seção
  "Transferência para o banco histórico". Não clicada.
- **"Apagar medições do histórico"** — sob o rótulo "CONFIRMAÇÃO PARA
  EXCLUSÃO", com campo de texto ao lado com placeholder "Digite APAGAR"
  (`#confirmacao-limpar-historico`) — **é o único ponto do sistema, em todo o
  teste, que pede confirmação textual explícita antes de uma ação
  destrutiva**, boa prática de segurança. Não preenchido, não clicado.
- **"Apagar dados gerados"** — botão na seção "Gerações realizadas". Não
  clicado.
- **"Consolidar histórico pendente"** (aba Sistema) e o auto-disparo já
  documentado em CT-03 — não clicado manualmente.
- **"Limpar histórico"** (aba Sistema, `btn-limpar`) — mesmo destino do botão
  de apagar medições. Não clicado.

Nenhuma dessas rotas foi acionada manualmente pelo agente.

---

### Painel Análises — estrutura observada (na única vez em que funcionou)

"Painel executivo por zona" traz, por zona: tendência do índice em 15/30/60 min, "Conforto nas últimas 24h", "Tempo contínuo no status atual", "Maior nível atingido hoje", "Minutos em Perigo/Emergência hoje", "Horário previsto do pico", "Sensores indisponíveis", "Equipamentos ligados", e um banner textual de recomendação. Abaixo, duas tabelas: "Percentual de tempo em cada condição térmica" e "Índice mínimo, médio e máximo por zona" (todas as 5 zonas, não só a selecionada). Não existe seletor de período dentro de Análises — só seletor de zona (`#zona-executivo`); "trocar período" pedido no roteiro não se aplica a este painel, que parece ser sempre sobre janelas fixas (15/30/60 min, 24h, hoje).

---

## Retomada (3ª sessão, 31/08) — nota inicial

As duas tentativas anteriores morreram por limite de sessão da conta, não por
erro do agente. Ao reabrir a tela de Usuários (`/usuarios/`) para começar o
Bloco 7, encontrei um resíduo: já existia `ZZTESTE-ct` (login `zzteste-ct`,
id 15, perfil Operador, Ativo, "Último login: Nunca") — quase certamente
criado pela 2ª tentativa, que morreu antes de atualizar o `STATUS_CT.md` (que
ainda dizia "Bloco 7 vai criar o usuário", sem registrar que já tinha
criado). Como não havia registro do momento da criação (segredo mostrado?
vazou?), optei por **excluir esse resíduo e recriar do zero**, para poder
observar o próprio instante da criação — que é justamente o que o Bloco 7
pede para verificar. Prefixo `ZZTESTE` respeitado, dentro da regra de ouro
(só mexi em registro que a própria rodada CT criou).

### Nota de método — cliques por `ref` não confiáveis nesta sessão; calibração de coordenada necessária na SPA

Logo na exclusão do resíduo, `computer` com `ref` (ex.: botão "Excluir" do
usuário) clicava consistentemente fora do alvo — o evento de clique chegava
com `event.target === HTML`, não no botão, mesmo com o `ref` resolvido para
a coordenada aparentemente certa. Cliques por **coordenada, no referencial
do próprio screenshot** (`computer` com `coordinate`, não `ref`) funcionaram
de primeira nas páginas administrativas simples (`/usuarios/*`,
`/minha-senha`) — ali o screenshot está em escala ~1:1 (menos DPR) com a
página.

Na **SPA principal** (`http://127.0.0.1:5001/`, Dashboard e demais abas por
JS), porém, nem `ref` nem coordenada direta do screenshot acertavam o alvo:
um clique em "Análises" (centro lógico, via `getBoundingClientRect()`,
em `x=283, y=90`) caiu de fato em `x=832, y=262` — um fator de ~5,1x entre a
coordenada pedida e o ponto realmente clicado (confirmado prendendo um
listener de `click`/`pointerdown` em `document` e lendo `clientX/clientY`
reais do evento). Calibrando (`coordenada_tela = coordenada_lógica / 5,08`,
obtida via `getBoundingClientRect()` de cada botão de aba, dividido por
5,08), os cliques passaram a acertar de forma consistente (confirmado via
`aria-selected`/classe `.ativo` depois de cada clique). Provável causa:
`devicePixelRatio` da aba estava `2`, e a combinação disso com a forma como
o layout da SPA calcula largura pode estar produzindo um descasamento entre
o screenshot exibido e o frame que `computer` usa para resolver cliques —
não investiguei a causa raiz (fora do escopo: sou agente de observação do
produto, não da ferramenta), só deixo a calibração registrada para quem
retomar. **Regra prática para continuar:** antes de clicar em qualquer coisa
na SPA principal por coordenada, pegue `getBoundingClientRect()` do alvo via
`javascript_tool`, divida x e y por ~5,08, e confirme o resultado (classe
`.ativo`, `aria-selected`, ou texto renderizado) depois do clique — não
confie no screenshot para mirar diretamalmente nessa parte do app. Nas
páginas `/usuarios/*` e `/minha-senha` não é preciso — coordenada direta do
screenshot funciona.

Um efeito colateral do mesmo descasamento: **screenshots da SPA principal em
viewport mobile mostraram cartões aparentemente cortados na borda direita**
(a "Zona monitorada" e o gráfico pareciam vazar para fora da tela). Medindo
via `getBoundingClientRect()` de cada `.painel`, porém, nenhum elemento
excedia `window.innerWidth` — **não há overflow real**, é só o mesmo
artefato de renderização/escala do screenshot nessa página específica.
Registrado para não induzir quem retomar a reportar uma responsividade
quebrada que a própria página não tem (ver Bloco 8, Responsividade).

---

## Bloco 7 — Usuários e senha

Lista inicial (após excluir o resíduo `ZZTESTE-ct` id 15): só `Admin` e
`Mariano de Angelo` (`mspa`), como esperado pelo roteiro.

### Criação, edição, ativação/desativação — ciclo completo, tudo funcionou

Ao contrário do CT-07 (zona), o CRUD de usuário **funciona de ponta a
ponta**, sem nenhuma falha silenciosa:
- **Criar `ZZTESTE-ct`** (perfil "Operador", não administrador): o
  formulário `/usuarios/novo` exige senha no próprio ato de criação (campo
  "Senha", `type=password`, `required`, sem `minlength` no HTML — validado
  só pelo servidor) — **diferença de estrutura real vs. o que o roteiro do
  Bloco 7 presumia** (o roteiro esperava senha temporária gerada já na
  criação; na prática quem cria escolhe a senha inicial, e a senha
  temporária de uso único é coisa do botão **Redefinir senha**, à parte —
  ver abaixo). Antes de submeter, o formulário pede confirmação num modal
  próprio do SharedAuth ("Criar usuário — Criar este usuário?"), não
  `window.confirm()` nativo. Confirmado, o usuário aparece na lista com
  status Ativo.
- **Editar `ZZTESTE-ct`**: troquei o perfil para "Técnico" — modal de
  confirmação ("Salvar alterações — Salvar as alterações deste usuário?"),
  confirmado, lista atualizada corretamente (`Técnico` no lugar de
  `Operador`). Funcionou de primeira.
- **Desativar**: desmarcar "Conta ativa" + salvar + confirmar modal → status
  vira "Inativo" na lista. Funcionou.
- **Reativar**: mesmo caminho, marcar de novo → volta a "Ativo". Funcionou.

Todas as quatro operações tiveram efeito real e imediato, confirmado via
`get_page_text` da lista depois de cada uma — nenhum sinal do padrão
"clique não faz nada" do CT-07. Isso é evidência de que o defeito do CT-07 é
específico do formulário de zona (`#form-zona`), não um problema geral de
manipulação de formulário no sistema.

### Redefinir senha pelo botão do admin — segredo mostrado uma única vez, sem vazamento

Cliquei "Redefinir senha" para `ZZTESTE-ct`. O modal de confirmação já
avisa o comportamento com clareza: *"Redefinir a senha de ZZTESTE-ct? O
sistema vai gerar uma senha temporária, mostrada uma única vez."* Confirmado
o modal, o resultado:

- A senha apareceu em um banner destacado no topo da lista de usuários:
  *"Senha temporária de zzteste-ct"* seguida do valor em texto monoespaçado
  (ex.: `cRoH4bQKUTL7`) e do aviso *"Anote agora: ela não será mostrada de
  novo. Quem entrar com ela terá de trocá-la antes de usar o sistema."*
- **Não vazou por URL:** a URL depois da ação é
  `http://127.0.0.1:5001/usuarios/16/redefinir-senha` (confirmado via
  `location.href`) — só o caminho da rota, nenhum parâmetro, nenhuma query
  string com o segredo.
- **Não é flash + redirect:** a página com a senha é a própria resposta do
  `POST` renderizada diretamente (sem redirecionamento HTTP 302 antes dela)
  — ou seja, o servidor não precisou passar o segredo pela sessão assinada
  do Flask (`flash()`) para exibi-lo depois de um redirect; ele veio direto
  no corpo da resposta do próprio `POST`. Isso é o desenho mais seguro
  possível para esse tipo de mensagem de uso único, exatamente o que o
  roteiro pedia para verificar.
- **Não reaparece ao "recarregar":** naveguei de novo para a mesma URL
  (`GET /usuarios/16/redefinir-senha`) e o servidor respondeu **405 Method
  Not Allowed** (rota só aceita `POST`) — página de erro genérica do Flask,
  sem nenhum resquício do segredo. Uma nova `GET /usuarios/` também não
  mostra mais o banner. A senha realmente aparece uma única vez.
- `document.cookie` não continha o valor da senha (o cookie de sessão é
  `HttpOnly` — não dá para ler via JS do lado do cliente; não consegui
  inspecionar o `Set-Cookie` bruto com as ferramentas disponíveis, mas a
  ausência de redirect já é evidência forte de que `flash()` não foi usado
  aqui).
- **"Conta fica com troca pendente":** não verificável pela tela (não há
  indicador visual de "troca pendente" nem na lista nem na edição do
  usuário) — o único sinal é o texto do próprio aviso ("terá de trocá-la
  antes de usar o sistema"). Confirmar de fato exigiria logar como
  `ZZTESTE-ct`, proibido pelo contrato. **Registrado como não verificado.**

### `/minha-senha` como `mspa` — validação testada sem concluir a troca

Formulário com três campos (`Senha atual`, `Nova senha`, `Confirme a nova
senha`), todos `required`, `Nova senha`/`Confirme a nova senha` com
`minlength=8` nativo, `autocomplete` correto (`current-password` /
`new-password` respectivamente) — boa prática, evita que o gerenciador de
senha do navegador confunda o campo de senha nova com um de login.

Para testar a validação **sem risco de mudar a senha real de `mspa`** (o
agente não tem — e não deveria ter — a senha atual de `mspa`), preenchi
`Senha atual` com um valor deliberadamente errado
(`ZZTESTEsenhaerrada`) e `Nova senha`/`Confirme a nova senha` com um valor
válido e coincidente (`ZZTESTEnovasenha123`). Resultado: `POST /minha-senha
→ 200 OK`, página re-renderizada com a mensagem clara em português **"Senha
atual inválida."**, campos de senha limpos (não ecoam o valor digitado). A
senha real de `mspa` **não foi alterada** — a validação do lado do servidor
bloqueou antes de aplicar qualquer mudança, que é exatamente o
comportamento esperado e a única forma seguro de exercitar esse endpoint
sem saber a senha real. Não testei o caminho "senha atual correta mas nova
senha ≠ confirmação" pelo mesmo motivo (exigiria a senha real).

### Exclusão da própria conta e limpeza final

- **Excluir a própria conta (`mspa`):** a linha de `mspa` na lista de
  usuários **não tem botão "Excluir"** (só `Editar` e `Redefinir senha`) —
  a tela já impede a ação na origem, sem precisar tentar. **Decidi não
  tentar a rota direta** (`POST /usuarios/1/excluir`) para forçar a
  verificação server-side: o risco (excluir de fato a conta real do
  mantenedor, se houver qualquer falha de autorização) supera o valor de
  confirmar algo que a UI já nega de forma consistente. Registrado como
  "recusa confirmada pela ausência do controle na UI; rota direta
  deliberadamente não tentada".
- **Excluir `ZZTESTE-ct`:** botão "Excluir" na lista → modal de confirmação
  do SharedAuth ("Excluir o usuário ZZTESTE-ct? Esta ação não pode ser
  desfeita.") → confirmado → usuário sumiu da lista. **Limpeza concluída,
  zero resíduo do Bloco 7.**

### Duas verificações pedidas pelo orquestrador

**1. Trilha de auditoria com `login`/`perfil` = "unknown" — não há tela para
confirmar isso no próprio ConfortoTermico.** Procurei ativamente por uma
tela de auditoria/log: a aba "Sistema" da SPA só tem Sensores, Banco de
dados (sem contagens, só "gravar a cada X minutos" e o botão "Consolidar
histórico pendente") e Servidor SMTP/Cálculos — nenhuma seção de log ou
auditoria. Tentei rotas prováveis (`/auditoria`, `/auditoria/`, `/logs`,
`/sistema/auditoria`, `/admin/auditoria`, `/api/auditoria`,
`/api/auditoria/eventos`, `/api/logs`, `/api/sistema/auditoria`,
`/api/eventos-auditoria`, `/api/sistema/logs`, `/api/auditoria/login`) —
todas devolveram 404. **Conclusão: o ConfortoTermico não tem, hoje, nenhuma
tela ou endpoint de auditoria acessível pela interface web** — o evento
`LOGIN_SUCESSO` com `usuario.login`/`usuario.perfil` = `"unknown"` (visto
pelo orquestrador via `docker logs`) só é visível por fora da aplicação, via
log bruto do contêiner. Não pude confirmar o formato exato do registro pela
própria tela porque essa tela não existe — o achado abaixo (CT-12) registra
os dois problemas: o dado incompleto no registro de auditoria, **e** a
ausência de qualquer superfície na UI para revisá-lo.

**2. Usuário `valida-sessao` (id 14) — não encontrado no ConfortoTermico.**
A lista de usuários deste sistema, antes e depois da minha rodada, sempre
teve só 2 ou 3 contas (`Admin`, `mspa`, e o `ZZTESTE-ct` que eu mesmo criei
e removi) — nunca um quarto usuário. Tentei `/usuarios/14/editar`
diretamente: a resposta é um redirecionamento para a lista de usuários (id
inexistente), confirmando que **não existe usuário com id 14 no
ConfortoTermico**. Verifiquei a contagem de linhas da tabela via DOM
(`document.querySelectorAll('table tbody tr').length`) para excluir
paginação escondendo a conta — só 2 linhas, sem paginação real. **Não
registro isso como Observação por não ter conseguido confirmar**: o resíduo
`valida-sessao` citado pode pertencer a outro dos quatro sistemas (o
`README.md` já documenta esse padrão para MegaSena e ControleRendaVariavel,
não para ConfortoTermico) ou já ter sido removido entre a leitura do log
pelo orquestrador e esta verificação. Repasso a divergência para o
orquestrador reconciliar entre os quatro relatórios, em vez de forçar um
achado que não consegui sustentar pela própria tela do sistema.

### [CT-10] Botão Voltar do navegador não desfaz troca de aba — sai do app inteiro
- **Severidade:** Melhoria
- **Onde:** toda a navegação por abas da SPA principal (`http://127.0.0.1:5001/`)
- **Passos:** 1. Na SPA, clicar em várias abas em sequência (Análises, Histórico, Operação, Cadastro, Configurações, Sistema, Dados de entrada) — confirmado via `location.href` que a URL nunca muda (`http://127.0.0.1:5001/` fixo, `history.length` não cresce com os cliques de aba). 2. Antes disso, ter navegado para outra página real do sistema (`/health`). 3. A partir de uma aba qualquer da SPA, acionar "Voltar" do navegador.
- **Esperado:** ou o Voltar não faz nada de relevante dentro do app (aceitável, já que não há estado de URL por aba), ou volta para a aba visitada anteriormente.
- **Obtido:** o Voltar ignora completamente a navegação por abas (que nunca gerou entradas de histórico) e pula direto para a última página *de verdade* visitada antes de entrar na SPA — neste teste, `/health`, uma página de JSON cru sem relação nenhuma com o que o usuário estava fazendo. Num uso real, isso significa: um usuário que troca de aba várias vezes dentro do ConfortoTermico e aperta Voltar pensando em desfazer a última troca de aba **sai do sistema inteiro** de uma vez, indo parar em uma página completamente alheia (o que quer que tenha aberto antes do ConfortoTermico no histórico daquela aba do navegador) — sem aviso, sem confirmação, sem meio-termo.
- **Evidência:** `history.length` não incrementa ao clicar em abas (confirmado antes/depois de 6 cliques de aba); `navigate({url:"back"})` a partir da SPA levou a `http://127.0.0.1:5001/health` (título da aba "127.0.0.1:5001/health"), não a nenhuma aba anterior do app.
- **Consequência adicional (mesmo achado, ver Bloco 8):** como a URL é sempre `http://127.0.0.1:5001/` para as 8 abas, **não existe like direto para abrir o sistema numa aba específica** (ex.: mandar alguém direto para "Operação" por link) — sempre cai no Dashboard.
- **Vale para os outros sistemas?** talvez — MegaSena usa SharedAuth também; vale conferir se tem telas de aba única semelhantes. ControleBancario (Django+HTMX) e ControleRendaVariavel provavelmente navegam por URL de verdade, então este padrão específico (aba única sem `pushState`) é mais provável de ser exclusivo do ConfortoTermico.

### [CT-11] "Último login" na tela de Usuários mostra timestamp ISO cru, não o formato pt-BR do resto do sistema
- **Severidade:** Inconsistência
- **Onde:** `/usuarios/` — coluna "ÚLTIMO LOGIN"
- **Passos:** 1. Abrir a lista de usuários. 2. Ler a coluna "Último login" para `Admin` e `mspa`.
- **Esperado:** mesmo padrão `dd/mm/aaaa hh:mm` usado no restante do sistema (confirmado em Bloco 2: Histórico mostra `30/08/2026`; em Bloco 6: campo de data da geração usa `dd/mm/aaaa`).
- **Obtido:** a coluna mostra o timestamp em formato ISO 8601 bruto — `2026-08-30T14:50:36` (Admin), `2026-08-31T00:36:20` (mspa) — sem nenhuma formatação para pt-BR, aparentemente o valor devolvido pela API/backend impresso direto no HTML sem passar por formatação de data no template ou no cliente.
- **Evidência:** HTML/texto da tabela de usuários, coluna 5, ambas as linhas.
- **Vale para os outros sistemas?** talvez — vale conferir se a mesma tela de usuários do SharedAuth (compartilhada entre os 4 sistemas, pelo que consta no README) tem o mesmo problema nos outros três; se a tela de usuários for código compartilhado, é provável que sim.

### [CT-12] Registro de auditoria de login não sabe dizer quem logou — e não há tela para revisá-lo
- **Severidade:** Defeito
- **Onde:** evento de auditoria `LOGIN_SUCESSO` (visto via `docker logs conforto-termico-ict-1`, fora da aplicação) — ausência de superfície de auditoria em toda a aplicação web
- **Passos:** 1. (Feito pelo orquestrador, fora do navegador) Ler `docker logs` do contêiner e localizar um evento `LOGIN_SUCESSO`. 2. (Feito por mim) Procurar uma tela de auditoria/log dentro do ConfortoTermico para confirmar o mesmo formato pela própria interface: aba "Sistema" da SPA (sem seção de log), rotas prováveis `/auditoria`, `/logs`, `/sistema/auditoria`, `/admin/auditoria` (todas 404) e endpoints de API prováveis `/api/auditoria`, `/api/auditoria/eventos`, `/api/logs`, `/api/sistema/auditoria`, `/api/eventos-auditoria`, `/api/sistema/logs`, `/api/auditoria/login` (todas 404).
- **Esperado:** um registro de auditoria de login deveria identificar quem logou (login e perfil reais) e, idealmente, deveria existir alguma forma de o administrador revisar essa trilha pela própria interface do sistema.
- **Obtido:** dois problemas distintos, registrados juntos por serem a mesma trilha:
  1. **Dado incompleto:** o bloco `usuario` do evento grava `login: "unknown"` e `perfil: "unknown"` mesmo quando o `id` do usuário é conhecido (`id: 1`) e o login real aparece a poucos bytes de distância, dentro de `detalhes` (`"detalhes": {"usuario_id": 1, "login": "mspa"}`). Ou seja, a informação existe e foi capturada pelo próprio evento — só não foi propagada para o campo que deveria descrever "quem fez isso".
  2. **Sem superfície na UI:** não existe, em nenhuma tela do ConfortoTermico, um lugar para ver esses eventos de auditoria — nem endpoint de API, nem página. A trilha de auditoria só existe no log bruto do processo dentro do contêiner Docker, inacessível a qualquer usuário (mesmo administrador) que só use a aplicação web.
- **Evidência:** trecho de log fornecido pelo orquestrador: `"usuario": {"id": 1, "login": "unknown", "perfil": "unknown"}, "detalhes": {"usuario_id": 1, "login": "mspa"}`; lista de rotas 404 tentadas por mim, acima.
- **Não verificado por mim diretamente:** não tenho acesso a `docker logs` nesta sessão (só ferramentas de navegador) — o trecho de log é evidência de segunda mão, fornecida pelo orquestrador, mas o item 2 (ausência de tela) eu confirmei em primeira mão.
- **Vale para os outros sistemas?** sim, provavelmente — se a auditoria for parte do SharedAuth (biblioteca compartilhada pelos 4 sistemas, pelo que registra o README), o mesmo bug de "unknown" no campo `usuario` tende a se repetir nos outros três; vale o orquestrador cruzar com os relatórios de MS/CB/RV.

### Limpeza do Bloco 7
Nenhum resíduo: `ZZTESTE-ct` (id 15, resíduo de tentativa anterior) e
`ZZTESTE-ct` (id 16, recriado por mim) foram ambos excluídos e confirmados
fora da lista. Lista final de usuários: `Admin`, `mspa` — igual ao estado
antes do Bloco 7.

---

## Bloco 8 — Bateria transversal

- **Console limpo:** naveguei pelas 8 abas da SPA (Dashboard, Análises,
  Histórico, Operação, Cadastro, Configurações, Sistema, Dados de entrada)
  numa sessão recém-carregada e comparei `read_console_messages` antes/depois:
  **nenhum erro novo** apareceu ao trocar de aba. Os únicos erros de console
  vistos durante o Bloco 8 (um 405 e treze 404) são resíduo das minhas
  próprias sondagens de diagnóstico (`fetch` em rotas de auditoria
  inexistentes, `GET` deliberado numa rota só-`POST`) — não são erros
  gerados pela navegação normal do produto. **Console limpo confirmado.**
- **Aba única / URL / Voltar:** ver CT-10 acima — URL nunca muda entre as 8
  abas, `history` não ganha entradas por troca de aba, Voltar do navegador
  sai do app inteiro em vez de voltar uma aba, e não há como linkar direto
  para uma aba específica.
- **HTMX:** não se aplica — o ConfortoTermico não usa HTMX; a troca de
  conteúdo é feita por JavaScript próprio trocando `display` de painéis
  (ver Bloco 1). As telas administrativas (`/usuarios/*`) são navegação de
  página inteira tradicional (confirmado: `POST /usuarios/16/redefinir-senha`
  não usa redirect, mas ainda é uma troca de documento completa, não
  fragmento).
- **Formato pt-BR:** números seguem pt-BR consistentemente na SPA (`81,88`,
  `18,69`, `34,04`, `23,29` — vírgula decimal, confirmado no Dashboard).
  Datas de filtro usam `dd/mm/aaaa` (Histórico, Dados de entrada — já
  confirmado em Blocos 2 e 6). A exceção é a tela de Usuários (CT-11,
  acima): timestamp ISO cru na coluna "Último login". CSV de exportação usa
  ponto decimal (já registrado no CT-09/Bloco 6) — aceitável para arquivo de
  máquina, mas outra inconsistência de formato já catalogada.
- **`/health`:** `GET /health` → `200 OK`, corpo
  `{"servico":"ict","status":"ok"}`. Correto e coerente com o nome interno
  do serviço (`ict` = interface, conforme o prompt).
- **Validação de formulário:** `/minha-senha` tem os três campos
  `required`, `minlength=8` nativo nos dois campos de senha nova,
  `autocomplete` correto (`current-password`/`new-password`). Submissão com
  senha atual errada (mas nova senha válida e confirmada) foi recusada pelo
  servidor com mensagem clara em português ("Senha atual inválida."), sem
  alterar a senha real — testado com segurança justamente porque o valor da
  "senha atual" usado era propositalmente errado (ver Bloco 7). Validações
  de campos de zona/equipamento/SMTP já cobertas em Blocos 3, 5 e 6
  (CT-08, e os campos somente-leitura/select fechado do Bloco 6).
- **Filtro, ordenação e paginação:** existem e funcionam. Histórico tem
  paginação textual "Leituras N-M de TOTAL" com botões "Retroceder/Avançar"
  (já testado em Bloco 2 com período de 26 anos, ~8930 leituras, resposta
  rápida). Cadastro tem filtro "Todas as zonas / Somente ativas / Somente
  inativas". Não testei "sobrevive ao Voltar" à parte — já coberto pelo
  CT-10: como trocar de aba/filtro não gera nova entrada de histórico,
  Voltar não tem como restaurar ou perder um filtro específico da aba, ele
  simplesmente sai do app.
- **F5 depois de gravar:** **não verificado com segurança plena** — as
  ferramentas de navegador disponíveis não têm uma ação de "recarregar a
  página atual" distinta de "navegar para uma URL nova" (`navigate` sempre
  dispara uma requisição nova, não o reload de documento que ativa o aviso
  nativo "Confirmar reenvio de formulário" do navegador), e esse aviso
  nativo não é roteável por script do jeito que os modais próprios do
  SharedAuth são. Ainda assim, uma evidência indireta importante: confirmei
  via `location.href` que pelo menos uma rota de escrita
  (`POST /usuarios/<id>/redefinir-senha`) **não usa redirect** — a resposta
  do `POST` é renderizada diretamente na mesma URL. Isso significa que, se
  um administrador de verdade apertar F5 logo depois de redefinir uma senha,
  o navegador vai warnar sobre reenviar o formulário — e, se ele confirmar
  sem entender o aviso, a ação se repete (gera **outra** senha temporária
  silenciosamente, sobrescrevendo a primeira sem que o admin perceba que
  trocou). Registro isso como risco plausível, evidenciado em parte, mas
  **não reproduzido de ponta a ponta** por limitação das ferramentas
  disponíveis, não por decisão de escopo.
- **Autorização:** `mspa` é administrador único testado nesta rodada (a
  sessão emprestada não permite trocar de conta, e logar como `ZZTESTE-ct`
  é proibido pelo contrato). Não há, à vista, nenhuma tela do ConfortoTermico
  a que o próprio `mspa` não tenha acesso — logo, o teste "tentar a rota
  direta só onde `mspa` não tem acesso" não tem onde ser aplicado nesta
  conta. **Não verificado, por falta de uma conta de perfil restrito
  disponível dentro das regras do contrato.**
- **Responsividade:** testado com `resize_window` preset mobile (375x812)
  em duas telas:
  - **Dashboard (SPA):** o menu de abas reflui corretamente em grupos
    rotulados (Monitoramento / Operação / Administração / Dados), cada
    grupo empilhando os botões verticalmente — bom comportamento responsivo.
    Os cartões de conteúdo (`.painel`) foram verificados via
    `getBoundingClientRect()` e **nenhum excede `window.innerWidth`** — sem
    overflow horizontal real, apesar de o screenshot desta página específica
    ter mostrado (falsamente) cartões cortados na borda direita (ver nota de
    método no início do Bloco 7 — artefato de escala do screenshot nessa
    página, não bug do produto).
  - **Usuários (`/usuarios/`):** a tabela de contas é mais larga que a tela
    (`scrollWidth` 822 contra `innerWidth` 375) e **rola horizontalmente
    dentro do próprio cartão** (`overflow-x: auto` no contêiner da tabela,
    barra de rolagem visível no rodapé do cartão) — o corpo da página em si
    não ganha rolagem horizontal. Padrão correto de "conteúdo largo rola no
    próprio contêiner".
- **Acessibilidade rasa:** na tela de Usuários, todo campo visível tem rótulo
  associado (só os `input[type=hidden]` de CSRF token ficam sem rótulo, o
  que é esperado — não são controles visíveis) e todo botão/link tem texto
  acessível (nenhum botão "mudo" encontrado). Achado de atenção: o CSS
  global (`style.css`) tem uma regra `:focus { border-color:
  var(--cor-acento); outline: none; }` — remove o contorno de foco padrão do
  navegador e substitui só por uma mudança de cor de borda. Isso pode ser
  insuficiente como indicador de foco por teclado em elementos sem borda
  visível por padrão, ou num tema escuro onde a diferença de cor é sutil.
  Não fiz varredura de contraste numérica (fora do escopo de uma checagem
  "rasa"); registro como ponto de atenção de baixa confiança, não como
  defeito fechado.

### [CT-13] `:focus` sem contorno nativo, substituído só por cor de borda
- **Severidade:** Melhoria
- **Onde:** `static/css/style.css`, regra global `:focus`
- **Passos:** 1. Buscar no CSS servido (`fetch('/static/css/style.css')`) por regras `:focus`. 2. Encontrar `:focus { border-color: var(--cor-acento); outline: none; }` sem nenhuma regra alternativa de contorno/box-shadow visível para elementos sem borda própria.
- **Esperado:** foco de teclado sempre visível com contraste suficiente, idealmente com contorno (`outline`/`box-shadow`) além ou no lugar de mudança de cor de borda.
- **Obtido:** `outline: none` global em `:focus`, compensado só por `border-color`. Funciona bem em campos com borda visível (inputs, selects); é potencialmente insuficiente em elementos sem borda visível por padrão (links, alguns botões) e no tema escuro do app, onde a troca de cor pode ser pouco perceptível para quem navega por teclado.
- **Evidência:** trecho do CSS citado acima.
- **Vale para os outros sistemas?** talvez — se `style.css` for parcialmente compartilhado entre os 4 projetos (base de engenharia comum), vale checar o mesmo padrão nos outros três.

---

## Limpeza final e estado ao fim da rodada

Nenhum resíduo `ZZTESTE` em nenhuma tela do ConfortoTermico. Todo campo de
configuração tocado ao longo de toda a rodada (Blocos 3, 5, 6, 7) foi
restaurado e confirmado de volta ao valor original. As 5 zonas e 42
equipamentos reais não foram alterados em nenhum momento. As cinco rotas
destrutivas listadas no prompt nunca foram acionadas deliberadamente pelo
agente (a única exceção é a rota de consolidação que dispara sozinha na
navegação comum, já documentada como CT-03, fora do controle do agente).

## Adendo de correção — 01/09/2026

CT-05, CT-07 e CT-09 foram corrigidos. O exportador CSV passou a usar resposta
streaming e leitura em lotes; os salvamentos seguros de zona/equipamento não
empilham confirmação sobre o modal; leituras vencidas são identificadas pelo
backend e apresentadas como desatualizadas, com horário explícito e sem estado
térmico enganoso. A regressão global das linhas de edição já havia sido
corrigida no ControleBancario pelo contrato compartilhado de `is-collapsed`.

Validação final: Ruff e 223 testes aprovados, serviços reconstruídos e
saudáveis, PostgreSQL verificado com 5 zonas, 2 usuários, 44.642 leituras e 6
execuções. O navegador interno alcançou a tela de login, mas não havia sessão
autenticada para repetir o fluxo visual; os três contratos alterados ficaram
cobertos por testes automatizados.
