#!/usr/bin/env bash
# Implanta um projeto no VPS a partir do main do GitHub.
#
#   ./deploy.sh <projeto>        implanta
#   ./deploy.sh <projeto> --check  só mostra o que mudaria
#   ./deploy.sh --status         estado dos quatro projetos
#
# Recusa implantar se houver alteração não commitada no servidor: o código do
# servidor é sempre um espelho do main, nunca a origem de uma mudança.

set -euo pipefail

APPS=/home/ubuntu/apps

projeto_info() {
    case "$1" in
        bancario|controle-bancario)
            DIR=controle-bancario;      ENVF=.env.vps;    PORTA=5201
            DOMINIO=bancario-mspa.duckdns.org ;;
        conforto|conforto-termico)
            DIR=conforto-termico;       ENVF=.env.docker; PORTA=5401
            DOMINIO=conforto-mspa.duckdns.org ;;
        megasena|mega-sena)
            DIR=mega-sena;              ENVF=.env.vps;    PORTA=5101
            DOMINIO=megasena-mspa.duckdns.org ;;
        renda|controle-renda-variavel)
            DIR=controle-renda-variavel; ENVF=.env.vps;   PORTA=5301
            DOMINIO=renda-mspa.duckdns.org ;;
        *)  echo "Projeto desconhecido: $1" >&2
            echo "Use: bancario | conforto | megasena | renda" >&2
            return 1 ;;
    esac
}

compose() { docker compose --env-file "$ENVF" -f compose.yaml "$@"; }

status_geral() {
    printf '%-26s %-10s %-10s %-8s %s\n' PROJETO VPS GITHUB LIMPO SAUDE
    for p in bancario conforto megasena renda; do
        projeto_info "$p"
        cd "$APPS/$DIR"
        local loc rem limpo saude
        loc=$(git rev-parse --short HEAD)
        rem=$(git ls-remote origin refs/heads/main 2>/dev/null | cut -c1-7)
        [ -z "$(git status --porcelain)" ] && limpo=sim || limpo=NAO
        saude=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "https://$DOMINIO/login" || echo ---)
        printf '%-26s %-10s %-10s %-8s %s\n' "$DIR" "$loc" "${rem:-?}" "$limpo" "$saude"
    done
}

if [ "${1:-}" = "--status" ]; then status_geral; exit 0; fi
if [ $# -lt 1 ]; then
    echo "uso: $0 <bancario|conforto|megasena|renda> [--check]" >&2
    echo "     $0 --status" >&2
    exit 1
fi

projeto_info "$1"
CHECK=${2:-}
cd "$APPS/$DIR"

echo "== $DIR =="

sujo=$(git status --porcelain)
if [ -n "$sujo" ]; then
    echo "ABORTADO: há alteração não commitada no servidor." >&2
    echo "$sujo" | sed 's/^/  /' >&2
    echo >&2
    echo "O servidor espelha o main; ele não é lugar de editar código." >&2
    echo "Leve a mudança para a sua máquina, commite, envie ao GitHub e rode de novo." >&2
    exit 1
fi

git fetch --quiet origin main
atual=$(git rev-parse HEAD)
novo=$(git rev-parse origin/main)

if [ "$atual" = "$novo" ]; then
    echo "Já está na versão do main ($(git rev-parse --short HEAD)). Nada a fazer."
    [ "$CHECK" = "--check" ] && exit 0
    exit 0
fi

echo "Mudanças a aplicar:"
git log --oneline "$atual..$novo" | sed 's/^/  /'
echo "Arquivos:"
git diff --stat "$atual..$novo" | tail -20 | sed 's/^/  /'

if [ "$CHECK" = "--check" ]; then
    echo
    echo "(--check: nada foi alterado)"
    exit 0
fi

echo
echo "-- atualizando código --"
git merge --ff-only origin/main

echo "-- reconstruindo e subindo --"
compose up -d --build

echo "-- aguardando saúde --"
for _ in $(seq 1 40); do
    sleep 5
    if ! compose ps --format '{{.Status}}' 2>/dev/null | grep -qi 'starting'; then break; fi
done
compose ps --format '  {{.Name}}  {{.Status}}'

echo "-- verificando o endereço público --"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://$DOMINIO/login" || echo 000)
echo "  https://$DOMINIO/login -> HTTP $code"
[ "$code" = "200" ] || { echo "ATENÇÃO: o site não respondeu 200." >&2; exit 1; }
echo "OK: $DIR em $(git rev-parse --short HEAD)"
