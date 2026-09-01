# Status — ControleRendaVariavel (RV)

**RODADA CONCLUÍDA** na 4ª tentativa (as três anteriores morreram por limite
de sessão da conta, não por erro do agente).

**Blocos concluídos:**
- [x] Bloco 1 — Varredura do menu
- [x] Bloco 2 — Cadastros
- [x] Bloco 3 — Posições e transações (núcleo)
- [x] Bloco 4 — Mercado e cotações
- [x] Bloco 5 — Análise (só leitura)
- [x] Bloco 6 — Sistema
- [x] Bloco 7 — Bateria transversal
- [x] Limpeza final (roteiro de 10 passos)

Nada pendente de execução. Resta apenas a pendência de banco de dados
listada abaixo, fora do escopo deste teste (proibido SQL).

## Achados finais por severidade

- Bloqueio: 0
- Defeito: 5 — RV-05 (datas futuras aceitas em transação fechada e
  provento), RV-06 (posição de opção em contrato já vencido), RV-10
  (cotação manual aceita R$0,00), RV-14 (posição sem cotação tratada de 3
  formas diferentes nas telas de Análise, uma delas falsa — "Nenhuma
  posição encontrada"), RV-15 (privacidade de valores só cosmética nos
  gráficos — `data-values` no HTML carrega os números reais)
- Inconsistência: 2 — RV-12 (mensagem do Yahoo Finance em inglês), RV-13
  (nomes de mês em inglês no navegador de cotações)
- Melhoria: 5 — RV-01 (links do mega-menu sem nome acessível), RV-04
  (mensagem genérica no cadastro de Vencimento), RV-07 (campo numérico
  rejeita vírgula sem aviso), RV-11 (confirmação de excluir cotação não
  identifica ticker/data), RV-16 (exclusão de cadastro em uso não indica
  qual registro bloqueia, mesmo quando nenhuma tela o exibe)
- Observação: 6 — RV-02 (pulso do coletor 13 dias no passado — mas
  Bloco 6 confirmou que a interface é honesta sobre isso), RV-03 (nota de
  método sobre cliques automatizados, corrigida no Bloco 3), RV-08 (não
  existe campo data-com em Proventos), descoberta de que `/quotes/import`
  não é upload de arquivo, confirmação positiva da regra da carteira
  Simulada (três vezes independentes: Bloco 3 movimento/bloqueio de
  encerramento, Bloco 5 ausência total nas telas de Análise e no filtro),
  e a descoberta de que as contas `valida-admin/valida-usuario/valida-next`
  descritas no README **não existem** neste ambiente do CRV (só `Admin` e
  `mspa`, ambos ativos)

**Nota:** a numeração salta de RV-08 para RV-10 (não existe RV-09) — gap
pré-existente de uma tentativa anterior a esta 4ª retomada, não foi criado
agora e não foi corrigido, para não violar a regra "acrescentar, nunca
reescrever" do relatório.

## Os três achados mais graves (para o resumo executivo)

1. **RV-15 (Defeito) — Privacidade de valores é só visual.** Com "Ocultar
   valores" ligado, os gráficos de `/performance` e `/analysis/exposure-asset`
   ficam borrados na tela, mas o HTML de origem carrega um atributo
   `data-values` com os números **exatos e completos** do patrimônio — "Ver
   código-fonte" ou qualquer inspeção simples do elemento revela tudo,
   contrariando o propósito do recurso.
