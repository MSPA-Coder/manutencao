"""Inventário estático para a auditoria de filtros e recargas (CB e CRV).

Uso: python inventario.py <cb|crv> <raiz_do_repo> <urls.json> <saida_dir>

Liga rota -> view -> templates (com include/import/extends) e extrai, por tela:
  - controles de filtro (forms GET, [data-table-filter], hx-get disparado por change);
  - operações de escrita (form POST, hx-post/put/patch/delete) e o endpoint de destino;
  - o que cada endpoint de escrita devolve (redirect com/sem query, HX-*, fragmento, 204).
É um checklist aproximado, não um contrato: os agentes confirmam no navegador.
"""
from __future__ import annotations

import ast
import csv
import json
import re
import sys
from collections import defaultdict
from html.parser import HTMLParser
from pathlib import Path

SIS, RAIZ, URLS, SAIDA = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4])
SAIDA.mkdir(parents=True, exist_ok=True)
TPL_DIR = RAIZ / ("templates" if SIS == "cb" else "app/templates")

texto = URLS.read_text(encoding="utf-8")
rotas = json.loads(texto[texto.index("["):])
rotas = [r for r in rotas if not r["modulo"].startswith(("django.", "flask", "sharedauth"))]

# ---------------------------------------------------------------- views (AST)
_mod_cache: dict[str, tuple[str, dict[str, ast.AST]]] = {}


def modulo(nome: str):
    if nome in _mod_cache:
        return _mod_cache[nome]
    caminho = RAIZ / (nome.replace(".", "/") + ".py")
    if not caminho.exists():
        _mod_cache[nome] = ("", {})
        return _mod_cache[nome]
    fonte = caminho.read_text(encoding="utf-8")
    arvore = ast.parse(fonte)
    funcs: dict[str, ast.AST] = {}
    for no in ast.walk(arvore):
        if isinstance(no, (ast.FunctionDef, ast.ClassDef)):
            funcs.setdefault(no.name, no)
    _mod_cache[nome] = (fonte, funcs)
    return _mod_cache[nome]


def corpo_com_ajudantes(nome_mod: str, func: str, prof: int = 2) -> list[tuple[str, str]]:
    """Fonte da função e das funções do mesmo módulo que ela chama (até `prof` níveis)."""
    fonte, funcs = modulo(nome_mod)
    vistos, fila, saida = set(), [(func.split(".")[-1], 0)], []
    while fila:
        f, n = fila.pop(0)
        if f in vistos or f not in funcs:
            continue
        vistos.add(f)
        no = funcs[f]
        # O segmento do AST começa no `def`; os decoradores (@require_POST) ficam antes.
        inicio = min([d.lineno for d in getattr(no, "decorator_list", [])] + [no.lineno])
        saida.append((f, "\n".join(fonte.splitlines()[inicio - 1:no.end_lineno])))
        if n < prof:
            for sub in ast.walk(no):
                if isinstance(sub, ast.Call) and isinstance(sub.func, ast.Name) and sub.func.id in funcs:
                    fila.append((sub.func.id, n + 1))
    return saida


RE_TPL = re.compile(r"""["']([\w/\-.]+\.html)["']""")
RE_REDIRECT = re.compile(r"\bredirect\(([^\n]*)")


