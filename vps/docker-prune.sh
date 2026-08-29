#!/usr/bin/env bash
# Poda o cache de build do Docker semanalmente.
#
# `docker compose build` no deploy.sh acumula camadas de build a cada
# implantação. Nada mais as remove sozinho, então cresceriam sem limite ao
# longo de meses de deploys. Só o cache de build é alvo — imagens em uso
# pelos containers ativos nunca são tocadas por este comando.

set -euo pipefail

docker builder prune -f --filter until=168h
logger -t docker-prune -- "poda concluída"
