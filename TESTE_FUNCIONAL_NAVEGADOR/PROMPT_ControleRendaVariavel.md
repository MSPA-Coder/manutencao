# Prompt do agente — ControleRendaVariavel (sigla RV)

Alvo: `http://127.0.0.1:5301`. Relatório: `RELATORIO_ControleRendaVariavel.md`.
Ler `README.md` deste diretório antes de começar: o contrato de execução vale
integralmente e não se repete aqui.

Acompanhamento pessoal de ações e opções: posições, transações, proventos,
cotações, risco, performance e exposição. **Não é plataforma de negociação** —
nada aqui envia ordem para lugar nenhum. O banco local tem dado real: 21
posições, 19 transações, 100 proventos, 28 movimentos, 5 posições de opção,
31 tickers, 5 corretoras, 3 carteiras e 7.329 registros de histórico de
cotação.

Regras de domínio que a interface deve respeitar, e que valem como critério de
teste:

- Toda posição pertence a uma carteira.
- **Carteira simulada serve só para insight:** não gera movimento nem
  transação, não consolida entrada nova e **não pode ser encerrada**. Se a tela
  deixar, é Defeito.
- Totais ficam separados **por moeda** e **por natureza** (real × simulada).
  Somar real com simulado, ou BRL com USD, é Defeito.
- Ticker de referência alimenta comparador e risco, mas **não é negociável**.

## Bloco 1 — Varredura do menu

Mega-menu superior, por grupo:

- **Carteira:** Ações (`/positions`) · Opções (`/options`) ·
  Transações (`/transactions`) · Proventos (`/dividends`)
- **Análise:** Risco (`/risk`) · Performance mensal (`/performance`) ·
  Exposição por ativo (`/analysis/exposure-asset`) · por corretora
  (`/analysis/exposure-broker`) · por mercado (`/analysis/exposure-market`)
- **Mercado:** Histórico de cotações (`/quotes`)
- **Cadastros:** Carteiras (`/tables/portfolios`) · Corretoras
  (`/tables/brokers`) · Tickers (`/tables/tickers`) · Vencimentos
  (`/tables/options/expirations`) · Contratos (`/tables/options/contracts`)
- **Sistema:** Configurações (`/settings`) · Usuários (`/users`)
- Na barra: pulso do coletor, **alternar privacidade de valores**,
  Minha senha (`/minha-senha`), Sair

Abrir cada grupo e cada item, confirmar carga, marcação do item corrente e
abertura/fechamento do mega-menu. Registrar a estrutura real encontrada.

## Bloco 2 — Cadastros (inclusão, alteração, exclusão)

Sempre com registro próprio prefixado `ZZTESTE`:

1. **Carteira** `ZZTESTE Real` e **carteira simulada** `ZZTESTE Simulada`:
   criar as duas, editar, e guardar para os blocos seguintes.
2. **Corretora** `ZZTESTE Corretora`: criar, editar, excluir.
3. **Ticker** `ZZTESTE4`: criar, editar, marcar como referência e desmarcar.
   Conferir se ticker de referência aparece bloqueado para negociação.
4. **Vencimento** e **contrato** de opção `ZZTESTE`: criar, editar, excluir.
5. **Tickers da carteira** (`/tables/portfolios/<id>/tickers`): vincular e
   desvincular o `ZZTESTE4` da carteira de teste.

Antes de cada gravação válida: enviar em branco, com código duplicado, com
texto além do limite, com número negativo onde não cabe. Testar exclusão de
cadastro **em uso** (corretora com transação, ticker com posição): deve barrar
com mensagem clara.

**Nunca editar nem excluir os 3 portfólios, 5 corretoras e 31 tickers reais.**

## Bloco 3 — Posições e transações (o núcleo)

- **Transação** (`/transactions/new`): criar compra de `ZZTESTE4` na carteira
  `ZZTESTE Real`, com quantidade, preço, taxas e data. Conferir se gera ou
  atualiza a posição. Editar a transação e conferir se a posição acompanha.
  Excluir e conferir se a posição volta ao que era.
- **Preço médio:** fazer duas compras a preços diferentes e **conferir o preço
  médio na mão**. Depois uma venda parcial e conferir quantidade, preço médio e
  resultado realizado. Divergência aqui é Defeito.
- **Posição** (`/positions/new`, `/edit`, `/close`, `/delete`): criar posição
  direta, editar, ver os movimentos (`position_movements`), encerrar
  (`/close`) e conferir o resultado apurado. Excluir ao final.