def analisar_view(r: dict) -> dict:
    partes = corpo_com_ajudantes(r["modulo"], r["funcao"])
    fonte = "\n".join(s for _, s in partes)
    principal = partes[0][1] if partes else ""
    metodos = set(r.get("metodos") or [])
    if not metodos:
        if re.search(r"require_POST|require_http_methods\(\[?['\"]POST", principal):
            metodos = {"POST"}
        elif "request.method" in principal and "POST" in principal:
            metodos = {"GET", "POST"}
        else:
            metodos = {"GET"}
    respostas = set()
    for _, trecho in partes:
        for m in RE_REDIRECT.finditer(trecho):
            alvo = m.group(1)
            if re.search(r"request\.(GET|args|full_path|query_string)|query|params|urlencode|next|volta", alvo):
                respostas.add("redirect+query")
            elif re.search(r"request\.(GET|args)|QUERY_STRING|redirect_qs|query_params|urlencode", trecho):
                respostas.add("redirect+query?")  # monta a query em outra linha: conferir
            else:
                respostas.add("redirect-sem-query")
    for h in ("HX-Redirect", "HX-Refresh", "HX-Trigger", "HX-Location", "HX-Push-Url", "HX-Replace-Url", "HX-Reswap", "HX-Retarget"):
        if h in fonte:
            respostas.add(h)
    if "HttpResponseClientRefresh" in fonte:
        respostas.add("HX-Refresh")
    if "HttpResponseClientRedirect" in fonte:
        respostas.add("HX-Redirect")
    if re.search(r"status=204|, 204\)|HTTPStatus.NO_CONTENT", fonte):
        respostas.add("204")
    htmx = bool(re.search(r"request\.htmx|is_htmx|HX-Request|hx_request|quer_fragmento", fonte))
    ajud = [n for n, _ in partes[1:] if "redirect" in n or "response" in n.lower() or "resposta" in n]
    return {
        "metodos": sorted(metodos),
        "templates": sorted(set(RE_TPL.findall(fonte))),
        "respostas": sorted(respostas) or (["render"] if RE_TPL.search(fonte) else ["?"]),
        "ramo_htmx": htmx,
        "ajudantes": ajud,
    }


# ---------------------------------------------------------------- templates
RE_INC = re.compile(r"""\{%-?\s*(include|extends|import|from)\s+["']([^"']+)["']""")


def fecho(tpl: str, vistos=None) -> list[str]:
    vistos = vistos if vistos is not None else []
    if tpl in vistos or tpl == "base.html":
        return vistos
    caminho = TPL_DIR / tpl
    if not caminho.exists():
        return vistos
    vistos.append(tpl)
    for _, filho in RE_INC.findall(caminho.read_text(encoding="utf-8")):
        fecho(filho, vistos)
    return vistos


RE_URLNAME = re.compile(r"""(?:\{%\s*url|url_for\()\s*['"]([\w:.\-]+)['"]""")


class Extrator(HTMLParser):
    def __init__(self, origem: str):
        super().__init__(convert_charrefs=True)
        self.origem = origem
        self.form: dict | None = None
        self.filtros: list[dict] = []
        self.escritas: list[dict] = []
        self.hx_gets: list[dict] = []

    def handle_starttag(self, tag, attrs):
        a = {k: (v or "") for k, v in attrs if k and not k.startswith("{")}
        linha = self.getpos()[0]
        if tag == "form":
            metodo = (a.get("method") or "get").lower()
            alvo = a.get("hx-post") or a.get("hx-put") or a.get("hx-patch") or a.get("hx-delete") or a.get("action", "")
            self.form = {"metodo": metodo, "hx": bool(set(a) & {"hx-post", "hx-get", "hx-put", "hx-patch", "hx-delete"}), "linha": linha}
            if metodo == "post" or any(k in a for k in ("hx-post", "hx-put", "hx-patch", "hx-delete")):
                self.escritas.append(self._op("form", a, alvo, linha))
            return
        if tag in ("input", "select", "textarea"):
            nome = a.get("name", "")
            tipo = a.get("type", "")
            if not nome or nome in ("csrf_token", "csrfmiddlewaretoken") or tipo in ("submit", "button"):
                pass
            elif "data-table-filter" in a or (self.form and self.form["metodo"] == "get") or (
                a.get("hx-get") and "change" in a.get("hx-trigger", "change")
            ):
                self.filtros.append({"nome": nome, "tag": tag, "tipo": tipo or tag, "hidden": tipo == "hidden", "linha": linha,
                                     "hx_get": "hx-get" in a or bool(self.form and self.form["hx"])})
        for verbo in ("hx-post", "hx-put", "hx-patch", "hx-delete"):
            if verbo in a and tag != "form":
                self.escritas.append(self._op(tag, a, a[verbo], linha, verbo))
        if "hx-get" in a and tag not in ("form", "select", "input"):
            self.hx_gets.append({"tag": tag, "url": self._nome_url(a["hx-get"]), "target": a.get("hx-target", ""),
                                 "swap": a.get("hx-swap", ""), "trigger": a.get("hx-trigger", ""), "linha": linha,
                                 "push": a.get("hx-push-url", "")})

    def handle_endtag(self, tag):
        if tag == "form":
            self.form = None

    @staticmethod
    def _nome_url(txt: str) -> str:
        m = RE_URLNAME.search(txt)
        return m.group(1) if m else txt.strip()[:80]

    def _op(self, tag, a, alvo, linha, verbo=None):
        return {"tag": tag, "verbo": verbo or ("hx-post" if "hx-post" in a else "POST"), "url": self._nome_url(alvo),
                "target": a.get("hx-target", ""), "swap": a.get("hx-swap", ""), "include": a.get("hx-include", ""),
                "confirm": bool(a.get("hx-confirm") or a.get("data-confirm") or "confirm(" in a.get("onsubmit", "")),
                "push": a.get("hx-push-url", ""), "boost": a.get("hx-boost", ""), "linha": linha}


