#!/usr/bin/env bash
# Monta a fonte declarada do VPS1 enquanto o Viva Passo ainda aguarda a troca
# de DNS. O instalador comum faz backup, valida e recarrega de forma atômica.
set -euo pipefail

RAIZ=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ORIGEM=$(mktemp -d)
trap 'rm -rf -- "$ORIGEM"' EXIT

mkdir -p "$ORIGEM/conf.d" "$ORIGEM/snippets"
cp "$RAIZ/conf.d/00-comum.conf" "$ORIGEM/conf.d/00-comum.conf"
cp "$RAIZ/snippets/proxy-app.conf" "$ORIGEM/snippets/proxy-app.conf"
cp "$RAIZ/recusa-host-desconhecido" "$ORIGEM/recusa-host-desconhecido"

for vhost in conforto-termico controle-bancario controle-renda-variavel megasena wealthfolio villa-rica; do
    cp "$RAIZ/$vhost" "$ORIGEM/$vhost"
done

bash "$RAIZ/instalar.sh" "$ORIGEM"
