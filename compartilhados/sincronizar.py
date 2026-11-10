"""Confere e copia o que é igual em vários repositórios, e confere a documentação de orientação.

Até 02/11/2026 esses arquivos eram mantidos iguais à mão: cada mudança virava
uma edição e um commit em cada repositório, e uma cópia já tinha divergido.
Agora cada um tem uma cópia canônica neste repositório e este script a leva aos
demais. Desde 03/11/2026 ele também mantém o bloco de regras comuns dentro de
cada `AGENTS.md` e reprova a orientação que voltou a crescer por acúmulo.

    python compartilhados/sincronizar.py            confere; sai 1 se algo divergir
    python compartilhados/sincronizar.py --aplicar  copia/atualiza o que diverge
    ... --pular=SharedAuth                          deixa um repositório de fora

O que é conferido:

1. Cópias inteiras (`COPIAS`): iguais à canônica.
2. Bloco comum (`AGENTS-comum.md`, mais `AGENTS-comum-vps.md` nos repositórios
   de `COM_VPS`): igual, entre os marcadores, no `AGENTS.md` de cada
   repositório de `COM_BLOCO`. `--aplicar` insere depois do título se faltar.
3. `AGENTS.md`: no máximo `TETO_PALAVRAS` fora do bloco, e todo caminho citado
   entre crases existe.
4. `AGENTS.md`, `README.md` e `docs/`: nenhuma frase do modelo de entrega
   anterior a 20/10/2026 (CI que reprova, PR obrigatório, checks antes do
   merge). Relatórios datados, ADRs e `docs/historico/` ficam de fora: são
   registro do que foi.

Os repositórios são irmãos deste checkout (mesma pasta-mãe). O script só grava
arquivos; o commit continua em cada repositório. Comparação e gravação em LF,
sem BOM: o `core.autocrlf` do Windows põe CRLF no checkout, o que não é
diferença de conteúdo.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
MANUTENCAO = AQUI.parent
BASE = MANUTENCAO.parent

APPS = ["ControleBancario", "ControleRendaVariavel", "ConfortoTermico", "MegaSena"]
COM_TESTES = APPS + ["BackupRestore", "FinancasMCP", "SharedAuth", "Site_Mp-solucoes"]
# Sites estáticos pequenos: só o bloco, sem docs/TESTES.md.
SITES = ["VivaPasso", "VillaRica", "PlayBook"]
COM_BLOCO = COM_TESTES + ["WealthfolioTeste", MANUTENCAO.name] + SITES
COM_QUALITY = [r for r in COM_TESTES if r != "ControleBancario"]

# canônica (relativa a este repositório) -> [(repositório, caminho lá)]
COPIAS: dict[str, list[tuple[str, str]]] = {
    "docs/TESTES.md": [(r, "docs/TESTES.md") for r in COM_TESTES],
    "docs/contratos/patrimonio-v4.schema.json": [
        ("ControleBancario", "tests/contrato/patrimonio-v4.schema.json"),
        ("ControleRendaVariavel", "tests/contrato/patrimonio-v4.schema.json"),
        ("WealthfolioTeste", "addons/controle-patrimonial-sync/sim/contrato/patrimonio-v4.schema.json"),
    ],
    "docs/contratos/crv-fechamento-1.schema.json": [
        ("ControleBancario", "tests/contrato/crv-fechamento-1.schema.json"),
        ("ControleRendaVariavel", "tests/contrato/crv-fechamento-1.schema.json"),
    ],
    # O que o CB publica ao CRV, gerado pela suíte do CB e lido pela do CRV.
    "docs/contratos/exemplos/cb-snapshot-vinculo.json": [
        ("ControleBancario", "tests/contrato/exemplo-cb-snapshot-vinculo.json"),
        ("ControleRendaVariavel", "tests/contrato/exemplo-cb-snapshot-vinculo.json"),
    ],
    "compartilhados/Dockerfile.browser": [(r, "Dockerfile.browser") for r in APPS],
    "compartilhados/provision-db-runtime.sh": [(r, "scripts/provision-db-runtime.sh") for r in APPS],
    "compartilhados/gerar_relatorio.py": [(r, "docs/security-audit/gerar_relatorio.py") for r in APPS],
    # O CB tem script próprio, mais antigo, que aceita argumentos do Compose.
    "compartilhados/quality.ps1": [(r, "scripts/quality.ps1") for r in COM_QUALITY],
}

BLOCO = "compartilhados/AGENTS-comum.md"
# Só o que é implantado por `deploy.sh` (e o repositório dono dele) recebe as
# regras de deploy e de dados de produção: em biblioteca, ferramenta de host ou
# site estático elas eram texto sem aplicação.
BLOCO_VPS = "compartilhados/AGENTS-comum-vps.md"
COM_VPS = APPS + ["WealthfolioTeste", MANUTENCAO.name, "VivaPasso", "VillaRica"]
INICIO = ("<!-- comum: início. Cópia de _manutencao/compartilhados/AGENTS-comum.md;"
          " mude lá e rode sincronizar.py --aplicar. -->")
FIM = "<!-- comum: fim -->"
TETO_PALAVRAS = 900

# Frases do modelo de entrega anterior a 20/10/2026. Cada uma já levou um agente
# a esperar CI, abrir PR ou tratar aviso como portão.
FRASES_VELHAS = [
    (re.compile(r"reprova\w* (?:a |na )?CI|reprovam a CI", re.I), "a CI não reprova nada: é só aviso"),
    (re.compile(r"status check obrigat", re.I), "não há status check obrigatório no main"),
    (re.compile(r"antes do merge|checks precisam passar", re.I), "não há merge: o commit vai direto ao main"),
    # só a ordem ("abra um PR"); "o workflow abre um PR" descreve automação, que continua por PR
    (re.compile(r"\babra (?:um )?PR\b", re.I), "o fluxo não usa PR (só automações como o Dependabot)"),
    (re.compile(r"auto-?merge", re.I), "o auto-merge foi removido; não é preciso citá-lo"),
    (re.compile(r"\b(?:os|nos|dos|aos) dois (?:VPS|servidores)\b", re.I),
     "só existe o VPS1 desde 05/11/2026"),
    # A tabela divergia da seção "Validação" do AGENTS.md do mesmo repositório.
    (re.compile(r"^#+ Validação proporcional\s*$"),
     "a validação por tipo de mudança mora na seção \"Validação\" do AGENTS.md"),
]
PULA_DOCS = re.compile(r"(^|/)(adr|historico|security-audit)/|\d{4}-\d{2}-\d{2}", re.I)

EXTENSOES = ("py", "sh", "md", "yaml", "yml", "toml", "json", "ps1", "txt", "js", "cjs", "html", "css",
             "sql", "conf", "service", "timer", "bat", "cfg", "ini", "lock")
CITACAO = re.compile(r"`([^`\s<>*%$~|]+)`")


def ler(caminho: Path) -> bytes:
    return caminho.read_bytes().replace(b"\r\n", b"\n")


def texto(caminho: Path) -> str:
    return ler(caminho).decode("utf-8")


def gravar(caminho: Path, conteudo: str) -> None:
    caminho.write_bytes(conteudo.encode("utf-8"))


def com_bloco(atual: str, bloco: str) -> str:
    """Devolve o AGENTS.md com o bloco comum entre os marcadores (inserido após o título se faltar)."""
    novo = f"{INICIO}\n{bloco.strip()}\n{FIM}"
    if INICIO.split(".")[0] in atual and FIM in atual:
        ini = atual.index(INICIO.split(".")[0])
        fim = atual.index(FIM) + len(FIM)
        return atual[:ini] + novo + atual[fim:]
    linhas = atual.split("\n")
    i = next((n for n, linha in enumerate(linhas) if linha.startswith("# ")), -1) + 1
    return "\n".join(linhas[:i] + ["", novo, ""] + linhas[i:]).replace("\n\n\n", "\n\n")


def fora_do_bloco(conteudo: str) -> str:
    if FIM not in conteudo:
        return conteudo
    ini = conteudo.find(INICIO.split(".")[0])
    return conteudo[:ini] + conteudo[conteudo.index(FIM) + len(FIM):]


def caminho_quebrado(repo: Path, cit: str) -> bool:
    cit = cit.replace("\\", "/").removeprefix("./")
    nome = cit.rstrip("/").rsplit("/", 1)[-1]
    eh_arquivo = "." in nome and nome.rsplit(".", 1)[-1] in EXTENSOES
    if not (eh_arquivo or (cit.endswith("/") and "/" in cit.rstrip("/"))):
        return False
    # nome solto (`compose.yaml`, `deploy.sh`) não diz onde procurar: só caminhos com pasta são conferidos
    if "/" not in cit.rstrip("/") or cit.startswith(("http", "/")) or ":" in cit:
        return False
    return not ((repo / cit).exists() or (BASE / cit.removeprefix("../")).exists())


def conferir_copias(aplicar: bool) -> int:
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
    return divergentes


def conferir_agents(aplicar: bool) -> tuple[int, int]:
    nucleo = texto(MANUTENCAO / BLOCO).strip()
    vps = texto(MANUTENCAO / BLOCO_VPS).strip()
    divergentes = problemas = 0
    for repo in COM_BLOCO:
        bloco = f"{nucleo}\n\n{vps}" if repo in COM_VPS else nucleo
        alvo = BASE / repo / "AGENTS.md"
        if not alvo.is_file():
            print(f"  ausente    {repo}/AGENTS.md")
            problemas += 1
            continue
        atual = texto(alvo)
        esperado = com_bloco(atual, bloco)
        if esperado != atual:
            divergentes += 1
            if aplicar:
                gravar(alvo, esperado)
                print(f"  bloco      {repo}/AGENTS.md atualizado")
                atual = esperado
            else:
                print(f"  DIFERENTE  {repo}/AGENTS.md: bloco comum ausente ou divergente")
        proprio = fora_do_bloco(atual)
        palavras = len(proprio.split())
        if palavras > TETO_PALAVRAS:
            problemas += 1
            print(f"  LONGO      {repo}/AGENTS.md: {palavras} palavras fora do bloco (teto {TETO_PALAVRAS});"
                  " para acrescentar, retire ou funda outra regra")
        for cit in sorted(set(CITACAO.findall(proprio))):
            if caminho_quebrado(BASE / repo, cit):
                problemas += 1
                print(f"  CAMINHO    {repo}/AGENTS.md cita `{cit}`, que não existe")
    return divergentes, problemas


def conferir_frases() -> int:
    problemas = 0
    for repo in COM_BLOCO:
        raiz = BASE / repo
        candidatos = [raiz / "AGENTS.md", raiz / "README.md", *sorted((raiz / "docs").rglob("*.md"))]
        for arq in candidatos:
            rel = arq.relative_to(raiz).as_posix()
            if not arq.is_file() or PULA_DOCS.search(rel) or arq.name == "TESTES.md":
                continue
            for n, linha in enumerate(texto(arq).split("\n"), 1):
                for padrao, motivo in FRASES_VELHAS:
                    if padrao.search(linha):
                        problemas += 1
                        print(f"  VELHO      {repo}/{rel}:{n}: {motivo}")
    return problemas


def main(argv: list[str]) -> int:
    aplicar = "--aplicar" in argv
    # --pular=Repo1,Repo2: deixa de fora um checkout ocupado por outro trabalho
    pular = {r for a in argv if a.startswith("--pular=") for r in a.split("=", 1)[1].split(",") if r}
    for nome in pular:
        for destinos in COPIAS.values():
            destinos[:] = [d for d in destinos if d[0] != nome]
    COM_BLOCO[:] = [r for r in COM_BLOCO if r not in pular]
    copias = conferir_copias(aplicar)
    blocos, problemas = conferir_agents(aplicar)
    problemas += conferir_frases()
    divergentes = copias + blocos
    if divergentes == 0 and problemas == 0:
        print("Cópias e blocos iguais às canônicas; orientação dentro dos limites.")
        return 0
    if aplicar and problemas == 0:
        print(f"{divergentes} cópia(s) ou bloco(s) atualizado(s); commite em cada repositório.")
        return 0
    if divergentes and not aplicar:
        print(f"{divergentes} cópia(s) ou bloco(s) diferente(s). Rode com --aplicar para copiar.")
    if problemas:
        print(f"{problemas} problema(s) de orientação: corrija o texto (o script não reescreve prosa).")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
