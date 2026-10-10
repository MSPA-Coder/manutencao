"""Gera lotes/LOTE_<id>.md a partir do inventário. Uso: python gerar_lotes.py <cb|crv>"""
import csv
import sys
from collections import OrderedDict, defaultdict
from pathlib import Path

SIS = sys.argv[1]
BASE = Path(__file__).parent
INV = BASE / "inventario"
(BASE / "lotes").mkdir(exist_ok=True)
URL = {"cb": "http://127.0.0.1:5201/", "crv": "http://127.0.0.1:5301"}[SIS]

filtros = defaultdict(list)
for r in csv.DictReader(open(INV / f"filtros_{SIS}.csv", encoding="utf-8")):
    if not r["oculto"] and r["filtro"] not in filtros[r["tela"]]:
        filtros[r["tela"]].append(r["filtro"])
ops = defaultdict(OrderedDict)
for r in csv.DictReader(open(INV / f"operacoes_{SIS}.csv", encoding="utf-8")):
    chave = r["endpoint"] if r["endpoint"] != "?" else (r["url_template"] or "(form sem ação)")
    o = ops[r["tela"]].setdefault(chave, {"resp": r["respostas_endpoint"], "n": 0, "conf": r["confirma"], "alvo": r["hx_target"]})
    o["n"] += 1
telas_inv = {r["tela"] for r in csv.DictReader(open(INV / f"filtros_{SIS}.csv", encoding="utf-8"))} | set(ops)

