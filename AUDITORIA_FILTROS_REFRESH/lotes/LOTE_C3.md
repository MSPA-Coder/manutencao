# Lote C3 (CRV)

Base: http://127.0.0.1:5301

**Território:** Carteira **id 3** (Simulada), corretora **3**. **DADOS REAIS (cópia da produção):** posição nova SÓ em ticker que a carteira 3 ainda não tem (a Simulada rejeita segunda entrada na mesma chave); nunca exclua nem altere posição que existia antes; quantidade 1; exclua a sua no fim.

Leia antes `PROTOCOLO.md`.

## Notas

- Performance, Risco e Exposição são telas de leitura com filtros: aplique, role, recarregue (F5), volte e navegue pelo menu.
- Na carteira Simulada (filtrada em `/`), crie, edite e exclua uma posição `[AUD-C3]` e confira os filtros.
- Procure no menu as telas de Exposição (por ativo, corretora, mercado) e teste os filtros delas.

## Casos

### 1. `/performance`
- filtros detectados: portfolio_id, broker, portfolio, period, benchmark_ticker_id
- **1.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **1.X** outras operações visíveis na tela e não listadas acima: teste e registre como `1.X<n>`.

### 2. `/risk`
- filtros detectados: nenhum no template (procure na tela)
- **2.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **2.X** outras operações visíveis na tela e não listadas acima: teste e registre como `2.X<n>`.

### 3. `/data-status`
- filtros detectados: nenhum no template (procure na tela)
- **3.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.
- **3.X** outras operações visíveis na tela e não listadas acima: teste e registre como `3.X<n>`.

