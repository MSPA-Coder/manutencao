# Lote R1 (CB): reteste das correções

Base: http://127.0.0.1:5201. O CB local roda a branch com as correções.

**Território:**
- Lançamentos: titular **Esposita** (owner_id=2), contas **3, 4 e 6**, meses 2026-11 a 2027-03;
- tabelas cadastrais e Gerencial: só entidades suas `[AUD-R1]`.

Os dados são de teste e o banco será restaurado ao fim.

Leia antes `PROTOCOLO.md`. Aqui cada caso diz o comportamento **esperado depois da
correção**. Meça com a sonda e registre:
- `OK` se o esperado aconteceu;
- o código do problema (`R`, `F`, `P`, `U`, `M` ou `C`) se não aconteceu;
- em `obs`, o que diverge.

Em todos os casos, prepare a tela com filtros fora do padrão: **moeda Dólar ou
"Real + Dólar"** pelo menu "Abrir filtros globais", titular, conta e, quando
houver, filtro de coluna.

## Casos

- **R1.1, Lançamentos: filtro de coluna.**
  - Ação: com o filtro de Tipo escolhido, escolha uma Categoria.
  - Esperado: os dois continuam (select e URL); troca só a tabela (`trocas` sem `appMain`); sem recarga.
- **R1.2, Lançamentos: Realizar.**
  - Ação: no formulário de realizar, Confirmar e depois "Realizar" no segundo diálogo.
  - Esperado: **sem recarga**; filtros, moeda e coluna iguais; o diálogo fecha; a linha some do modo "A vencer"; aparece aviso de sucesso.
- **R1.3, Lançamentos: Desfazer realização** (modo Realizado).
  - Esperado: sem recarga; filtros iguais; o lançamento volta a aparecer em **A vencer** se o vencimento for hoje ou futuro.
- **R1.4, Lançamentos: Novo lançamento `[AUD-R1]`.**
  - Esperado: sem recarga; a tabela atualiza; o formulário fica aberto, com descrição e valor limpos e conta, tipo, status e vencimento mantidos.
  - Repita em seguida com **outra** descrição: tem de criar o segundo normalmente.
- **R1.5, Lançamentos: Novo lançamento sem descrição.**
  - Esperado: o navegador ou o servidor recusa; nada é criado; o formulário mantém o que foi digitado.
- **R1.6, Lançamentos: duplo clique.**
  - Ação: no diálogo final de Salvar do Novo lançamento, dois cliques seguidos no botão de confirmar.
  - Esperado: **um** lançamento criado.
- **R1.7, Lançamentos: Editar em linha** um `[AUD-R1]`.
  - Esperado: sem recarga; filtros iguais; a linha volta fechada com o valor novo.
- **R1.8, Lançamentos: Excluir** os seus `[AUD-R1]`.
  - Esperado: sem recarga; filtros iguais.
- **R1.9, Lançamentos: "Voltar" do Novo lançamento.**
  - Esperado: só fecha o cartão, sem navegar; filtros iguais.
- **R1.10, Tabelas: bancos, contas, categorias e titulares.**
  - Ação: com o filtro da tabela escolhido, inclua, edite e exclua uma entidade `[AUD-R1]`.
  - Esperado: sem recarga; o filtro continua no select **e na URL**; troca só o corpo da tabela.
  - Ação: troque o filtro.
  - Esperado: a **URL acompanha**.
- **R1.11, Tabelas: erro.**
  - Ação: inclua um banco com nome vazio (apague o `required` não; use só espaços, se o navegador deixar).
  - Esperado: mensagem de erro e nada recarrega.
- **R1.12, Gerencial.**
  - Ação: com titular, conta e mês escolhidos, crie uma tag e um projeto `[AUD-R1]` e depois arquive.
  - Esperado: **sem recarga** (troca de `appMain` é aceitável); filtros iguais.
- **R1.13, Fechamento de mês.**
  - Ação: com filtros de conta e ano, feche 2026-10 da **conta 4** e reabra.
  - Esperado: sem recarga; filtros iguais.
- **R1.14, Reclassificação.**
  - Ação: com conta 6, categoria e **moeda "Real + Dólar"**, clique em "Revisar".
  - Esperado: a prévia mantém conta, categoria e moeda **na URL**.
  - Ação: cancele, sem gravar.
- **R1.15, Recorte pelo menu.**
  - Ação: em Lançamentos com titular e conta escolhidos, **clique** nos links do menu Dashboard, Projeções, Próximos movimentos, Gerencial e Posição por conta.
  - Esperado: titular e conta chegam e aparece a faixa "Recorte: …". Em Posição por conta chega só o titular, sem a conta. Em Planejamento anual e Fechamento **não** chegam.
  - Ação: clique em "Limpar recorte".
  - Esperado: o recorte some.
- **R1.16, Voltar do navegador** depois de filtrar em Lançamentos.
  - Esperado: sai da tela (decisão de produto); **não** é achado.

## Fim

Exclua tudo o que for `[AUD-R1]` e for excluível (tags e projetos só se arquivam),
feche a sua aba e responda em até 15 linhas, com a lista de casos que **não**
deram o esperado e o porquê.
