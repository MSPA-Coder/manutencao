#!/usr/bin/env bash
# Backup diário dos bancos de produção.
#
#   ./backup-db.sh            faz o ciclo dos quatro projetos
#   ./backup-db.sh --estado   mostra o estado sem alterar nada
#   ./backup-db.sh --forcar   ignora a checagem de alteração e faz o dump
#
# O que este script NUNCA faz: ligar, parar ou recriar contêiner. Se o Postgres
# de um projeto não estiver de pé, ele registra a falha e segue para o próximo.
# Consertar a produção às 3 da manhã não é tarefa de um backup.
#
# Ordem de cada dump, e o motivo de cada passo:
#   1. nasce em .tmp                  um dump cortado nunca tem nome de dump bom
#   2. relido com pg_restore --list   código de saída zero não prova nada
#   3. só então recebe o nome final   troca atômica
#   4. retenção por último            nunca apagar antes de ter o substituto

set -euo pipefail

DEST=/home/ubuntu/backups
RETENCAO_DIAS=14
INTERVALO_MAX_DIAS=7

# slug:contêiner — o usuário e o banco são lidos de dentro do contêiner, para
# não duplicar aqui uma configuração que já existe lá.
PROJETOS=(
    "conforto_termico:conforto-termico-postgres-1"
    "mega_sena:mega-sena-postgres-1"
    "controle_bancario:controle-bancario-postgres-1"
    "controle_renda_variavel:controle-renda-variavel-db-1"
)

log() { printf '%s  %s\n' "$(date -u '+%Y-%m-%d %H:%M:%SZ')" "$*"; }

rodando() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }

# Executa psql dentro do contêiner usando as credenciais que já vivem lá.
consultar() {
    docker exec "$1" sh -c \
        'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "'"$2"'"' 2>/dev/null
}

lsn_atual() { consultar "$1" 'SELECT pg_current_wal_lsn()'; }

