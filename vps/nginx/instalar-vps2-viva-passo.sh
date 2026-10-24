#!/usr/bin/env bash
# Monta, a partir desta fonte versionada, o conjunto mínimo de Nginx do VPS2.
# O instalador comum faz o backup, nginx -t e reload; este atalho só escolhe o
# vhost que esta máquina deve servir.
set -euo pipefail

RAIZ=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ORIGEM=$(mktemp -d)
trap 'rm -rf -- "$ORIGEM"' EXIT

mkdir -p "$ORIGEM/conf.d" "$ORIGEM/snippets"
cp "$RAIZ/conf.d/00-comum.conf" "$ORIGEM/conf.d/00-comum.conf"
cp "$RAIZ/snippets/proxy-app.conf" "$ORIGEM/snippets/proxy-app.conf"
cp "$RAIZ/recusa-host-desconhecido" "$ORIGEM/recusa-host-desconhecido"
cp "$RAIZ/viva-passo" "$ORIGEM/viva-passo"

"$RAIZ/instalar.sh" "$ORIGEM"
