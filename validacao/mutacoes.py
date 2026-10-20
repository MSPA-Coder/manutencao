"""Representative mutation checks in disposable source copies, never in the checkout."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

project = os.environ["PROBE_PROJECT"]
cases = {
    "MegaSena": ("app/draws/statistics.py", "prize_winners[key] += winners", "prize_winners[key] += int(winners > 0)", "tests/test_estatisticas_com_banco.py::test_estatisticas_preservam_frequencias_e_diferenciam_ganhadores_de_concursos", ["app"]),
    "MpPortal": ("institucional/previa.py", "self.send_response(404)", "self.send_response(200)", "tests/test_entrega_http.py::test_pagina_inexistente_preserva_status_e_semantica_head[GET]", ["institucional", "templates", "static", "php"]),
    "FinancasMCP": ("financas_mcp/conexao.py", "truncado = len(linhas) > limite", "truncado = len(linhas) >= limite", "tests/test_contratos_leitura.py::test_limite_distingue_resultado_completo_de_cortado[2-2-False]", ["financas_mcp"]),
    "ControleBancario": ("management/services.py", "            account__currency=BASE_CURRENCY,\n", "", "tests/test_gestao_persistida.py::test_orcamento_recalcula_realizado_sem_misturar_moedas_ou_virada_do_ano", ["accounts", "bank_statements", "banking", "core", "dashboard", "financeiro", "management", "reports", "transactions"]),
    "BackupRestore": ("restaurar.py", 'if motor.sha256_arquivo(origem) != artefato["sha256"]:', 'if False and motor.sha256_arquivo(origem) != artefato["sha256"]:', "tests.test_fluxo_backup.FluxoBackupTests.test_restauracao_adulterada_e_recusada_antes_de_falar_com_docker", []),
}
filename, before, after, target, roots = cases[project]
original = Path.cwd()
with tempfile.TemporaryDirectory(prefix="mutation-") as directory:
    mutated = Path(directory)
    for root in roots:
        shutil.copytree(original / root, mutated / root)
    if project != "BackupRestore":
        shutil.copytree(original / "tests", mutated / "tests")
        (mutated / "logs").mkdir()
        for support in ("pyproject.toml", "compose.yaml", "migrations"):
            path = original / support
            if path.is_dir():
                shutil.copytree(path, mutated / support)
            elif path.is_file():
                shutil.copy2(path, mutated / support)
    if project == "BackupRestore":
        for source in original.glob("*.py"):
            shutil.copy2(source, mutated / source.name)
        shutil.copytree(original / "tests", mutated / "tests")
    source = mutated / filename
    code = source.read_text()
    if before not in code:
        raise RuntimeError("Mutation target no longer matches; review the probe.")
    source.write_text(code.replace(before, after, 1))
    if project == "BackupRestore":
        command = [sys.executable, "-m", "unittest", target, "-v"]
        result = subprocess.run(command, cwd=mutated, text=True, capture_output=True, timeout=120)
        killed = result.returncode != 0 and "FAILED (failures=1)" in result.stderr and "ERROR:" not in result.stderr
    else:
        junit = mutated / "junit.xml"
        command = [sys.executable, "-m", "pytest", "-q", "-o", f"pythonpath={mutated}", "--junitxml=" + str(junit), target]
        environment = dict(os.environ, PYTHONPATH=str(mutated))
        if project == "ControleBancario":
            environment["POSTGRES_DB"] = "validation_mutation_cb"
        result = subprocess.run(command, cwd=mutated, env=environment, text=True, capture_output=True, timeout=120)
        cases_xml = ET.parse(junit).findall(".//testcase") if junit.exists() else []
        killed = result.returncode == 1 and len(cases_xml) == 1 and len(cases_xml[0].findall("failure")) == 1 and not cases_xml[0].findall("error")
    report = {"project": project, "file": filename, "mutation": {"before": before, "after": after}, "test": target, "killed_by_assertion": killed, "exit_code": result.returncode}
    (Path("/evidence") / f"{project}-mutation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(result.stdout)
    print(result.stderr)
    print(json.dumps(report))
    sys.exit(0 if killed else 1)
