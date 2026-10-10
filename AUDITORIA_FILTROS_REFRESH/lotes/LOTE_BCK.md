# Lote BCK (CRV): ataques de corrida

Base: http://127.0.0.1:5301.

**Território:**
- carteira **id 1**, corretora **2**;
- proventos na corretora **4**;
- cadastros só com prefixo `[AUD-BCK]`.

**Dados reais** (cópia da produção): quantidade 1 e valor mínimo; anote o id de
tudo o que criar e exclua no fim; nunca altere nem exclua o que já existia.

Leia antes `PROTOCOLO.md`. Use a sonda em todos os casos. O código extra
deste lote é **C** (corrida).

- **K1. Duplo envio.**
  - Ação: no formulário de **novo provento** (`/dividends/new`) e no de **nova transação encerrada**, dois cliques seguidos em Salvar.
  - Pergunta: quantos registros foram criados (filtre a lista)? O CRV tem uma checagem de duplicata no servidor; registre se ela aparece.
  - Ação: repita na **exclusão** de um registro seu.
- **K2. Duas abas.**
  - Ação: aba A em `/dividends` filtrada pela corretora 4; aba B em `/dividends` com outra moeda. Crie e exclua um provento seu na aba A.
  - Pergunta: a aba B mudou de URL ou de filtro?
  - Ação: mesmo teste na Carteira (`/`) com filtros diferentes nas duas abas.
- **K3. Filtro em voo.**
  - Ação: na Carteira, troque a corretora e, na mesma `browser_batch`, troque o período de retorno.
  - Pergunta: o resultado final tem os dois filtros, coerentes na tela e na URL?
- **K4. Voltar no meio da requisição.**
  - Ação: na Carteira, troque um filtro e, na mesma batch, `navigate "back"`.
  - Pergunta: a URL, os selects e a tabela estão coerentes?
- **K5. Linha expandida.**
  - Ação: na Carteira, expanda uma posição e então troque um filtro.
  - Pergunta: a expansão some? A resposta da expansão chegando depois sobrescreve a lista filtrada?

## Fim

Exclua o que for seu, feche as suas abas e responda em até 12 linhas, com cada
caso **C** e o passo exato que o produz.
