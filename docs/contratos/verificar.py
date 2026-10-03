"""Confere a cópia canônica do schema do contrato patrimonio/v4, só com a biblioteca padrão.

    python3 docs/contratos/verificar.py

O que isto garante, e o que não:

- o arquivo é JSON, em LF e com quebra de linha no fim (as cópias nos outros
  repositórios são comparadas byte a byte com ele, e CRLF as faria divergir);
- toda `$ref` aponta para uma definição que existe em `$defs`;
- as seis definições de entrada que os repositórios validam existem.

Que o documento é um JSON Schema 2020-12 válido e que a saída real dos
publicadores o cumpre quem confere são as suítes do CB, do CRV e do Wealthfolio
(jsonschema e Ajv em modo estrito). Aqui fica a barreira barata, que roda em
segundos no CI deste repositório antes de a cópia chegar aos outros.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

CAMINHO = Path(__file__).resolve().parent / "patrimonio-v4.schema.json"
ENTRADAS = (
    "cb_metadata", "cb_snapshot", "cb_changes",
    "crv_metadata", "crv_snapshot", "crv_changes",
)


def refs(no):
    if isinstance(no, dict):
        for chave, valor in no.items():
            if chave == "$ref" and isinstance(valor, str):
                yield valor
            else:
                yield from refs(valor)
    elif isinstance(no, list):
        for item in no:
            yield from refs(item)


def main() -> int:
    bruto = CAMINHO.read_bytes()
    problemas: list[str] = []
    if b"\r" in bruto:
        problemas.append("o arquivo tem CR: precisa ser LF")
    if not bruto.endswith(b"\n"):
        problemas.append("falta a quebra de linha no fim do arquivo")
    try:
        schema = json.loads(bruto.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as erro:
        print(f"{CAMINHO.name}: não é JSON válido: {erro}", file=sys.stderr)
        return 1
    definicoes = schema.get("$defs", {})
    for entrada in ENTRADAS:
        if entrada not in definicoes:
            problemas.append(f"falta a definição {entrada}")
    for ref in sorted(set(refs(schema))):
        if not ref.startswith("#/$defs/"):
            problemas.append(f"$ref fora do documento: {ref}")
        elif ref.removeprefix("#/$defs/") not in definicoes:
            problemas.append(f"$ref sem definição: {ref}")
    for problema in problemas:
        print(f"{CAMINHO.name}: {problema}", file=sys.stderr)
    if not problemas:
        print(f"{CAMINHO.name}: ok ({len(definicoes)} definições)")
    return 1 if problemas else 0


if __name__ == "__main__":
    raise SystemExit(main())
