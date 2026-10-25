"""Testes do menu de status do Telegram: coletor e bot, sem rede nem VPS.

    python3 -m unittest vps/tests/status_test.py
"""

from __future__ import annotations

import importlib.util
import json
import os
import tempfile
import time
import unittest
from pathlib import Path

VPS = Path(__file__).resolve().parent.parent


def _carregar(nome: str, arquivo: str):
    spec = importlib.util.spec_from_file_location(nome, VPS / arquivo)
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


coletor = _carregar("status_coletor", "status-coletor.py")
bot = _carregar("telegram_bot_status", "telegram-bot-status.py")


class ColetorTests(unittest.TestCase):
    def test_dominios_vem_dos_vhosts_sem_o_padrao(self) -> None:
        # O bot antigo tinha a lista escrita à mão, e ela não tinha o
        # Wealthfolio: o mesmo erro que a descoberta do vigia já evitava.
        with tempfile.TemporaryDirectory() as pasta:
            Path(pasta, "villa-rica").write_text(
                "server {\n    server_name villa-rica.duckdns.org;\n    root /var/www/villa-rica;\n}\n",
                encoding="utf-8")
            Path(pasta, "app").write_text(
                "server { listen 443; server_name a.example b.example; }\n"
                "# server_name comentado.example;\n", encoding="utf-8")
            Path(pasta, "default").write_text("server { server_name _; }\n", encoding="utf-8")
            self.assertEqual(
                coletor.dominios(Path(pasta)),
                ["a.example", "b.example", "villa-rica.duckdns.org"],
            )

    def test_backups_marca_o_que_passou_de_36h(self) -> None:
        with tempfile.TemporaryDirectory() as pasta:
            agora = time.time()
            for nome, horas in (("site_villa_rica", 2), ("velho", 40)):
                Path(pasta, nome).mkdir()
                marca = Path(pasta, nome, ".ultima_conferencia")
                marca.write_text("x", encoding="utf-8")
                os.utime(marca, (agora - horas * 3600, agora - horas * 3600))
            Path(pasta, "sem_marca").mkdir()
            texto = coletor.coletar_backups(Path(pasta), agora)
        self.assertIn("✅ site_villa_rica: conferido há 2h", texto)
        self.assertIn("⚠️ velho: conferido há 40h", texto)
        self.assertIn("⚠️ sem_marca: sem marcador", texto)

    def test_pela_chave_restrita_so_categoria_da_lista(self) -> None:
        # A chave do bot só executa este programa; o que vem em
        # SSH_ORIGINAL_COMMAND nunca pode virar comando.
        for pedido in ("rm -rf /", "containers; id", "", "../x"):
            with self.subTest(pedido=pedido):
                self.assertEqual(coletor.main(["x"], {"SSH_ORIGINAL_COMMAND": pedido}), 2)

    def test_categoria_valida_roda_o_coletor(self) -> None:
        chamado = []
        original = coletor.CATEGORIAS["reboot"]
        coletor.CATEGORIAS["reboot"] = lambda: chamado.append(1) or "ok"
        try:
            self.assertEqual(coletor.main(["x"], {"SSH_ORIGINAL_COMMAND": " reboot "}), 0)
            self.assertEqual(coletor.main(["x", "reboot"], {}), 0)
        finally:
            coletor.CATEGORIAS["reboot"] = original
        self.assertEqual(len(chamado), 2)

    def test_marca_dos_conteineres(self) -> None:
        marca = coletor._marca_do_conteiner
        self.assertEqual(marca("Up 14 hours (healthy)"), "✅")
        self.assertEqual(marca("Up 3 seconds (health: starting)"), "✅")
        self.assertEqual(marca("Up 2 hours (unhealthy)"), "⚠️")
        # A tarefa de uma vez do deploy que terminou bem não é problema.
        self.assertEqual(marca("Exited (0) 14 hours ago"), "⏹️")
        self.assertEqual(marca("Exited (1) 5 minutes ago"), "⚠️")
        self.assertEqual(marca("Exited (127) 3 days ago"), "⚠️")
        self.assertEqual(marca("Restarting (1) 2 seconds ago"), "⚠️")

    def test_bot_e_coletor_tem_as_mesmas_categorias(self) -> None:
        self.assertEqual(list(bot.SECOES), list(coletor.CATEGORIAS))


