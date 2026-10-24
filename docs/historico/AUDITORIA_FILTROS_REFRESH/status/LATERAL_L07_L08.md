# Investigações laterais L07 e L08 — ControleRendaVariavel

Data: 2026-10-09. Escopo: somente leitura (código, `git`, SELECT no banco local).
Nenhum arquivo do repositório foi alterado; nenhum commit; nenhum navegador; a
aplicação não foi executada. Árvore git limpa no momento da leitura. Os arquivos
`app/routes/options.py` e `app/routes/quotes.py` do contêiner
`controle-renda-variavel-web-1` são idênticos ao working tree (não há imagem
antiga em jogo).

---

## L07 — editar contrato de opção não salva e não avisa

### Veredito

**Não há caminho silencioso no servidor.** A rota aceita trocar o ticker da
opção, e todos os desfechos produzem flash. O sintoma "recarregou sem mensagem e
o código não mudou" não se explica só pelo código da rota. As causas prováveis
ficam fora da rota (toast de 6 s, ou edição de campo diferente do que se
imaginou). Confirmar pelo banco antes de mexer no código.

### Evidência

- Rota: `app/routes/options.py:593-619` (`update_contract`).
  - Lê `ticker_id` (598), `underlying_ticker_id` (599), `strike` (600),
    `expiration_id` (611) e `option_type` (612). Os cinco campos batem com os
    `name=` do template.
  - "Código da opção" = `ticker_id`. O select da coluna "Opção" do template
    (`app/templates/table_contracts.html:37`) é o ticker da opção. A edição
    **troca o ticker** quando o usuário escolhe outro.
  - Desfechos, todos com flash:
    - sucesso: `flash("Contrato atualizado.", "success")` (615);
    - `ValueError`, `KeyError`, `ArithmeticError`, `IntegrityError`:
      `flash("Contrato inválido ou ticker já associado a uma opção.", "error")` (618);
    - id malformado: `parse_positive_id` chama `abort(400)` (`app/routes/helpers.py:200-212`),
      que é página de erro, não reload silencioso.
  - Não há `return` sem flash nem `except` que engula erro.
- Template: o form de cada linha é `<form id="contract-{id}">` (36) e os demais
  campos usam `form="contract-{id}"`. O botão Salvar também (`form=`, linha
  ~62). Esse padrão é válido em navegador moderno. O clique passa pelo
  `data-sa-confirmar` do SharedAuth (`sharedauth-ui.js:354-366`), que faz
  `requestSubmit(alvo)` e inclui todos os campos associados ao form.
- Restrições de banco (`pg_constraint`): `uq_option_contracts_ticker_id UNIQUE (ticker_id)`
  e FKs `RESTRICT`. Trocar o ticker para um que já tem contrato gera
  `IntegrityError`, que volta como erro (flash de erro, não silêncio).
- Banco: 6 contratos; nenhum com ticker inativo ou benchmark. Não há trigger em
  `option_contracts` (os triggers `patrimonio_v4_outbox_*` não incluem essa tabela).
- Nenhum teste cobre `POST /tables/options/contracts/<id>` (grep em `tests/`).

### Hipóteses, em ordem de probabilidade

1. **Toast não percebido.** O resultado (sucesso ou erro) vira toast via
   `data-sa-avisos` (`partials/flash_toast.html`, `sharedauth-ui.js:413-431`) e
   some em 6 s (`SEGUNDOS_TOAST = 6000`). Se o toast passou despercebido, o
   usuário conclui "sem mensagem".
2. **Troca rejeitada por ticker já vinculado.** Se o ticker escolhido já tem
   contrato, o commit falha por `uq_option_contracts_ticker_id` e aparece o
   erro genérico "Contrato inválido ou ticker já associado a uma opção.". A
   mensagem é genérica e pode não ter sido lida como falha.
3. **Campo errado.** Os códigos de call/put (ex.: "2026A") vivem em
   `OptionExpiration` (`/tables/options/expirations`, `update_expiration`). A
   tela de contratos não os edita. Se o executor tentou mudar o "código" nessa
   tela e não achou, nada foi salvo.

### Como confirmar (sem executar a aplicação)

- Pedir ao executor o `id` do contrato de teste e rodar (somente leitura):
  `SELECT id, ticker_id, underlying_ticker_id, expiration_id, option_type FROM option_contracts WHERE id = <id>;`
  Se o `ticker_id` ficou igual ao de antes, a troca não persistiu; se mudou, o
  problema é só de feedback visual (hipótese 1).
- No navegador do executor (DevTools > Rede): o POST deve responder 302 para
  `/tables/options/contracts`. Se responder 400/403/404, o problema está no
  envio, não na rota.

### Proposta

- Nenhuma mudança de comportamento é necessária para o caso "não troca": a rota
  já troca o ticker.
- Melhoria de feedback (baixa prioridade): separar as mensagens de erro em
  `IntegrityError` ("Este ticker já possui contrato de opção"), `ticker_id == underlying_ticker_id`
  ("O ticker da opção e o ativo-objeto não podem ser o mesmo") e
  `is_benchmark` ("Ticker de referência não pode ter contrato"). Hoje as três
  caem na mesma frase genérica.
- Se o executor precisa mudar o código de vencimento (call/put), o caminho certo
  é `/tables/options/expirations`, não a tela de contratos.

### Teste proposto

Teste de rota com a fixture `app_com_banco` (marcador `banco`), em
`tests/test_options_contratos.py` (nome sugerido). Casos:
1. trocar `ticker_id` para um ticker livre → 302, `flash` de sucesso, e o banco
   reflete o novo `ticker_id`;
2. trocar para ticker já vinculado a outro contrato → 302, flash de erro, banco
   inalterado;
