"""Aplica arquivos `.dropignore` marcando itens com o atributo `com.dropbox.ignored`.

O Dropbox não lê arquivo de ignore; ele obedece a um fluxo NTFS alternativo
chamado `com.dropbox.ignored` gravado no próprio arquivo ou pasta. Esta
ferramenta lê os `.dropignore` (sintaxe do `.gitignore`: `#`, `!`, `/` final
para pasta, `/` inicial ou interno para ancorar, `*`, `?` e `**`) e grava ou
confere esse atributo.

A marca acompanha o item quando ele é movido dentro do mesmo disco, então um
projeto marcado em `C:\\Dev` já chega ao Dropbox com os segredos ignorados. Pasta
marcada vale para tudo o que nascer dentro dela; arquivo solto perde a marca se
for apagado e recriado, por isso rode `--aplicar` de novo antes de mover.

Uso:
    py -3 dropignore.py RAIZ             # confere; sai com 1 se faltar marca
    py -3 dropignore.py RAIZ --aplicar   # grava as marcas que faltam
    py -3 dropignore.py RAIZ --listar    # mostra também o que já está marcado
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ARQUIVO = ".dropignore"
FLUXO = "com.dropbox.ignored"
NUNCA_DESCER = {".git"}


@dataclass(frozen=True)
class Regra:
    base: Path
    regex: re.Pattern[str]
    negada: bool
    so_pasta: bool
    ancorada: bool


def _glob_para_regex(padrao: str) -> str:
    saida, i = [], 0
    while i < len(padrao):
        c = padrao[i]
        if padrao.startswith("**/", i):
            saida.append("(?:.*/)?")
            i += 3
            continue
        if padrao.startswith("**", i):
            saida.append(".*")
            i += 2
            continue
        if c == "*":
            saida.append("[^/]*")
        elif c == "?":
            saida.append("[^/]")
        else:
            saida.append(re.escape(c))
        i += 1
    return "".join(saida)


def ler_regras(arquivo: Path) -> list[Regra]:
    regras = []
    for linha in arquivo.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#"):
            continue
        negada = linha.startswith("!")
        if negada:
            linha = linha[1:]
        so_pasta = linha.endswith("/")
        linha = linha.rstrip("/")
        ancorada = "/" in linha
        linha = linha.lstrip("/")
        if not linha:
            continue
        regras.append(Regra(arquivo.parent, re.compile(_glob_para_regex(linha) + r"\Z", re.I),
                            negada, so_pasta, ancorada))
    return regras


def casa(regras: list[Regra], caminho: Path, eh_pasta: bool) -> bool:
    """Última regra que casa decide, como no .gitignore."""
    resultado = False
    for r in regras:
        if r.so_pasta and not eh_pasta:
            continue
        try:
            rel = caminho.relative_to(r.base).as_posix()
        except ValueError:
            continue
        alvo = rel if r.ancorada else caminho.name
        if r.regex.match(alvo):
            resultado = not r.negada
    return resultado


def marcado(p: Path) -> bool:
    try:
        with open(f"{p}:{FLUXO}", encoding="utf-8") as f:
            return f.read().strip() == "1"
    except OSError:
        return False


def marcar(p: Path) -> None:
    with open(f"{p}:{FLUXO}", "w", encoding="utf-8") as f:
        f.write("1")


def varrer(raiz: Path):
    """Devolve (item, eh_pasta) para cada item que os .dropignore mandam ignorar."""
    pilha: dict[Path, list[Regra]] = {}
    for atual, pastas, arquivos in os.walk(raiz):
        atual_p = Path(atual)
        herdadas = pilha.get(atual_p.parent, []) if atual_p != raiz else []
        proprias = ler_regras(atual_p / ARQUIVO) if ARQUIVO in arquivos else []
        regras = herdadas + proprias
        pilha[atual_p] = regras
        descer = []
        for nome in sorted(pastas):
            p = atual_p / nome
            if p.is_symlink():
                continue
            if regras and casa(regras, p, True):
                yield p, True
            elif nome not in NUNCA_DESCER:
                descer.append(nome)
        pastas[:] = descer
        for nome in sorted(arquivos):
            p = atual_p / nome
            if regras and casa(regras, p, False):
                yield p, False


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("raiz", type=Path)
    ap.add_argument("--aplicar", action="store_true", help="grava as marcas que faltam")
    ap.add_argument("--listar", action="store_true", help="mostra também os itens já marcados")
    a = ap.parse_args(argv)
    if os.name != "nt":
        print("O atributo do Dropbox usado aqui é um fluxo NTFS: rode no Windows.", file=sys.stderr)
        return 2
    raiz = a.raiz.resolve()
    faltando = ja = 0
    for p, eh_pasta in varrer(raiz):
        rel = p.relative_to(raiz).as_posix() + ("/" if eh_pasta else "")
        if marcado(p):
            ja += 1
            if a.listar:
                print(f"  ok        {rel}")
            continue
        faltando += 1
        if a.aplicar:
            marcar(p)
            print(f"  marcado   {rel}")
        else:
            print(f"  FALTA     {rel}")
    print(f"\n{ja} já marcados; {faltando} {'marcados agora' if a.aplicar else 'sem marca'}.")
    return 0 if (a.aplicar or faltando == 0) else 1


if __name__ == "__main__":
    sys.exit(main())