_tpl_cache: dict[str, Extrator] = {}


def extrair(tpl: str) -> Extrator:
    if tpl not in _tpl_cache:
        e = Extrator(tpl)
        e.feed((TPL_DIR / tpl).read_text(encoding="utf-8"))
        _tpl_cache[tpl] = e
    return _tpl_cache[tpl]


# ---------------------------------------------------------------- JS
def varrer_js() -> list[str]:
    pastas = [RAIZ / "static/js"] if SIS == "cb" else [RAIZ / "app/static"]
    achados = []
    padroes = re.compile(r"location\.(reload|href\s*=|assign|replace)|window\.location\s*=|\.submit\(\)|htmx\.ajax|history\.(push|replace)State|requestSubmit")
    for pasta in pastas:
        for f in sorted(pasta.rglob("*.js")):
            if "vendor" in f.parts or f.name.endswith(".min.js"):
                continue
            for i, l in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
                if padroes.search(l) and not l.strip().startswith(("//", "*", "/*")):
                    achados.append(f"{f.relative_to(RAIZ).as_posix()}:{i}: {l.strip()[:140]}")
    for f in sorted(TPL_DIR.rglob("*.html")):
        for i, l in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if padroes.search(l):
                achados.append(f"{f.relative_to(RAIZ).as_posix()}:{i}: {l.strip()[:140]}")
    return achados


# ---------------------------------------------------------------- montagem
views = {r["nome"]: {**r, **analisar_view(r)} for r in rotas}
por_nome_curto = defaultdict(list)
for n in views:
    por_nome_curto[n.split(":")[-1].split(".")[-1]].append(n)


def resolver(nome_url: str) -> str:
    if nome_url in views:
        return nome_url
    cand = por_nome_curto.get(nome_url.split(":")[-1].split(".")[-1], [])
    return cand[0] if len(cand) == 1 else ""


telas, ops_csv, filtros_csv = [], [], []
for nome, v in sorted(views.items(), key=lambda x: x[1]["rota"]):
    if "GET" not in v["metodos"]:
        continue
    tpls = []
    for t in v["templates"]:
        fecho(t, tpls)
    if not tpls:
        continue
    pagina_cheia = any("extends" in (TPL_DIR / t).read_text(encoding="utf-8")[:400] for t in v["templates"] if (TPL_DIR / t).exists())
    fil, esc, hxg = [], [], []
    for t in tpls:
        e = extrair(t)
        fil += [{**f, "tpl": t} for f in e.filtros]
        esc += [{**o, "tpl": t, "endpoint": resolver(o["url"])} for o in e.escritas]
        hxg += [{**g, "tpl": t} for g in e.hx_gets]
    telas.append({"nome": nome, "rota": v["rota"], "pagina_cheia": pagina_cheia, "templates": tpls, "filtros": fil, "escritas": esc, "hx_gets": hxg, "respostas_get": v["respostas"], "ramo_htmx": v["ramo_htmx"]})
    for f in fil:
        filtros_csv.append([v["rota"], nome, f["nome"], f["tipo"], "sim" if f["hidden"] else "", "sim" if f["hx_get"] else "", f"{f['tpl']}:{f['linha']}"])
    for o in esc:
        ep = views.get(o["endpoint"], {})
        ops_csv.append([v["rota"], nome, o["verbo"], o["url"], o["endpoint"] or "?", ep.get("rota", ""), " ".join(ep.get("respostas", [])),
                        o["target"], o["swap"], o["include"], "sim" if o["confirm"] else "", f"{o['tpl']}:{o['linha']}"])

