#!/usr/bin/env bash
# Deploy diário de commits aprovados e reconstrução semanal das tags-base móveis.

set -euo pipefail

APPS=${APPS:-/home/ubuntu/apps}
DEPLOY=${DEPLOY:-/home/ubuntu/deploy.sh}
BACKUP=${BACKUP:-/home/ubuntu/backup-db.sh}
ALERTA=${ALERTA:-/home/ubuntu/alerta.sh}
LOCK_FILE=${LOCK_FILE:-/home/ubuntu/.local/state/mspa-auto-deploy/lock}
MODO=${1:-}

case "$MODO" in
    ""|--refresh) ;;
    *) echo "Uso: $0 [--refresh]" >&2; exit 2 ;;
esac

PROJETOS=(megasena conforto bancario renda wealthfolio)
DIRS=(mega-sena conforto-termico controle-bancario controle-renda-variavel wealthfolio-teste)

alertar() {
    [ -x "$ALERTA" ] || return 0
    "$ALERTA" "$1" "$2" >/dev/null 2>&1 || true
}

falhar() {
    local titulo=$1 detalhe=$2
    echo "$titulo: $detalhe" >&2
    alertar "$titulo" "$detalhe"
    exit 1
}

install -d -m 700 "$(dirname -- "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "Outra atualização automática ainda está em execução; esta rodada foi ignorada."
    exit 0
fi

ATUALIZACOES=()
for i in "${!PROJETOS[@]}"; do
    projeto=${PROJETOS[$i]}
    diretorio="$APPS/${DIRS[$i]}"
    if [ ! -d "$diretorio/.git" ]; then
        falhar "AUTO-DEPLOY ABORTADO" "$diretorio não é um clone Git."
    fi
    local_sha=$(git -C "$diretorio" rev-parse HEAD) ||
        falhar "AUTO-DEPLOY ABORTADO" "não foi possível ler o HEAD de $projeto."
    remoto=$(git -C "$diretorio" ls-remote --exit-code origin refs/heads/main | cut -f1) ||
        falhar "AUTO-DEPLOY ABORTADO" "não foi possível consultar main de $projeto."
    if ! [[ "$local_sha" =~ ^[0-9a-f]{40}$ && "$remoto" =~ ^[0-9a-f]{40}$ ]]; then
        falhar "AUTO-DEPLOY ABORTADO" "SHA inválido ao verificar $projeto."
    fi
    if [ "$local_sha" != "$remoto" ]; then
        ATUALIZACOES+=("$projeto ${local_sha:0:7} -> ${remoto:0:7}")
    fi
done

if [ "$MODO" = "--refresh" ]; then
    echo "Reconstrução semanal solicitada; os cinco apps serão verificados pela CI."
elif [ "${#ATUALIZACOES[@]}" -eq 0 ]; then
    echo "Nenhum main avançou; sem deploy e sem backup forçado."
    exit 0
else
    printf 'Commits prontos para verificação pelo deploy.sh:\n'
    printf '  %s\n' "${ATUALIZACOES[@]}"
fi

# Um único backup verificado cobre todas as migrações e reinícios desta rodada.
if ! "$BACKUP" --forcar; then
    falhar "AUTO-DEPLOY ABORTADO: BACKUP FALHOU" \
        "backup-db.sh --forcar não confirmou uma cópia válida; produção não foi alterada."
fi

FALHAS=()
for projeto in "${PROJETOS[@]}"; do
    if [ "$MODO" = "--refresh" ]; then
        if ! "$DEPLOY" "$projeto" --refresh; then
            FALHAS+=("$projeto")
        fi
    elif ! "$DEPLOY" "$projeto"; then
        FALHAS+=("$projeto")
    fi
done

if [ "${#FALHAS[@]}" -gt 0 ]; then
    lista=$(IFS=', '; echo "${FALHAS[*]}")
    falhar "AUTO-DEPLOY INCOMPLETO" \
        "deploy.sh recusou ou reverteu: $lista. Consulte journalctl -u atualizar-stacks.service."
fi

echo "OK: deploys concluídos; cada app passou pela CI e pela sonda pública /health."