CB = {
    "A1": {
        "territorio": "Titular **Esposita** (owner_id=2): contas 3, 4, 6, 15 e 22. Lançamentos novos só em 2026-11 a 2027-03 dessas contas.",
        "telas": ["transactions/", "operations/", "dashboard/", "reports/upcoming-movements/", "reports/projections/"],
        "notas": [
            "Lançamentos é o centro deste lote: teste **cada** ação da linha (Editar inline, Excluir com cada escopo "
            "oferecido, Realizar, Desfazer realização, Ver operação) e o **Novo lançamento** (simples, parcelado, "
            "recorrente, transferência entre as SUAS contas).",
            "Em Lançamentos combine os filtros de contexto (período, status, titular, instituição, conta) com os "
            "**filtros de coluna** (data, tipo, categoria) antes de operar: são dois grupos e podem se perder separados.",
            "Dashboard e Relatórios: além dos filtros, siga os links e drilldowns que levam a Lançamentos e confira se "
            "chegam com os filtros (titular, conta, período, moeda e grupos).",
        ],
    },
    "A2": {
        "territorio": "Titular **Maridito** (owner_id=1), contas **1, 7, 8, 9, 10 e 11**. Gerencial: crie só projetos e tags `[AUD-A2]`.",
        "telas": ["management/", "banking/balance/", "banking/reclassification/", "banking/reconciliation/",
                  "banking/attachments/", "banking/imports/", "banking/statements/", "banking/status/",
                  "reports/account-position/", "reports/annual-planning/"],
        "notas": [
            "Upload de arquivo (importar extrato, anexo) **não** é possível neste navegador: registre `NAO_TESTAVEL` e siga. "
            "Operações sobre linhas já importadas (conciliar, ignorar, criar lançamento a partir da linha, desfazer) são "
            "testáveis se a linha for de conta do seu território.",
            "Desfazer importação inteira: **não** faça (é destrutivo e global ao lote importado). Só registre que existe.",
            "Planejamento anual tem seletor próprio de contas e titulares (múltiplo): marque várias e confira se sobrevivem.",
        ],
    },
    "A3": {
        "territorio": "Cartões **20 e 21**; contas em dólar **12, 13, 14 e 26**; aplicações **16, 17, 18, 19 e 24**; titular **Mamita** (conta 5). Fechamento de mês **só** nessas contas.",
        "telas": ["settings/monthly-close/", "banking/cards/", "banking/accounts/<int:account_id>/"],
        "notas": [
            "Fechamento de mês: feche **2026-10** de uma conta sua com filtros aplicados na lista, depois reabra; repita "
            "reabrindo **2026-09** e fechando de novo. Confira a lista e os filtros depois de cada ação.",
            "Faturas: abra a fatura de cada cartão, navegue entre faturas e volte; confira filtros e rolagem.",
            "**Filtros globais (tarefa extra deste lote, só leitura):** em **cada** tela do menu do CB, marque Dólar "
            "(ou Real+Dólar) e desmarque um grupo de conta no menu \"Abrir filtros globais\", clique Aplicar e navegue "
            "pelo menu para 5 outras telas: a moeda e os grupos têm de acompanhar. Registre como caso `G.<tela>`.",
            "Lançamentos em cartão: crie uma compra `[AUD-A3]` no cartão 20 a partir de Lançamentos filtrado no "
            "cartão, depois exclua. Use `transactions/` só para isso.",
        ],
    },
    "A4": {
        "territorio": "Entidades **criadas por você** com prefixo `[AUD-A4]`: crie, edite e exclua a sua. **Não** altere registros existentes, exceto preferências de perfil (tema, rolagem), que você restaura ao valor original.",
        "telas": ["tables/accounts/", "tables/banks/", "tables/categories/", "tables/owners/", "settings/",
                  "settings/profile/", "settings/audit-log/", "settings/database/", "permissions/",
                  "banking/reconciliation/", "banking/reclassification/", "banking/balance/"],
        "notas": [
            "Este lote roda **sozinho**, depois que A1, A2 e A3 terminaram: mexe em cadastros que os outros usam.",
            "**Escrita financeira (só neste lote, porque roda sozinho; dados locais de teste):** em Conciliação, "
            "filtre a **conta 8** e opere só em linhas dessa conta: conciliar, desfazer a conciliação, ignorar, "
            "criar lançamento a partir da linha (depois exclua o lançamento criado em Lançamentos) e ação em lote "
            "com 2 linhas (depois desfaça). Em Reclassificação, filtre a conta 8, reclassifique **um** lançamento "
            "para outra categoria e, em seguida, devolva-o à categoria original. Se pedir para autorizar a reabertura "
            "de um mês fechado, autorize: os dados são de teste. Em Atualizar saldo, lance a diferença numa "
            "aplicação (contas 16 a 19 ou 24) e depois exclua o lançamento gerado. Meça cada passo com a sonda.",
            "Gerencial: o executor A2 deixou um orçamento de teste (categoria Outros, 09/2026) sem prefixo. Retire-o "
            "pela tela de Gestão (titular Maridito) e meça a operação.",
            "Tabelas: aplique o filtro da tabela (titular, instituição, tipo), role, e então crie, edite e exclua a "
            "sua entidade. Também edite em linha, se houver.",
            "Configurações gerais (política de senha, bloqueio, projeção recorrente): **leia o valor atual, salve o "
            "MESMO valor** e meça a resposta. Não mude política.",
            "Permissões: selecione outro usuário no filtro, marque e desmarque uma permissão e devolva o estado "
            "original. Confira se o usuário selecionado continua selecionado.",
            "Banco de dados: verificação de saúde pode rodar; **otimizar não**. Registre só a existência.",
        ],
    },
}