escritas_eps = sorted({n for n, v in views.items() if "POST" in v["metodos"] or any(m in v["metodos"] for m in ("PUT", "PATCH", "DELETE"))})
origem_por_ep = defaultdict(set)
for t in telas:
    for o in t["escritas"]:
        if o["endpoint"]:
            origem_por_ep[o["endpoint"]].add(t["rota"])

with open(SAIDA / f"operacoes_{SIS}.csv", "w", encoding="utf-8", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["tela", "tela_nome", "verbo", "url_template", "endpoint", "rota_endpoint", "respostas_endpoint", "hx_target", "hx_swap", "hx_include", "confirma", "origem"])
    w.writerows(ops_csv)
with open(SAIDA / f"filtros_{SIS}.csv", "w", encoding="utf-8", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["tela", "tela_nome", "filtro", "tipo", "oculto", "dispara_hx_get", "origem"])
    w.writerows(filtros_csv)
with open(SAIDA / f"endpoints_escrita_{SIS}.csv", "w", encoding="utf-8", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["endpoint", "rota", "metodos", "respostas", "ramo_htmx", "ajudantes", "telas_de_origem"])
    for n in escritas_eps:
        v = views[n]
        w.writerow([n, v["rota"], " ".join(v["metodos"]), " ".join(v["respostas"]), "sim" if v["ramo_htmx"] else "", " ".join(v["ajudantes"]), " ".join(sorted(origem_por_ep.get(n, [])))])

js = varrer_js()
(SAIDA / f"js_{SIS}.txt").write_text("\n".join(js) + "\n", encoding="utf-8", newline="")

# Resumo legível
L = [f"# Inventário {SIS.upper()}", "", f"- rotas de aplicação: {len(views)}",
     f"- telas GET com template: {len(telas)} (página cheia: {sum(t['pagina_cheia'] for t in telas)})",
     f"- endpoints de escrita: {len(escritas_eps)} (sem tela de origem encontrada: {sum(1 for n in escritas_eps if n not in origem_por_ep)})",
     f"- operações (tela × controle de escrita): {len(ops_csv)}", f"- controles de filtro: {len(filtros_csv)}",
     f"- trechos JS de navegação/recarga: {len(js)}", ""]
cont = defaultdict(int)
for n in escritas_eps:
    for r in views[n]["respostas"]:
        cont[r] += 1
L += ["## Respostas dos endpoints de escrita", ""] + [f"- `{k}`: {v}" for k, v in sorted(cont.items(), key=lambda x: -x[1])] + [""]
L += ["## Telas", ""]
for t in telas:
    if not t["pagina_cheia"]:
        continue
    nomes_f = sorted({f["nome"] for f in t["filtros"] if not f["hidden"]})
    L.append(f"### `{t['rota']}` ({t['nome']})")
    L.append(f"- filtros ({len(nomes_f)}): {', '.join(nomes_f) or '—'}")
    eps = defaultdict(int)
    for o in t["escritas"]:
        eps[(o["endpoint"] or o["url"], " ".join(views.get(o["endpoint"], {}).get("respostas", ["?"])))] += 1
    L.append(f"- operações ({len(t['escritas'])}):")
    L += [f"  - `{e}` → {r}" + (f" ×{n}" if n > 1 else "") for (e, r), n in sorted(eps.items())]
    L.append("")
L += ["## Endpoints de escrita sem tela de origem encontrada (achar no navegador)", ""]
L += [f"- `{n}` {views[n]['rota']} → {' '.join(views[n]['respostas'])}" for n in escritas_eps if n not in origem_por_ep]
(SAIDA / f"INVENTARIO_{SIS.upper()}.md").write_text("\n".join(L) + "\n", encoding="utf-8", newline="")
print("\n".join(L[:12]))
