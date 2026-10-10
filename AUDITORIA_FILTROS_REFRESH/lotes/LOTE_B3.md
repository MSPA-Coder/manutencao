# Lote B3 (CB): continuação do B2 — só K2, K4, K6 e G1–G4

Base: http://127.0.0.1:5201

**Território:**
- **cartões 20 e 21**, contas **12, 13, 14 e 26** (dólar), aplicações
  **16, 17, 18, 19 e 24** e titular **Mamita** (conta 5);
- para criar lançamentos de ataque, use a **conta 5**, com descrição
  `[AUD-B3]`, de 2026-11 a 2027-03.

Os dados são de teste e o banco será restaurado ao fim. Mesmo assim, exclua o que
criar e registre o que sobrou.

Leia antes `PROTOCOLO.md`. Código extra deste lote: **C** (corrida), quando o
resultado depende da ordem ou do tempo. Exemplos: resposta velha sobrescrevendo
a nova, operação duplicada, filtro de uma aba afetando outra, tabela que volta
com filtro diferente do que está na tela.

**Já feitos pelo B2, NÃO repita:** K1, K3 e K5. Faça **só** K2, K4, K6 e G1 a
G4.

**Como funciona o Realizar** (o B2 se perdeu aqui):
1. clicar "Realizar" na linha abre o formulário com data e valor;
2. o botão "Confirmar" desse formulário abre um **segundo diálogo**,
   "Confirmar realização", que fica **por cima** do primeiro;
3. para enviar, clique o botão "Realizar" do **segundo** diálogo.

Use `find` com "Confirmar realização" depois do primeiro clique, para achar o
`ref` do segundo botão. O "Desfazer realização" segue o mesmo padrão, com o
diálogo "Confirmar reversão" e o botão "Desfazer".

## Parte 1: corrida (use a sonda em todos)

- **K1. Duplo clique no envio.** Em Lançamentos filtrado na conta 5:
  1. crie um lançamento `[AUD-B3]`;
  2. no diálogo final de confirmação, dê **dois cliques seguidos** no botão de
     confirmar, com duas chamadas `left_click` no mesmo `ref`, sem nada entre
     elas, ou um `double_click`;
  3. conte quantos foram criados (filtre pela descrição).

  Repita com **Realizar** e com **Excluir**.
- **K2. Filtro em voo e operação.** Em Lançamentos:
  1. troque um filtro de coluna (por exemplo, categoria) e, **na mesma
     `browser_batch`**, sem esperar, clique "Realizar" numa linha e confirme;
  2. depois confira se a tabela e os selects mostram o mesmo filtro, e se esse
     filtro é o da URL.
- **K3. Dois filtros rápidos.** Troque o filtro de tipo e, logo em seguida, o
  de categoria, na mesma `browser_batch`. O resultado final tem os dois? A
  tabela bate com os selects e a URL?
- **K4. Duas abas.**
  1. Abra uma **segunda aba sua** (`tabs_create`) com Lançamentos na conta 5 e
     outros filtros; a primeira fica na conta 20.
  2. Opere na aba 1: crie e depois exclua uma compra `[AUD-B3]` no cartão 20.
  3. Depois leia a aba 2: a URL e os filtros dela mudaram?
  4. Repita invertendo as abas. Mesmo teste no Fechamento de mês (conta 5 numa
     aba, filtro de ano diferente na outra; feche e reabra 2026-10 da conta 5).
- **K5. Voltar no meio da requisição.** Aplique um filtro e, na mesma batch,
  `navigate` `"back"`. Registre o estado final: URL, selects e tabela coerentes
  entre si?
- **K6. Recarga da tabela depois de um filtro HTMX.**
  1. Em Lançamentos, aplique um filtro de coluna (troca HTMX, sem recarga).
  2. Sem recarregar, edite um lançamento `[AUD-B3]` em linha e salve.
  3. A tabela volta com o filtro de coluna que estava aplicado?

  Repita com o Desfazer realização.

## Parte 2: lacunas da rodada A

- **G1. Compra no cartão.** Em Lançamentos filtrado no cartão 20, crie uma
  compra `[AUD-B3]`, edite, depois exclua. Meça cada passo.
- **G2. Transferência e escopo.**
  1. Crie uma **transferência** entre a conta 5 e uma aplicação do território
     (16 a 19 ou 24), como recorrente ou parcelada, com `[AUD-B3]`.
  2. Depois edite com o escopo **"Este registro e os próximos"**: o app pede uma
     confirmação. Registre o texto e se a gravação sai.
  3. Exclua tudo.
- **G3. Filtros globais em todas as telas do menu.** Para **cada** item do menu
  lateral que ainda não foi coberto (Lançamentos e Fechamento já foram):
  1. aplique Dólar e desmarque um grupo em "Abrir filtros globais";
  2. navegue para mais 2 telas pelo menu;
  3. confirme que moeda e grupos acompanham.

  Registre como `G3.<tela>`.
- **G4. Planejamento anual, seleção múltipla.** Marque 2 titulares e 3 contas
  **clicando em cada opção** (não use `form_input` com lista), aplique, role, F5
  e voltar. Os múltiplos sobrevivem?

## Fim

Exclua tudo o que tiver `[AUD-B3]`, feche **as suas** abas e responda em até 15
linhas: casos com C (corrida), com o passo exato, e os resultados de G1 a G4.