class MenuUnificadoTests(unittest.TestCase):
    def test_cada_secao_mostra_os_dois_servidores_em_ordem(self) -> None:
        texto = bot.montar_texto("containers", coletar=lambda nome, _: f"estado do {nome}")
        self.assertTrue(texto.startswith("🐳 Containers"))
        self.assertLess(texto.index("━━ VPS1 ━━"), texto.index("━━ VPS2 ━━"))
        self.assertIn("estado do VPS1", texto)
        self.assertIn("estado do VPS2", texto)

    def test_um_servidor_longo_nao_esconde_o_outro(self) -> None:
        texto = bot.montar_texto(
            "containers", coletar=lambda nome, _: "x" * 9000 if nome == "VPS1" else "curto")
        self.assertLessEqual(len(texto), bot.LIMITE_MENSAGEM)
        self.assertIn("(… cortado)", texto)
        self.assertIn("curto", texto)

    def test_esta_maquina_e_local_e_a_outra_e_remota(self) -> None:
        chamadas = []
        original_local, original_remoto = bot.coletar_local, bot.coletar_remoto
        bot.coletar_local = lambda cat: chamadas.append(("local", cat)) or "l"
        bot.coletar_remoto = lambda end, cat: chamadas.append(("remoto", end)) or "r"
        try:
            bot.montar_texto("vps", este_host="instance-20260818-1632")
        finally:
            bot.coletar_local, bot.coletar_remoto = original_local, original_remoto
        self.assertIn(("local", "vps"), chamadas)
        self.assertIn(("remoto", "100.86.176.64"), chamadas)
        self.assertEqual(len(chamadas), 2)

    def test_sem_a_chave_a_secao_remota_diz_por_que(self) -> None:
        original = bot.CHAVE_REMOTA
        bot.CHAVE_REMOTA = Path("/nao/existe/chave")
        try:
            self.assertIn("sem a chave", bot.coletar_remoto("192.0.2.1", "vps"))
        finally:
            bot.CHAVE_REMOTA = original


class BotTests(unittest.TestCase):
    def _bot(self):
        chamadas = []
        b = bot.Bot("t", 42, chamar_api=lambda metodo, **p: chamadas.append((metodo, p)) or {},
                    montar=lambda cat: f"texto de {cat}")
        return b, chamadas

    def test_outro_chat_e_ignorado(self) -> None:
        b, chamadas = self._bot()
        b.processar({"message": {"chat": {"id": 7}, "text": "/status"}})
        b.processar({"callback_query": {"id": "1", "data": "vps",
                                        "message": {"chat": {"id": 7}, "message_id": 1}}})
        self.assertEqual(chamadas, [])

    def test_status_abre_o_menu_com_os_nove_botoes(self) -> None:
        b, chamadas = self._bot()
        b.processar({"message": {"chat": {"id": 42}, "text": "/status"}})
        metodo, params = chamadas[0]
        self.assertEqual(metodo, "sendMessage")
        botoes = [x["callback_data"] for linha in json.loads(params["reply_markup"])["inline_keyboard"]
                  for x in linha]
        self.assertEqual(botoes, list(bot.SECOES))

    def test_clique_responde_com_a_secao_e_o_voltar(self) -> None:
        b, chamadas = self._bot()
        b.processar({"callback_query": {"id": "9", "data": "backups",
                                        "message": {"chat": {"id": 42}, "message_id": 5}}})
        self.assertEqual(chamadas[0], ("answerCallbackQuery", {"callback_query_id": "9"}))
        metodo, params = chamadas[1]
        self.assertEqual(metodo, "editMessageText")
        self.assertEqual(params["text"], "texto de backups")
        self.assertIn("menu", params["reply_markup"])


if __name__ == "__main__":
    unittest.main()