CRV = {
    "C1": {
        "territorio": "Carteira **id 1** (BRL), corretoras **1 e 2**. **DADOS REAIS (cópia da produção):** "
                      "1) Posição nova SÓ numa combinação carteira+corretora+ticker que **ainda não existe** (confira na "
                      "Carteira filtrando por carteira 1 e corretora); criar numa combinação existente **funde com a posição "
                      "real** (vira aporte) — se o formulário avisar de aporte, abertura anterior ou duplicata, **cancele**. "
                      "2) Nunca exclua nem encerre uma posição que existia antes; para desfazer um aporte, exclua só o "
                      "**movimento** que você criou. 3) Transações encerradas: crie com `[AUD-C1]` nas notas e exclua. "
                      "4) Opções: só em contrato que a carteira não tem; exclua no fim. Quantidade 1 em tudo.",
        "telas": ["/", "/transactions", "/options", "/positions/<int:position_id>"],
        "notas": [
            "A Carteira (`/`) é o centro: filtre por carteira, corretora e o que mais houver, e role. Então: nova "
            "posição, editar, movimento (aporte), encerrar parcial e excluir — tudo na posição que VOCÊ criou.",
            "Transações e Opções: filtre, opere (criar, editar, excluir; em opção também encerrar) e confira se a lista "
            "volta filtrada.",
            "O CRV declara que cada tela tem uma URL só: confira se os filtros aplicados **aparecem na URL** (`U`).",
        ],
    },
    "C2": {
        "territorio": "Carteira **id 2** (USD); proventos só nas corretoras **2 e 4**. Crie só proventos `[AUD-C2]` e exclua no fim.",
        "telas": ["/dividends", "/dividends/import"],
        "notas": [
            "Proventos: filtre por corretora, tipo, período e ticker (o que houver), role, crie, edite e exclua um "
            "provento seu. Teste também a edição a partir da lista filtrada.",
            "Importação de proventos: se pedir arquivo, `NAO_TESTAVEL`. Se for colar texto, **não** importe; só abra e "
            "cancele.",
            "Moeda: alterne BRL, USD e ALL e confira a propagação pelo menu (caso `G.<tela>`).",
        ],
    },
    "C3": {
        "territorio": "Carteira **id 3** (Simulada), corretora **3**. **DADOS REAIS (cópia da produção):** posição nova "
                      "SÓ em ticker que a carteira 3 ainda não tem (a Simulada rejeita segunda entrada na mesma chave); "
                      "nunca exclua nem altere posição que existia antes; quantidade 1; exclua a sua no fim.",
        "telas": ["/performance", "/risk", "/data-status"],
        "notas": [
            "Performance, Risco e Exposição são telas de leitura com filtros: aplique, role, recarregue (F5), volte e "
            "navegue pelo menu.",
            "Na carteira Simulada (filtrada em `/`), crie, edite e exclua uma posição `[AUD-C3]` e confira os filtros.",
            "Procure no menu as telas de Exposição (por ativo, corretora, mercado) e teste os filtros delas.",
        ],
    },
    "C4": {
        "territorio": "Entidades **criadas por você** `[AUD-C4]`: corretora, ticker, carteira, vencimento e contrato de opção. **Não** altere nem exclua registros existentes. Cotações: nada de importar, apagar por data ou excluir.",
        "telas": ["/tables/brokers", "/tables/tickers", "/tables/portfolios", "/tables/options/contracts",
                  "/tables/options/expirations", "/quotes", "/settings", "/preferences", "/users"],
        "notas": [
            "Este lote roda **sozinho**, depois de C1, C2 e C3.",
            "Tabelas: filtre, role, crie a sua entidade, edite, desative e reative (se houver) e exclua.",
            "Preferências, configurações e modo discreto: leia o valor, salve o mesmo valor (ou alterne e desfaça) e "
            "meça a resposta.",
            "Usuários: só abra e filtre; não crie usuário.",
        ],
    },
}

CFG = CB if SIS == "cb" else CRV
for lid, c in CFG.items():
    L = [f"# Lote {lid} ({SIS.upper()})", "", f"Base: {URL}", "", f"**Território:** {c['territorio']}", "",
         "Leia antes `PROTOCOLO.md`.", "", "## Notas", ""] + [f"- {n}" for n in c["notas"]] + ["", "## Casos", ""]
    for i, tela in enumerate(c["telas"], 1):
        if tela not in telas_inv:
            print(f"aviso: {lid} {tela} fora do inventário (sem filtro nem operação detectados)")
        f = filtros.get(tela, [])
        L.append(f"### {i}. `{tela}`")
        L.append(f"- filtros detectados: {', '.join(f) or 'nenhum no template (procure na tela)'}")
        L.append(f"- **{i}.F** aplicar filtros, conferir a URL (U), F5, voltar e ir e voltar pelo menu.")
        for j, (ep, o) in enumerate(ops.get(tela, {}).items(), 1):
            extra = f"; resposta prevista: {o['resp']}" if o["resp"] else ""
            L.append(f"- **{i}.{j}** operação `{ep}`" + (f" ({o['n']} controles)" if o["n"] > 1 else "") + extra)
        L.append(f"- **{i}.X** outras operações visíveis na tela e não listadas acima: teste e registre como `{i}.X<n>`.")
        L.append("")
    (BASE / "lotes" / f"LOTE_{lid}.md").write_text("\n".join(L) + "\n", encoding="utf-8", newline="")
    print(lid, len(c["telas"]), "telas")