- **Carteira simulada:** repetir a criação de posição na `ZZTESTE Simulada` e
  confirmar que **não** gera movimento nem transação e que **não deixa
  encerrar**. Este é o teste de regra de domínio mais importante do sistema.
- **Opções** (`/options/new`, `/options/positions/...`): criar posição de
  opção com contrato e vencimento `ZZTESTE`, editar, encerrar, excluir.
  Conferir tratamento de vencimento passado e de contrato sem série.
- **Proventos** (`/dividends`): criar provento em `ZZTESTE4`, editar, excluir.
  Conferir o reflexo em performance e no total da carteira. Testar data de
  pagamento anterior à data-com, valor zero e valor negativo.
- Validações gerais: quantidade zero e negativa, preço zero e negativo, data
  futura, data inválida, ponto × vírgula como separador decimal.

Apagar todo `ZZTESTE` ao fim e conferir que as 21 posições e 19 transações
reais continuam intactas (conferir os totais antes e depois).

## Bloco 4 — Mercado e cotações

- **Histórico de cotações** (`/quotes`): filtro por ticker e período,
  ordenação, paginação sobre 7.329 registros — medir a resposta.
- **Importar cotações** (`/quotes/import`): importar um arquivo pequeno **só
  com o ticker `ZZTESTE4` e datas próprias**. Testar arquivo malformado, data
  inválida, preço negativo, ticker inexistente, arquivo vazio.
- **Importar histórico de posição** (`/quotes/import-position-history`):
  mesma disciplina, só com dado de teste.
- **Apagar cotações por data** (`/quotes/delete-by-date`): **rota destrutiva**.
  Usar **exclusivamente** para apagar as datas que este agente importou.
  Conferir se a tela pede confirmação, se diz quantos registros vai apagar e se
  aceita data sem cotação. Errar o alvo aqui apaga histórico real — conferir
  duas vezes antes de confirmar.

## Bloco 5 — Análise (só leitura)

Com 21 posições e 100 proventos reais, os relatórios têm massa.

- **Risco** (`/risk`): conferir de onde vêm os números e se o comparador usa os
  tickers de referência.
- **Performance mensal** (`/performance`): conferir se a soma dos meses fecha
  com o acumulado e se separa real de simulado.
- **Exposição por ativo, por corretora e por mercado:** somar os percentuais —
  devem fechar em 100% dentro de cada moeda e natureza. **Fazer a conta.**
  Conferir que nenhuma tela mistura BRL com USD nem real com simulado.
- Em todas: gráfico renderiza (screenshot vale), legenda coerente, filtro
  vazio tratado, formato de número e moeda.

## Bloco 6 — Sistema

- **Configurações** (`/settings`): percorrer os campos. **Anotar os valores
  originais antes de mexer e restaurá-los ao final.**
- **Coletor / RTD:** pulso do coletor na barra, fragmento de heartbeat,
  `/settings/collector/refresh`, o alternador do RTD e o conceito de cotação
  "velha" (`RTD_STALE_AFTER_SECONDS`, 30s). O coletor remoto está desligado
  neste ambiente (`REMOTE_COLLECTOR_ENABLED=false`): conferir se a interface
  diz isso com clareza em vez de fingir que está ligada.
- **Alternar privacidade de valores:** ligar, percorrer três telas com valor na
  tela e conferir que **nenhuma** deixa valor escapar (inclusive gráfico,
  tooltip e título de página). Desligar ao final. Este é um bom candidato a
  achado transversal — o Bancário tem o mesmo botão.
- **Usuários** (`/users`): devem aparecer `mspa` e `Admin` ativos, e
  `valida-admin`, `valida-usuario` e `valida-next` **desativados** (resíduo de
  rodada anterior; não excluir, só registrar). Criar `ZZTESTE-rv` como
  operador, conferir a senha temporária mostrada uma única vez e que ela **não**
  vaza por mensagem flash, HTML subsequente ou URL. Editar, ativar/desativar,
  usar o botão **Redefinir**. **Não fazer login como `ZZTESTE-rv`.** Excluir ou
  desativar ao final.
- **`/minha-senha`** como `mspa`: abrir, conferir validação, **sem concluir a
  troca**.

## Bloco 7 — Bateria transversal

Conforme a seção "Bateria transversal" do `README.md`. Aqui, atenção especial
aos **gráficos Chart.js** (renderizam sem erro de console? redimensionam?) e ao
mega-menu no preset `mobile`.
