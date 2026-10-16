#!/usr/bin/env bash
# Biblioteca compartilhada para serializar operações que mudam o estado de uma
# aplicação no VPS. Deve ser carregada (source), nunca executada diretamente.
#
# Um lock é por slug do projeto, não pela operação: deploy manual, o timer de
# atualização e o backup do volume do Wealthfolio precisam se excluir entre si
# porque os dois podem recriar/pausar o mesmo contêiner. Apps diferentes seguem
# independentes. O descritor fica aberto até o processo terminar; assim um
# TERM, erro ou queda do shell libera o flock pelo próprio kernel.

APP_LOCK_DIR=${APP_LOCK_DIR:-/home/ubuntu/.local/state/mspa-app-locks}
APP_LOCK_TIMEOUT_SEGUNDOS=${APP_LOCK_TIMEOUT_SEGUNDOS:-300}
APP_LOCK_FD=

travar_app() {
    local app=$1 arquivo inicio agora

    if ! [[ "$app" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        echo "ERRO: nome de aplicação inválido para lock: '$app'" >&2
        return 2
    fi
    if ! [[ "$APP_LOCK_TIMEOUT_SEGUNDOS" =~ ^[0-9]+$ ]]; then
        echo "ERRO: APP_LOCK_TIMEOUT_SEGUNDOS deve ser um inteiro não negativo." >&2
        return 2
    fi

    install -d -m 700 "$APP_LOCK_DIR"
    arquivo="$APP_LOCK_DIR/$app.lock"
    exec {APP_LOCK_FD}>"$arquivo"
    # `flock -w` seria menor, mas o BusyBox da imagem de testes não o oferece.
    # O laço usa apenas `-n`, presente tanto lá como no util-linux do VPS, e
    # mantém o mesmo contrato de espera limitada.
    inicio=$(date +%s)
    until flock -n "$APP_LOCK_FD"; do
        agora=$(date +%s)
        if [ $((agora - inicio)) -ge "$APP_LOCK_TIMEOUT_SEGUNDOS" ]; then
            echo "ABORTADO: $app está em outra operação; aguardou ${APP_LOCK_TIMEOUT_SEGUNDOS}s pelo lock." >&2
            eval "exec ${APP_LOCK_FD}>&-"
            APP_LOCK_FD=
            return 75
        fi
        sleep 1
    done
}

destravar_app() {
    [ -n "$APP_LOCK_FD" ] || return 0
    flock -u "$APP_LOCK_FD" || true
    eval "exec ${APP_LOCK_FD}>&-"
    APP_LOCK_FD=
}
