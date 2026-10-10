"""Cruza a reprodução às cegas (B) com o resultado original (A). Uso: python cruzar_b.py B1 B1b"""
import csv
import sys
from collections import Counter
from pathlib import Path

BASE = Path(__file__).parent / "status"
orig = {}
for f in list(BASE.glob("ACHADOS_A*.csv")) + list(BASE.glob("ACHADOS_C*.csv")):
    eid = f.stem.split("_", 1)[1]
    for r in csv.DictReader(open(f, encoding="utf-8")):
        orig.setdefault(f"{eid}:{r['caso']}", []).append((r["codigo"].strip(), r["operacao"], r["variacao"]))

tab = Counter()
div = []
for lid in sys.argv[1:]:
    mapa = {r["rnum"]: r["origem"] for r in csv.DictReader(open(BASE / f"MAPA_{lid}.csv", encoding="utf-8"))}
    lote = Path(__file__).parent / "lotes" / f"LOTE_{lid}.md"
    desc = {}
    for linha in open(lote, encoding="utf-8"):
        if linha.startswith("- **R"):
            desc[linha[4:8]] = linha
    for r in csv.DictReader(open(BASE / f"ACHADOS_{lid}.csv", encoding="utf-8")):
        rn = r["caso"].strip()[:4]
        if rn not in mapa:
            continue
        cb = r["codigo"].strip()
        alvo = desc.get(rn, "")
        cands = orig.get(mapa[rn], [])
        # o caso original pode ter várias variações; pega a que bate com operação+variação do lote
        ca = next((c for c, op, var in cands if op in alvo and var in alvo), cands[0][0] if cands else "?")
        if not cb or cb.upper().startswith("NAO"):
            tab["não executado"] += 1
            continue
        ok_a, ok_b = ca == "OK", cb == "OK"
        if ok_a and ok_b:
            tab["OK confirmado"] += 1
        elif not ok_a and not ok_b:
            tab["achado reproduzido" + (" (mesmo código)" if ca == cb else " (código diferente)")] += 1
            if ca != cb:
                div.append((lid, rn, mapa[rn], ca, cb, r["obs"][:90]))
        elif ok_a and not ok_b:
            tab["FALSO NEGATIVO em A (B achou problema)"] += 1
            div.append((lid, rn, mapa[rn], ca, cb, r["obs"][:90]))
        else:
            tab["NÃO reproduzido (A achou, B não)"] += 1
            div.append((lid, rn, mapa[rn], ca, cb, r["obs"][:90]))
for k, v in tab.most_common():
    print(f"{v:4d}  {k}")
print("\nDivergências (lote, R, origem, A, B, obs B):")
for d in div:
    print(" | ".join(d))
