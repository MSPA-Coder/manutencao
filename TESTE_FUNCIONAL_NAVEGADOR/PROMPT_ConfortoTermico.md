# Prompt do agente — ConfortoTermico (sigla CT)

Alvo: `http://127.0.0.1:5001`. Relatório: `RELATORIO_ConfortoTermico.md`.
Ler `README.md` deste diretório antes de começar: o contrato de execução vale
integralmente e não se repete aqui.

Software de mestrado para índices de conforto térmico animal (ITU, ITUV, IGNU).
Interface de aba única: um `index.html` com abas que trocam por JavaScript, e
telas separadas para usuários e senha. O `ict` é a interface; o `coletor` é um
serviço interno sem porta publicada. **O sistema opera em modo simulado e não
aciona equipamento físico** — acionar ventilador/nebulizador pela tela é
seguro.

## Bloco 1 — Varredura do menu

Abas, na ordem em que aparecem, agrupadas na barra lateral:

- **Monitoramento:** Dashboard · Análises · Histórico
- **Operação:** Operação
- **Administração:** Cadastro (zonas e equipamentos) · Configurações · Sistema
- **Dados:** Dados de entrada

Abrir cada aba, confirmar que carrega, que o conteúdo corresponde ao rótulo e
que a aba selecionada fica marcada. Registrar tempo perceptível de carga e
qualquer painel que apareça vazio sem explicar por quê. Anotar a estrutura real
encontrada — se divergir desta lista, a divergência já é um achado.

## Bloco 2 — Dashboard, Análises e Histórico (leitura)

Há 5 zonas, 42 equipamentos, 44.642 leituras e 65.088 medições no banco: as
telas devem ter o que mostrar.

- Dashboard: cartões por zona, índices calculados, estado dos equipamentos,
  atualização automática. Conferir se o índice exibido é coerente com a
  temperatura e umidade mostradas na mesma tela.
- Análises: painel executivo, tendências, comparação entre zonas. Trocar zona,
  trocar período, conferir se o gráfico muda de fato.
- Histórico: filtro por zona e período, resumo horário, agregados de 15 min.
  Pedir um período sem dados e ver o que a tela diz. Pedir período invertido
  (fim antes do início). Pedir período muito longo e medir a resposta.

Screenshot vale a pena aqui: gráfico é evidência visual.

## Bloco 3 — Cadastro de zonas e equipamentos (inclusão, alteração, exclusão)

É o CRUD principal do sistema. Ciclo completo com dado próprio:

1. Criar a zona `ZZTESTE Zona`, preenchendo espécie, quantidade e peso médio
   dos animais, área útil, densidade, latitude/longitude, altitude, cidade
   (código IBGE) e fuso.
2. Antes disso, tentar gravar com campos obrigatórios vazios, com quantidade
   de animais negativa, com peso zero, com latitude fora de -90..90 e com
   código IBGE inválido. Cada recusa (ou ausência de recusa) é um achado.
3. Editar a zona criada: mudar espécie e densidade, conferir se os limites e o
   cálculo de índice acompanham a mudança.
4. Criar dois equipamentos na zona `ZZTESTE` — um ventilador e um nebulizador
   — com modo de conexão, endereço de registrador, tipo, fator de escala.
   Testar endereço duplicado e fator de escala zero.
5. Ativar e desativar a zona; ver o efeito no Dashboard e na Operação.
6. Excluir os equipamentos e depois a zona. Conferir se a exclusão de zona com
   equipamento vinculado é barrada ou cascateia — e se o que acontece é o que
   a tela promete.

**Não tocar nas 5 zonas preexistentes.**

## Bloco 4 — Operação

- Supervisão e operação: escolher a zona `ZZTESTE` (criá-la de novo se já
  apagou) e rodar um ciclo manual. Conferir "Dados processados do ciclo".
