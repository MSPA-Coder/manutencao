#!/usr/bin/env bash
# Roda a sintaxe (`bash -n`) e todas as suítes `*_test.sh` desta pasta, em
# ordem, e para na primeira que falha. É o passo que `scripts/quality.ps1`
# chama dentro de um contêiner `ubuntu:24.04` (o `vigia_test.sh` precisa do
# `date` do GNU, que a imagem `bash:5.2` não tem); a CI roda as mesmas suítes uma a
# uma, para o vermelho já dizer qual foi. O `nginx_test.sh` fica de fora: ele
# precisa da imagem do Nginx e tem passo próprio.
set -euo pipefail

raiz=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$raiz"

while IFS= read -r -d '' script; do
    bash -n "$script"
done < <(find vps -type f -name '*.sh' -print0)
echo "ok   bash -n em vps/"

for suite in vps/tests/*_test.sh; do
    [ "$(basename "$suite")" = nginx_test.sh ] && continue
    echo "==> $suite"
    bash "$suite"
done
echo "ok   todas as suites"
