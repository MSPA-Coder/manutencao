#!/usr/bin/env python3
"""Bot de status dos VPS via Telegram (long polling, só stdlib).

Responde a /status com um menu de botões inline. Só reage a mensagens do
TELEGRAM_CHAT_ID configurado em .secrets/telegram.env; qualquer outro chat é
ignorado em silêncio, então achar o bot publicamente não basta para usá-lo.

MENU UNIFICADO (25/10/2026). Cada botão responde com uma seção por servidor:
a desta máquina vem do `status-coletor.py` local e a do outro VPS vem do
mesmo coletor, por SSH pelo Tailscale, com uma chave presa por `command=` ao
coletor (só lê, como a chave do backup). O bot roda numa máquina só — hoje o
VPS1 —, porque o Telegram entrega os cliques a um único `getUpdates` por bot:
dois processos com o mesmo token brigam (HTTP 409) e o menu para de
responder. Os alertas (`alerta.sh`) não têm esse limite e saem dos dois VPS.
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

CONFIG = Path(os.environ.get("TELEGRAM_CONFIG", "/home/ubuntu/.secrets/telegram.env"))
COLETOR = Path(os.environ.get("STATUS_COLETOR", "/home/ubuntu/status-coletor.py"))
CHAVE_REMOTA = Path(os.environ.get("STATUS_CHAVE", "/home/ubuntu/.ssh/status-agente"))
HOSTS_CONHECIDOS = Path(os.environ.get("STATUS_KNOWN_HOSTS", "/home/ubuntu/.ssh/known_hosts_status"))

# Os servidores do menu, na ordem em que aparecem: nome curto, hostname e
# endereço no Tailscale. O mesmo mapa de nomes do `alerta.sh`.
SERVIDORES = (
    ("VPS1", "instance-20260818-1632", "100.94.82.91"),
    ("VPS2", "instance-20260913-1619", "100.86.176.64"),
)

SECOES = {
    "containers": "🐳 Containers",
    "vps": "🖥️ VPS",
    "diskdocker": "📦 Disco do Docker",
    "backups": "💾 Backups",
    "fail2ban": "🚫 Fail2Ban",
    "cert": "🔒 Certificado TLS",
    "endpoints": "🌐 Endpoints públicos",
    "autocura": "🩹 Autocura",
    "reboot": "🔄 Reboot pendente",
}

# O Telegram recusa mensagem acima de 4096 caracteres; cada servidor fica com
# metade da folga, para um não esconder o outro.
LIMITE_MENSAGEM = 3900


def carregar_config(arquivo: Path = CONFIG) -> tuple[str, int]:
    valores = {}
    for linha in arquivo.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, _, valor = linha.partition("=")
        valores[chave.strip()] = valor.strip().strip('"')
    return valores["TELEGRAM_BOT_TOKEN"], int(valores["TELEGRAM_CHAT_ID"])


def coletar_local(categoria: str) -> str:
    try:
        r = subprocess.run(
            ["python3", str(COLETOR), categoria], capture_output=True, text=True, timeout=60
        )
    except subprocess.TimeoutExpired:
        return "(tempo esgotado ao coletar)"
    except OSError as erro:
        return f"(erro ao chamar o coletor: {erro})"
    return (r.stdout or r.stderr or "(sem saída)").strip()


def coletar_remoto(endereco: str, categoria: str) -> str:
    if not CHAVE_REMOTA.exists():
        return f"(sem a chave {CHAVE_REMOTA} para consultar este servidor)"
    comando = [
        "ssh", "-i", str(CHAVE_REMOTA),
        "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", f"UserKnownHostsFile={HOSTS_CONHECIDOS}",
        f"ubuntu@{endereco}", categoria,
    ]
    try:
        r = subprocess.run(comando, capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        return "(o servidor não respondeu a tempo)"
    except OSError as erro:
        return f"(erro ao chamar o ssh: {erro})"
    if r.returncode != 0:
        motivo = (r.stderr or r.stdout or "").strip().splitlines()
        return f"⚠️ não foi possível consultar ({motivo[-1] if motivo else f'código {r.returncode}'})"
    return (r.stdout or "(sem saída)").strip()


def montar_texto(categoria: str, coletar=None, este_host: str | None = None) -> str:
    """O título da seção e um bloco por servidor, coletados em paralelo."""
    este_host = este_host or socket.gethostname().split(".")[0]

    def um(servidor: tuple[str, str, str]) -> str:
        nome, hostname, endereco = servidor
        if coletar is not None:
            return coletar(nome, categoria)
        if hostname == este_host:
            return coletar_local(categoria)
        return coletar_remoto(endereco, categoria)

    with ThreadPoolExecutor(max_workers=len(SERVIDORES)) as grupo:
        corpos = list(grupo.map(um, SERVIDORES))
    folga = (LIMITE_MENSAGEM - len(SECOES[categoria]) - 40) // len(SERVIDORES)
    blocos = []
    for (nome, _, _), corpo in zip(SERVIDORES, corpos):
        if len(corpo) > folga:
            corpo = corpo[: folga - 12] + "\n(… cortado)"
        blocos.append(f"━━ {nome} ━━\n{corpo}")
    return f"{SECOES[categoria]}\n\n" + "\n\n".join(blocos)


def teclado_menu() -> dict:
    botoes, linha = [], []
    for chave, titulo in SECOES.items():
        linha.append({"text": titulo, "callback_data": chave})
        if len(linha) == 2:
            botoes.append(linha)
            linha = []
    if linha:
        botoes.append(linha)
    return {"inline_keyboard": botoes}


def teclado_voltar() -> dict:
    return {"inline_keyboard": [[{"text": "⬅️ Menu", "callback_data": "menu"}]]}


TEXTO_MENU = "Status dos VPS (VPS1 e VPS2) — escolha uma categoria:"


class Bot:
    def __init__(self, token: str, chat_id: int, chamar_api=None, montar=montar_texto):
        self.api_base = f"https://api.telegram.org/bot{token}"
        self.chat_id = chat_id
        self.api = chamar_api or self._api
        self.montar = montar

    def _api(self, metodo: str, **params):
        dados = urllib.parse.urlencode(params).encode()
        req = urllib.request.Request(f"{self.api_base}/{metodo}", data=dados)
        with urllib.request.urlopen(req, timeout=40) as resp:
            return json.load(resp)

    def processar(self, update: dict) -> None:
        if "message" in update:
            msg = update["message"]
            if msg.get("chat", {}).get("id") != self.chat_id:
                return
            if (msg.get("text") or "").strip() in ("/status", "/start"):
                self.api("sendMessage", chat_id=self.chat_id, text=TEXTO_MENU,
                         reply_markup=json.dumps(teclado_menu()))
            return

        cq = update.get("callback_query")
        if not cq or cq.get("message", {}).get("chat", {}).get("id") != self.chat_id:
            return
        chave = cq.get("data")
        msg_id = cq["message"]["message_id"]
        self.api("answerCallbackQuery", callback_query_id=cq["id"])
        if chave == "menu":
            self.api("editMessageText", chat_id=self.chat_id, message_id=msg_id,
                     text=TEXTO_MENU, reply_markup=json.dumps(teclado_menu()))
        elif chave in SECOES:
            self.api("editMessageText", chat_id=self.chat_id, message_id=msg_id,
                     text=self.montar(chave)[:LIMITE_MENSAGEM],
                     reply_markup=json.dumps(teclado_voltar()))

    def rodar(self) -> None:
        offset = 0
        while True:
            try:
                resp = self.api("getUpdates", offset=offset, timeout=30)
                for update in resp.get("result", []):
                    offset = update["update_id"] + 1
                    try:
                        self.processar(update)
                    except Exception as erro:
                        print(f"erro ao processar update: {erro}", flush=True)
            except urllib.error.HTTPError as erro:
                if erro.code == 409:
                    # Outro processo com o mesmo token está recebendo os
                    # cliques (o bot ligado nas duas máquinas). Insistir só
                    # alterna quem perde os cliques.
                    print("409: outro processo já recebe os cliques deste bot; "
                          "deixe o bot ligado numa máquina só", flush=True)
                    time.sleep(60)
                else:
                    print(f"erro HTTP no polling: {erro}", flush=True)
                    time.sleep(5)
            except (urllib.error.URLError, TimeoutError) as erro:
                print(f"erro de rede no polling: {erro}", flush=True)
                time.sleep(5)
            except Exception as erro:
                print(f"erro inesperado no loop: {erro}", flush=True)
                time.sleep(5)


if __name__ == "__main__":
    Bot(*carregar_config()).rodar()