- Equipamentos da zona: ligar e desligar ventilador e nebulizador; conferir o
  par desejado/confirmado, o limite de umidade do nebulizador e o que a tela
  faz quando o estado confirmado não acompanha o desejado.
- Eventos de operação: conferir se a ação acima gerou evento e se o evento
  descreve o que aconteceu.
- Status: próximo ciclo, último ciclo, sensores indisponíveis, qualidade da
  leitura.

## Bloco 5 — Configurações e Sistema

- Preferências do app: intervalo de leitura, habilitar sons, habilitar
  equipamentos, modo simulado por zona. **Anotar o valor original de cada
  campo antes de mexer e restaurá-lo ao final do bloco** — são ajustes globais.
- Alertas por e-mail e servidor SMTP: **não configurar servidor real e não
  disparar e-mail.** Conferir apenas a validação dos campos (host vazio, porta
  fora de faixa, e-mail malformado) e se a senha do SMTP aparece mascarada e
  não volta em texto claro no HTML da página. Ver o HTML por `get_page_text`
  ou `read_page` — segredo que volta ao navegador é achado de segurança.
- Sensores, banco de dados, cálculo dos parâmetros: conferir o que a tela
  informa e se bate com a realidade (5 zonas, 42 equipamentos).

## Bloco 6 — Dados de entrada

Gerador de séries sintéticas. É onde mora o risco.

- Gerar uma execução pequena para a zona `ZZTESTE` apenas: período curto,
  resolução grossa. Conferir a listagem "Gerações realizadas".
- Exportar CSV da execução gerada e conferir o conteúdo: separador, decimal,
  formato de data, cabeçalho.
- Referências e configurações por zona: conferir leitura.

**Rotas destrutivas — não acionar em hipótese nenhuma:**
`/api/reset`, `/api/dados-entrada/apagar-historico`,
`/api/dados-entrada/copiar-para-historico`, `/api/consolidar-historico` e
`/api/zonas/<id>/consolidar-historico`. As duas primeiras apagam dados reais;
as três últimas escrevem no banco histórico de 44 mil leituras. Registrar que
existem, onde ficam na interface, se a tela avisa do risco e se pede
confirmação — **inspecionar sem clicar**.

## Bloco 7 — Usuários e senha

Telas: `/usuarios/`, `/usuarios/novo`, `/usuarios/<id>/editar`,
`/usuarios/<id>/excluir`, `/usuarios/<id>/redefinir-senha`, `/minha-senha`.

- Listar usuários: devem aparecer `mspa` e `Admin`.
- Criar `ZZTESTE-ct` com perfil não administrador. Conferir se a criação
  devolve senha temporária mostrada uma única vez, e se ela **não** aparece em
  mensagem flash (a sessão do Flask é assinada, não cifrada — se a senha
  temporária passar por flash, é achado grave de segurança; conferir também se
  ela não fica no HTML de páginas seguintes nem na URL).
- Editar o perfil de `ZZTESTE-ct`; desativar e reativar.
- Redefinir a senha de `ZZTESTE-ct` pelo botão do admin: conferir que a senha
  temporária aparece uma vez só, que recarregar a página não a mostra de novo,
  e que a conta fica com troca pendente.
- **Não fazer login como `ZZTESTE-ct`** (contrato: agente não digita senha em
  tela de login). Registrar como não verificado o que depender disso.
- `/minha-senha` como `mspa`: abrir, conferir que a tela existe e valida, mas
  **não concluir a troca** — mudaria a senha do mantenedor.
- Tentar excluir a própria conta (`mspa`): a tela deve recusar. Depois excluir
  `ZZTESTE-ct` e confirmar que sumiu da lista.

## Bloco 8 — Bateria transversal

Conforme a seção "Bateria transversal" do `README.md`. Neste sistema, olhar com
atenção especial: a aba única não muda a URL — conferir se o botão Voltar do
navegador faz algo sensato e se dá para chegar direto a uma aba por link.