2. **RV-14 (Defeito) — Telas de Análise escondem ou mentem sobre posição sem
   cotação.** Uma posição real sem preço atual some inteiramente de
   "Alocação por Ativo" (ou pior, gera a mensagem falsa "Nenhuma posição
   encontrada"), aparece como linha `R$0,00`/`-` inconsistente em Corretora,
   e como duas linhas idênticas sem rótulo em Mercado — quatro tratamentos
   diferentes para o mesmo dado no mesmo sistema, nenhum deles no padrão
   correto que a própria home já usa ("Aguardando primeira cotação RTD").
3. **RV-05 (Defeito) — Datas futuras aceitas onde representam algo já
   realizado.** Transação fechada e provento aceitam data de
   encerramento/pagamento no futuro sem qualquer aviso, mesmo o sistema já
   demonstrando ter validação de data em outras telas (Cotações barra data
   futura corretamente).

## O que ficou sem testar, e por quê

- **F5 depois de gravar:** não foi possível confirmar se o navegador
  reenvia um POST ao atualizar — a tecla F5 simulada via automação não
  gerou nenhuma requisição nova na aba em segundo plano (limitação do
  ambiente de automação, não conclusão sobre o produto).
- **Autorização por papel:** só havia uma conta disponível (`mspa`, Admin);
  o roteiro proíbe logar como o `ZZTESTE-rv` (Operador) recém-criado para
  comparar o que cada papel vê, então não foi possível confirmar se rotas
  de Sistema/Cadastros são de fato protegidas no servidor para não-admin ou
  só escondidas no menu.
- **Editar usuário existente (papel/nome) em `/users`:** o classificador de
  segurança do próprio harness bloqueou as tentativas (tratou troca de
  papel/edição de conta como ação sensível demais para automatizar, mesmo
  em ambiente de teste). Nenhuma conta real foi alterada; o teste ficou
  incompleto por essa razão, documentado em detalhe no relatório.
- **"Contrato sem série" em Opções (Bloco 3):** não consegui reproduzir
  esse cenário específico pela interface sem mexer em cadastro real.
- **`/settings/collector/refresh`:** confirmado que existe (405 em GET),
  mas não achei nenhum botão de UI que aponte para essa rota neste
  ambiente (o alternador RTD vem desabilitado) — não pôde ser exercitado
  como usuário real faria.

## Pendência de limpeza que sobrou para o mantenedor (fora do escopo deste teste — proibido SQL)

Três cadastros `ZZTESTE` **não puderam ser excluídos pela tela**, mesmo
depois de eu ter apagado manualmente, pela própria interface, toda posição,
transação, provento e vínculo visível que os referenciava:

- Ticker `ZZTESTE4` / "ZZTESTE4 PN N1" — **id 32** —
  `/tables/tickers/32/delete` → "O ticker não pode ser excluído enquanto
  possuir posições, transações ou proventos vinculados."
- Corretora `ZZTESTE Corretora` — **id 7** — `/tables/brokers/7/delete` →
  "A corretora não pode ser excluída enquanto possuir posições, transações
  ou proventos vinculados."
- Carteira `ZZTESTE Real` — **id 4** — `/tables/portfolios/4/delete` → "A
  carteira não pode ser excluída enquanto possuir posições ou transações
  vinculadas."

Ver RV-16 no relatório e a seção "Limpeza final" para o detalhamento
completo de como cheguei a essa conclusão (nenhuma tela do produto —
home, `/transactions` em ambos os status, `/dividends`, `/options` —
mostra qualquer vínculo remanescente; a trava provavelmente aponta para um
registro histórico de movimento que sobrevive à exclusão de posição por
design de auditoria, mas nenhuma tela expõe). **Recomendação para o
mantenedor:** localizar e remover esse(s) registro(s) órfão(s) via banco
(fora do escopo deste agente), ou então excluir os três cadastros
diretamente no banco depois de confirmar que não há dado real dependendo
deles.

**Removidos com sucesso nesta limpeza:** as 4 transações originais (`#27`,
`#28`, `#29`, `#31`) mais uma inesperada (`#35`, resto do encerramento
parcial da opção `#7` que virou standalone ao apagar a posição-mãe);
posições `#34` e `#33`; posição de opção `#7`; provento `#101`; contrato de
opção `ZZTESTE4O`/`ZZTESTE4`; vencimento `9999A/9999M`; vínculo
ticker↔carteira `ZZTESTE4`↔`ZZTESTE Real`; ticker `ZZTESTE4O` (id 33);
carteira `ZZTESTE Simulada` (id 5); usuário `ZZTESTE-rv` (deixado
desativado — produto não tem exclusão de usuário, só ativar/desativar).

Nenhum dado real (21 posições, 19 transações, 100 proventos, 31 tickers, 5
corretoras, 3 carteiras, 7.329 cotações) foi tocado em nenhum bloco desta
rodada.

## Remediação das prioridades imediatas — 01/09/2026

- **RV-05 — resolvido:** transação fechada e provento recebido recusam datas
  futuras com mensagem explícita.
- **RV-06 — resolvido:** não é mais possível criar posição usando contrato de
  opção já vencido. Uma posição histórica vencida continua editável, evitando
  bloquear manutenção de registros legítimos.
- **RV-10 — resolvido:** cotação manual exige preço estritamente positivo e
  data não futura; preço zero é recusado antes de qualquer consulta ao banco.
- **RV-14 — resolvido:** posições sem cotação deixam de contaminar totais e
  agrupamentos com zero fictício e aparecem em tabela própria, com corretora,
  mercado, carteira, moeda e o estado `Aguardando primeira cotação RTD`.
- **Validação:** Ruff aprovado, **192 testes** aprovados (duas advertências de
  depreciação em dependência externa), migração concluída e aplicação/banco
  reconstruídos e saudáveis na porta 5301.
