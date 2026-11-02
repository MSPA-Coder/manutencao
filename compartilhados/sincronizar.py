"""Confere e copia os arquivos que são iguais em vários repositórios.

Até 02/11/2026 esses arquivos eram mantidos iguais à mão: cada mudança virava
uma edição e um commit em cada repositório (uns 60 commits desde setembro só
para isso), e uma cópia já tinha divergido. Agora cada um tem uma cópia
canônica neste repositório e este script a leva aos demais.

    python compartilhados/sincronizar.py            confere; sai 1 se algo divergir
    python compartilhados/sincronizar.py --aplicar  copia a canônica para quem diverge

Os repositórios são irmãos deste checkout (mesma pasta-mãe). O script só grava
arquivos; o commit continua em cada repositório, junto com a mudança que motivou
a cópia. Comparação e gravação em LF, sem BOM: o `core.autocrlf` do Windows põe
CRLF no checkout, o que não é diferença de conteúdo.
"""

from __future__ import annotations

import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
MANUTENCAO = AQUI.parent
BASE = MANUTENCAO.parent

APPS = ["ControleBancario", "ControleRendaVariavel", "ConfortoTermico", "MegaSena"]
COM_TESTES = APPS + ["BackupRestore", "FinancasMCP", "SharedAuth", "Site_Mp-solucoes"]

# canônica (relativa a este repositório) -> [(repositório, caminho lá)]
COPIAS: dict[str, list[tuple[str, str]]] = {
    "docs/TESTES.md": [(r, "docs/TESTES.md") for r in COM_TESTES],
    "docs/contratos/patrimonio-v4.schema.json": [
        ("ControleBancario", "tests/contrato/patrimonio-v4.schema.json"),
        ("ControleRendaVariavel", "tests/contrato/patrimonio-v4.schema.json"),
        ("WealthfolioTeste", "addons/controle-patrimonial-sync/sim/contrato/patrimonio-v4.schema.json"),
    ],
    "compartilhados/Dockerfile.browser": [(r, "Dockerfile.browser") for r in APPS],
    "compartilhados/provision-db-runtime.sh": [(r, "scripts/provision-db-runtime.sh") for r in APPS],
    "compartilhados/gerar_relatorio.py": [(r, "docs/security-audit/gerar_relatorio.py") for r in APPS],
}


def ler(caminho: Path) -> bytes:
    return caminho.read_bytes().replace(b"\r\n", b"\n")


def main(argv: list[str]) -> int:
    aplicar = "--aplicar" in argv
    divergentes = 0
    for canonica, destinos in COPIAS.items():
        origem = ler(MANUTENCAO / canonica)
        for repo, rel in destinos:
            alvo = BASE / repo / rel
            if not (BASE / repo).is_dir():
                print(f"  ausente    {repo} (repositório não encontrado ao lado do manutencao)")
                divergentes += 1
                continue
            if alvo.is_file() and ler(alvo) == origem:
                continue
            divergentes += 1
            if aplicar:
                alvo.parent.mkdir(parents=True, exist_ok=True)
                alvo.write_bytes(origem)
                print(f"  copiado    {repo}/{rel}")
            else:
                print(f"  DIFERENTE  {repo}/{rel}  (canônica: {canonica})")
    if divergentes == 0:
        print("Todas as cópias iguais às canônicas.")
        return 0
    if aplicar:
        print(f"{divergentes} cópia(s) atualizada(s); commite em cada repositório.")
        return 0
    print(f"{divergentes} cópia(s) diferente(s). Rode com --aplicar para copiar.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
