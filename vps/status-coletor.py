#!/usr/bin/env python3
"""Coleta o estado DESTA máquina para o bot de status do Telegram.

    status-coletor.py <categoria>     imprime a seção em texto
    status-coletor.py --categorias    lista as categorias aceitas

Roda nos dois VPS. No VPS1 o bot o chama direto; no VPS2 ele é o único
comando que a chave do bot pode executar (`command=` no `authorized_keys`,
como o `backup-agent.sh`), e então a categoria chega em
`SSH_ORIGINAL_COMMAND`. Só lê: nenhuma categoria muda nada na máquina.

POR QUE SAIU DO BOT (25/10/2026). O bot vivia solto no VPS1, fora do Git, com
a lista de domínios escrita à mão (sem o Wealthfolio). Para o menu mostrar
também o VPS2, a coleta virou este programa à parte, o mesmo nas duas
máquinas, e os domínios passaram a vir dos vhosts habilitados do nginx, como
no `vigia.sh`.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from pathlib import Path

BACKUPS_DIR = Path(os.environ.get("BACKUPS_DIR", "/home/ubuntu/backups"))
NGINX_HABILITADOS = Path(os.environ.get("NGINX_HABILITADOS", "/etc/nginx/sites-enabled"))
_DOMINIO = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$")
_SERVER_NAME = re.compile(r"(?:^|[;{}\s])server_name\s+([^;]+);")


def rodar(cmd: str, timeout: int = 15) -> str:
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        saida = (r.stdout or "") + (r.stderr or "")
        return saida.strip() or "(sem saída)"
    except subprocess.TimeoutExpired:
        return "(tempo esgotado ao coletar)"
    except Exception as erro:  # coleta não pode derrubar quem chamou
        return f"(erro: {erro})"


def dominios(pasta: Path | None = None) -> list[str]:
    """Os domínios que o nginx desta máquina publica, sem o `_` padrão."""
    encontrados: set[str] = set()
    for vhost in sorted((pasta or NGINX_HABILITADOS).glob("*")):
        try:
            texto = vhost.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        texto = re.sub(r"#[^\n]*", "", texto)
        for grupo in _SERVER_NAME.findall(texto):
            for nome in grupo.split():
                if _DOMINIO.match(nome):
                    encontrados.add(nome)
    return sorted(encontrados)


def coletar_containers() -> str:
    saida = rodar("docker ps -a --format '{{.Names}}\t{{.Status}}' | sort")
    if saida == "(sem saída)":
        return "(nenhum contêiner nesta máquina)"
    linhas = []
    for linha in saida.splitlines():
        partes = linha.split("\t")
        if len(partes) != 2:
            linhas.append(linha)
            continue
        nome, status = partes
        bom = "healthy" in status or ("Up" in status and "unhealthy" not in status)
        linhas.append(f"{'✅' if bom else '⚠️'} {nome}: {status}")
    return "\n".join(linhas)


def coletar_vps() -> str:
    uptime = rodar("uptime -p")
    carga = rodar("cut -d' ' -f1-3 /proc/loadavg")
    memoria = rodar("free -h | sed -n '1,3p'")
    disco = rodar("df -h / | tail -1")
    pendentes = rodar("apt list --upgradable 2>/dev/null | tail -n +2 | wc -l")
    return (
        f"Uptime: {uptime}\n"
        f"Load average (1/5/15m): {carga}\n\n"
        f"Memória:\n{memoria}\n\n"
        f"Disco raiz:\n{disco}\n\n"
        f"Atualizações pendentes: {pendentes}"
    )


def coletar_docker_disco() -> str:
    return rodar("docker system df")


def coletar_backups(pasta: Path | None = None, agora: float | None = None) -> str:
    raiz = pasta or BACKUPS_DIR
    if not raiz.is_dir():
        return "(diretório de backups indisponível)"
    momento = time.time() if agora is None else agora
    linhas = []
    for projeto in sorted(p for p in raiz.iterdir() if p.is_dir()):
        marca = projeto / ".ultima_conferencia"
        try:
            horas = int((momento - marca.stat().st_mtime) // 3600)
        except OSError:
            linhas.append(f"⚠️ {projeto.name}: sem marcador de conferência")
            continue
        linhas.append(f"{'✅' if horas < 36 else '⚠️'} {projeto.name}: conferido há {horas}h")
    return "\n".join(linhas) or "(nenhum backup nesta máquina)"


def coletar_fail2ban() -> str:
    return rodar("sudo -n fail2ban-client status sshd")


def coletar_certificados() -> str:
    linhas = []
    for dominio in dominios():
        dias = rodar(
            f"fim=$(echo | openssl s_client -servername {dominio} -connect {dominio}:443 2>/dev/null "
            f"| openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2); "
            f"[ -n \"$fim\" ] && echo $(( ($(date -d \"$fim\" +%s) - $(date +%s)) / 86400 )) || echo '?'"
        )
        linhas.append(f"{'✅' if dias.isdigit() and int(dias) >= 15 else '⚠️'} {dominio}: {dias} dia(s)")
    return "\n".join(linhas) or "(nenhum domínio no nginx desta máquina)"


def coletar_endpoints() -> str:
    linhas = []
    for dominio in dominios():
        codigo = rodar(
            f"curl -sSL --max-time 10 -o /dev/null -w '%{{http_code}}' https://{dominio}/health"
        )
        linhas.append(f"{'✅' if codigo == '200' else '⚠️'} {dominio}: HTTP {codigo}")
    return "\n".join(linhas) or "(nenhum domínio no nginx desta máquina)"


def coletar_autocura() -> str:
    # Exclui eventos de "teste-*" (nome usado só em validações manuais do
    # autocura.sh) para não parecer um problema real em produção.
    saida = rodar(
        "journalctl -t autocura --since '-7 days' --no-pager -o cat | grep -v '^teste-' | tail -15"
    )
    return "Sem eventos nos últimos 7 dias." if saida == "(sem saída)" else saida


def coletar_reboot() -> str:
    if not Path("/var/run/reboot-required").exists():
        return "✅ Nenhum reboot pendente."
    pacotes = rodar("cat /var/run/reboot-required.pkgs 2>/dev/null || echo '(lista indisponível)'")
    return (
        "⚠️ Reboot pendente para aplicar atualizações já instaladas.\n\n"
        f"Pacotes:\n{pacotes}\n\n"
        "Containers têm restart automático (unless-stopped); reinicie "
        "num horário de baixo uso e acompanhe pelo menu depois."
    )


# A ordem é a do menu. O título fica no bot; aqui só a coleta.
CATEGORIAS = {
    "containers": coletar_containers,
    "vps": coletar_vps,
    "diskdocker": coletar_docker_disco,
    "backups": coletar_backups,
    "fail2ban": coletar_fail2ban,
    "cert": coletar_certificados,
    "endpoints": coletar_endpoints,
    "autocura": coletar_autocura,
    "reboot": coletar_reboot,
}


def main(argv: list[str], ambiente: dict[str, str] | None = None) -> int:
    ambiente = os.environ if ambiente is None else ambiente
    # Pela chave restrita, o pedido chega em SSH_ORIGINAL_COMMAND e é só uma
    # palavra da lista: qualquer outra coisa é recusada, nunca executada.
    pedido = ambiente.get("SSH_ORIGINAL_COMMAND")
    categoria = pedido.strip() if pedido is not None else (argv[1] if len(argv) > 1 else "")
    if categoria == "--categorias":
        print("\n".join(CATEGORIAS))
        return 0
    coletor = CATEGORIAS.get(categoria)
    if coletor is None:
        print(f"categoria desconhecida: {categoria!r} — use: {', '.join(CATEGORIAS)}", file=sys.stderr)
        return 2
    print(coletor())
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