3. `ticker_id == underlying_ticker_id` → flash de erro, banco inalterado.

---

## L08 — `/quotes?benchmark_ticker_id=...` devolve 404

### Veredito

**Para a URL isolada (`/quotes?benchmark_ticker_id=1`): uso inválido.** Nenhum
fluxo da interface gera essa URL, e o id 1 aqui não é benchmark.

**Há um defeito real, latente:** quando `ticker_id == benchmark_ticker_id`, a
rota responde 404. Esse caso é alcançável pela própria interface (trocar o
ticker principal para o que está em comparação, ou gravar uma cotação desse
ticker), e a resposta 404 é silenciosa no HTMX. Hoje ele não aparece nos dados
porque não há benchmark entitled a nenhum usuário (ver abaixo).

### Evidência

- GET aceita o parâmetro: `app/routes/quotes.py:193-194` (`request.args.get("ticker_id")`
  e `request.args.get("benchmark_ticker_id")`). Não é só POST.
- Origem dos 404 em `app/routes/quotes.py`:
  - linha 89: `ticker_id` não está em `quote_ticker_records()` → `abort(404)`;
  - linha 110: `benchmark_id` não está em `benchmark_candidates(exclude_ticker_id=selected_ticker.id)` → `abort(404)`.
  - `owned_or_404` **não** é usado aqui: é um `abort(404)` direto.
- Sem `ticker_id`, `selected_ticker` cai em `tickers[0]` (linha ~84). Para
  `?benchmark_ticker_id=1` isolado, o id 1 é ao mesmo tempo o ticker padrão
  (excluído dos candidatos) e não é benchmark. Logo 404 por desenho.
- `benchmark_candidates` (`app/routes/helpers.py:362-375`) exige
  `is_benchmark`, entitlement do usuário, ativo, e exclui o ticker selecionado.
- Quem gera os dois parâmetros juntos:
  - seletor "Ticker" (`app/templates/partials/quotes_results.html:17-20`, `hx-get` com
    `hx-include="closest form"`): inclui o `benchmark_ticker_id` do form. Se o
    usuário escolhe como ticker o mesmo que está em "Comparar com" (linha
    51-54), a requisição é `/quotes?ticker_id=X&benchmark_ticker_id=X` → 404.
  - formulários de gerenciamento (`quotes_results.html:147, 161, 173`; select
    `ticker_id` na linha 176): o `benchmark_ticker_id` vai como hidden. Em
    `create_quote_history_entry` o commit acontece **antes** de
    `_quote_management_response` (`quotes.py:201-232`). Com `ticker == benchmark`,
    a cotação é gravada e a resposta é 404.
- Por que é silencioso: `app/static/app.js:294-302` só troca resposta 400/422
  com cabeçalho `X-App-Request-Error`. Um 404 não é trocado: a tela fica como
  estava, sem mensagem. Na versão sem JS, a gravação vai para um redirect 404.
- Estado do banco (somente contagens):
  - benchmarks cadastrados: 2; benchmarks com entitlement: **0**;
  - tickers com entitlement: 26; o id 1 não é benchmark, tem entitlement e é o
    primeiro na ordem da lista.
  - Consequência: `benchmark_candidates` está vazio para todos os usuários, o
    seletor "Comparar com" não é renderizado (`{% if benchmark_candidates %}`) e
    a colisão não ocorre hoje.
- Como a colisão pode surgir: `grant_ticker_entitlement` (`helpers.py:101`) não
  revoga entitlement ao encerrar posição, e `ticker_has_holdings`
  (`helpers.py:~306-350`) não considera entitlement. Um ticker que já foi detido,
  sem registros restantes, pode ser marcado como benchmark
  (`tables.py:168`) e passa a ser candidato para o usuário.

### Proposta

1. Em `_quote_history_context` (`quotes.py`): se `benchmark_id` for o ticker
   selecionado ou não for candidato, tratar como "Nenhum" (`selected_benchmark = None`)
   em vez de `abort(404)`. Parâmetro de filtro não deve virar 404.
2. Em `_quote_management_response`: descartar `benchmark_id` quando for igual a
   `ticker_id`, para que a resposta após a gravação não seja 404.
3. Opcional, front-end: ao trocar o ticker principal para o comparador atual,
   resetar "Comparar com" para "Nenhum" no próprio seletor.
4. Não mudar a regra de entitlement sem decisão de produto: é ela que impede
   comparar com benchmark não detido.

### Teste proposto

- `GET /quotes?ticker_id=X&benchmark_ticker_id=X` → 200, sem comparação
  (`selected_benchmark is None`). Hoje retorna 404.
- `POST` de cotação com `ticker_id == benchmark_ticker_id` → 200/302 e sem 404
  após gravar.
- `GET /quotes?benchmark_ticker_id=<id não candidato>` → 200 sem comparação
  (após a mudança na proposta 1). Documentar a decisão no próprio teste.
- Os testes atuais de `tests/test_htmx_persistence.py` monkeypatcham
  `_quote_history_context`, então não cobrem a colisão; o novo teste deve usar a
  rota real (camada `banco`, se houver entitlement de benchmark).

---

## Resumo

| Item | Veredito | Severidade |
|---|---|---|
| L07 | Rota troca o ticker e sempre dá flash; sintoma provavelmente de feedback ou de campo errado. Confirmar pelo banco. | Baixa |
| L08 (URL isolada) | Uso inválido: nenhum fluxo gera. | Nenhuma |
| L08 (colisão ticker == benchmark) | Defeito real e latente: 404 silencioso no HTMX, e cotação gravada sem feedback. Zero benchmarks entitled hoje. | Média |
