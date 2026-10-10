# Lote C2 (CRV)

Base: http://127.0.0.1:5301

**Território:** Carteira **id 2** (USD); proventos só nas corretoras **2 e 4**. Crie só proventos `[AUD-C2]` e exclua no fim.

Leia antes `PROTOCOLO.md`.

## Notas

- Proventos: filtre por corretora, tipo, período e ticker (o que houver), role, crie, edite e exclua um provento seu. Teste também a edição a partir da lista filtrada.
- Importação de proventos: se pedir arquivo, `NAO_TESTAVEL`. Se for colar texto, **não** importe; só abra e cancele.
- Moeda: alterne BRL, USD e ALL e confira a propagação pelo menu (caso `G.<tela>`).

## Casos

### 1. `/dividends`
- filtros detectados: broker
- **1.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **1.X** outras operações visíveis na tela e não listadas acima: teste e registre como `1.X<n>`.

### 2. `/dividends/import`
- filtros detectados: nenhum no template (procure na tela)
- **2.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **2.1** operação `portfolio.import_dividends`; resposta prevista: redirect-sem-query
- **2.X** outras operações visíveis na tela e não listadas acima: teste e registre como `2.X<n>`.

