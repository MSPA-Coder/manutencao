"""Gera lotes/LOTE_<B>.md: reprodução às cegas (só passos, sem código nem diagnóstico).

Uso: python gerar_b1.py <sistema> <id_lote> <ids_executores separados por vírgula> <território>
"""
import csv
import random
import sys
from pathlib import Path

SIS, LID, EXEC, TERR = sys.argv[1], sys.argv[2], sys.argv[3].split(","), sys.argv[4]
BASE = Path(__file__).parent
URL = {"cb": "http://127.0.0.1:5201", "crv": "http://127.0.0.1:5301"}[SIS]

nao_ok, ok = [], []
for e in EXEC:
    for r in csv.DictReader(open(BASE / "status" / f"ACHADOS_{e}.csv", encoding="utf-8")):
        cod = (r.get("codigo") or "").strip()
        obs = (r.get("obs") or "") + (r.get("url_perdeu") or "")
        if not cod or "NAO TESTADO" in obs.upper() or "NAO_TESTAVEL" in cod.upper() or cod == "LATERAL":
            continue
        if cod != "OK" and "padrao" in obs.lower() and "currency=BRL" in obs and cod in ("R",) and not (r.get("filtros_mudaram") or "").strip():
            # recarga com parâmetro padrão: continua sendo R, reproduzir mesmo assim
            pass
        item = {"origem": f"{e}:{r['caso']}", "tela": r["tela_url_antes"], "op": r["operacao"], "var": r["variacao"]}
        (ok if cod == "OK" else nao_ok).append(item)

random.seed(20261009)
amostra = random.sample(ok, max(1, round(len(ok) * 0.2))) if ok else []
casos = nao_ok + amostra
random.shuffle(casos)  # o adversário não sabe quais eram achados
if len(sys.argv) > 5:  # "k/n": fica com a k-ésima de n fatias
    k, n = map(int, sys.argv[5].split("/"))
    casos = casos[k - 1::n]

L = [f"# Lote {LID} ({SIS.upper()}): reprodução às cegas", "", f"Base: {URL}", "",
     f"**Território para escrita:** {TERR}", "",
     "Leia antes `PROTOCOLO.md`. Este lote **não** traz o resultado que outro agente obteve, de propósito: "
     "meça do zero, com a sonda, e classifique com o seu próprio código.", "",
     "Para cada caso:",
     "1. abra a tela indicada (pode ajustar ids e valores para o seu território, mantendo os **mesmos "
     "nomes de filtro**);",
     "2. faça a operação e a variação;",
     "3. registre em `status/ACHADOS_<SEU_ID>.csv`, com a coluna `caso` igual ao **R-número** abaixo.", "",
     "Se um passo for ambíguo, escolha a leitura mais natural para um usuário e anote em `obs`.", "",
     "## Casos", ""]
mapa = []
for i, c in enumerate(casos, 1):
    L.append(f"- **R{i:03d}**: tela `{c['tela'] or '(ver operação)'}`; operação: {c['op']}; variação: {c['var']}")
    mapa.append(f"R{i:03d},{c['origem']}")
(BASE / "lotes" / f"LOTE_{LID}.md").write_text("\n".join(L) + "\n", encoding="utf-8", newline="")
# Mapa R-número -> caso original: só para o coordenador.
(BASE / "status" / f"MAPA_{LID}.csv").write_text("rnum,origem\n" + "\n".join(mapa) + "\n", encoding="utf-8", newline="")
print(LID, "casos:", len(casos), "(achados", len(nao_ok), "+ amostra OK", len(amostra), ")")