# --------------------------------------------------------------------------
# Decisão: precisa fazer backup agora?
#
# Só pula quando existe backup válido, o LSN guardado é legível e o atual é
# exatamente igual. Qualquer outra situação faz o dump — ausência de prova de
# que nada mudou não é prova de que nada mudou.
# --------------------------------------------------------------------------
motivo_backup() {
    local dir="$1" lsn="$2" ultimo guardado idade_s idade_d

    ultimo=$(ls -1t "$dir"/*.dump 2>/dev/null | head -1 || true)
    [ -z "$ultimo" ] && { echo "primeiro backup"; return 0; }

    [ -r "$dir/.ultimo.lsn" ] || { echo "marcador de LSN ausente"; return 0; }
    guardado=$(cat "$dir/.ultimo.lsn" 2>/dev/null || true)
    [ -z "$guardado" ] && { echo "marcador de LSN vazio"; return 0; }

    idade_s=$(( $(date +%s) - $(stat -c %Y "$ultimo") ))
    idade_d=$(( idade_s / 86400 ))
    [ "$idade_d" -ge "$INTERVALO_MAX_DIAS" ] && \
        { echo "teto de $INTERVALO_MAX_DIAS dias sem backup"; return 0; }

    # Diferença em qualquer direção conta: o LSN só anda para frente, então um
    # valor menor significa que o banco foi restaurado ou recriado.
    [ "$lsn" != "$guardado" ] && { echo "banco alterado"; return 0; }

    return 1
}

aplicar_retencao() {
    local dir="$1" mais_novo
    mais_novo=$(ls -1t "$dir"/*.dump 2>/dev/null | head -1 || true)
    [ -z "$mais_novo" ] && return 0

    # O `! -samefile` é o piso: o mais recente nunca sai, por mais velho que seja.
    while IFS= read -r -d '' velho; do
        rm -f "$velho" "$velho.sha256"
        log "  retenção: removido $(basename "$velho")"
    done < <(find "$dir" -maxdepth 1 -name '*.dump' -mtime +"$RETENCAO_DIAS" \
                  ! -samefile "$mais_novo" -print0 2>/dev/null)
}

fazer_dump() {
    local slug="$1" container="$2" dir="$3" lsn="$4"
    local carimbo nome tmp final

    carimbo=$(date -u '+%Y%m%d_%H%M%S')
    nome="${slug}_banco_${carimbo}.dump"
    tmp="$dir/.${nome}.tmp"
    final="$dir/$nome"

    # O pg_dump roda dentro do contêiner: a versão da ferramenta é sempre a do
    # servidor, e o host não precisa ter PostgreSQL instalado.
    if ! docker exec "$container" sh -c \
        'pg_dump --format=custom --no-owner --no-acl -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
        > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        log "  ERRO: pg_dump falhou"
        return 1
    fi

    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        log "  ERRO: dump vazio"
        return 1
    fi

    # Releitura obrigatória, dentro do mesmo contêiner que o produziu.
    if ! docker exec -i "$container" pg_restore --list < "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        log "  ERRO: dump reprovado em pg_restore --list"
        return 1
    fi

    mv "$tmp" "$final"
    sha256sum "$final" | awk '{print $1}' > "$final.sha256"
    printf '%s' "$lsn" > "$dir/.ultimo.lsn"

    log "  gravado $nome ($(du -h "$final" | cut -f1))"
    return 0
}

ciclo() {
    local forcar="${1:-nao}"
    local falhas=0

    for entrada in "${PROJETOS[@]}"; do
        local slug="${entrada%%:*}" container="${entrada##*:}"
        local dir="$DEST/$slug"
        mkdir -p "$dir"

        log "== $slug"

        if ! rodando "$container"; then
            log "  ERRO: $container não está rodando — nada foi feito"
            falhas=$((falhas + 1))
            continue
        fi

        local lsn
        lsn=$(lsn_atual "$container" || true)
        if [ -z "$lsn" ]; then
            log "  ERRO: não foi possível ler o LSN"
            falhas=$((falhas + 1))
            continue
        fi

        local motivo
        if [ "$forcar" = sim ]; then
            motivo="forçado"
        elif ! motivo=$(motivo_backup "$dir" "$lsn"); then
            # Registrar a conferência é o que distingue "quieto" de "quebrado".
            date -u '+%Y-%m-%dT%H:%M:%SZ' > "$dir/.ultima_conferencia"
            log "  sem alterações desde o último backup — nada a fazer"
            continue
        fi

        log "  motivo: $motivo"
        if fazer_dump "$slug" "$container" "$dir" "$lsn"; then
            date -u '+%Y-%m-%dT%H:%M:%SZ' > "$dir/.ultima_conferencia"
            aplicar_retencao "$dir"
        else
            falhas=$((falhas + 1))
        fi
    done

    if [ "$falhas" -gt 0 ]; then
        log "$falhas projeto(s) falharam"
        return 1
    fi
    log "ciclo concluído sem falhas"
}

estado() {
    printf '%-26s %-6s %-22s %-10s %s\n' PROJETO DUMPS ULTIMO_BACKUP TAMANHO CONFERIDO
    for entrada in "${PROJETOS[@]}"; do
        local slug="${entrada%%:*}" dir="$DEST/${entrada%%:*}"
        local n ultimo quando tam conf
        # Contagem por glob: `ls | wc -l` com pipefail dispara o ramo de erro
        # quando a pasta está vazia, e a contagem sai duplicada.
        local -a arquivos=()
        shopt -s nullglob; arquivos=("$dir"/*.dump); shopt -u nullglob
        n=${#arquivos[@]}
        ultimo=$(ls -1t "$dir"/*.dump 2>/dev/null | head -1 || true)
        if [ -n "$ultimo" ]; then
            quando=$(date -u -d "@$(stat -c %Y "$ultimo")" '+%Y-%m-%d %H:%MZ')
            tam=$(du -h "$ultimo" | cut -f1)
        else
            quando="nunca"; tam="—"
        fi
        conf=$(cat "$dir/.ultima_conferencia" 2>/dev/null || echo "—")
        printf '%-26s %-6s %-22s %-10s %s\n' "$slug" "$n" "$quando" "$tam" "$conf"
    done
}

case "${1:-}" in
    --estado) estado ;;
    --forcar) ciclo sim ;;
    "")       ciclo nao ;;
    *)        echo "Uso: $0 [--estado|--forcar]" >&2; exit 2 ;;
esac
