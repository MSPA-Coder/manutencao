#!/usr/bin/env bash
# Backup diário dos bancos de produção.
#
#   ./backup-db.sh            faz o ciclo dos bancos que encontrar rodando
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

# `DEST` vem do ambiente para que `tests/backup-db_test.sh` exercite ESTE
# arquivo, e não uma cópia adaptada — mesma razão pela qual `instalar.sh` aceita
# `DESTINO_SCRIPTS`, e pela mesma lição: uma suíte que aprova um arquivo
# diferente do que roda em produção não aprova nada.
DEST=${DEST:-/home/ubuntu/backups}
RETENCAO_DIAS=14
INTERVALO_MAX_DIAS=7

# O usuário e o banco são lidos de dentro do contêiner, para não duplicar aqui
# uma configuração que já existe lá.
#
# `mp_portal` entrou na virada de 10/09/2026: é o primeiro banco da frota com
# dado pessoal de terceiro (os contatos vindos do site), então a retenção dos
# dumps aqui passou a valer também sob a ótica da LGPD.
#
# POR QUE OS BANCOS SÃO DESCOBERTOS E NÃO LISTADOS (13/09/2026). Havia aqui um
# vetor `slug:contêiner` escrito à mão, e um segundo, com a mesma intenção, no
# `backup-agent.sh`. Quando o portal entrou em 10/09, alguém acrescentou o
# `mp_portal` a este e não àquele: o dump do portal passou a ser produzido e a
# NÃO poder ser baixado, e nada acusou, porque as duas listas não se
# conversavam. Some-se a isso um segundo VPS, onde a lista dos cinco descreve
# em parte a outra máquina, e manter a resposta à mão deixa de se pagar.
#
# O CRITÉRIO É A IMAGEM QUE O COMPOSE PEDIU (`postgres:*`):
#   - não é o nome do contêiner, porque a frota já é inconsistente aí
#     (`-postgres-1` em quatro projetos, `-db-1` no ControleRendaVariavel);
#   - não é "tem `pg_dump` dentro", porque os aplicativos trazem o cliente do
#     Postgres para falar com o banco: conferido no VPS, esse teste aprova
#     `conforto-termico-ict-1` e `conforto-termico-coletor-1`, que não são
#     banco nenhum.
#
# O slug é o projeto do Compose com `-` virando `_` — exatamente o nome das
# pastas que já existem em ~/backups, então o histórico não se perde.
descobrir_projetos() {
    local c imagem projeto
    for c in $(docker ps --format '{{.Names}}' 2>/dev/null); do
        imagem=$(docker inspect -f '{{.Config.Image}}' "$c" 2>/dev/null) || continue
        case "$imagem" in postgres:*) ;; *) continue ;; esac
        projeto=$(docker inspect -f \
            '{{index .Config.Labels "com.docker.compose.project"}}' "$c" 2>/dev/null)
        [ -n "$projeto" ] || continue
        printf '%s:%s\n' "${projeto//-/_}" "$c"
    done | sort
}

# Projetos que JÁ tiveram dump e agora não têm contêiner rodando.
#
# É o único caso que a descoberta sozinha não enxerga: contêiner parado não
# aparece em `docker ps`, e um banco que sumiu ficaria indistinguível de um
# banco que nunca existiu aqui. Comparar com o histórico em disco recupera o
# aviso que a lista fixa dava — e amplia, porque vale para qualquer projeto já
# visto, e não só para os que alguém lembrou de escrever.
#
# Pasta sem nenhum `.dump` não conta: é resto de tentativa, não banco perdido.
descobrir_desaparecidos() {
    local rodando="$1" dir slug
    for dir in "$DEST"/*/; do
        [ -d "$dir" ] || continue
        slug=$(basename "$dir")
        compgen -G "$dir/*.dump" >/dev/null || continue
        printf '%s\n' "$rodando" | grep -q "^${slug}:" && continue
        printf '%s\n' "$slug"
    done
}

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

    # shellcheck disable=SC2012  # este script é quem nomeia os dumps, e o nome
    # é slug + carimbo de tempo: sem espaço, sem quebra de linha, nada que o
    # `ls` possa quebrar. Vale para as três ocorrências deste arquivo.
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
    # shellcheck disable=SC2012  # ver o motivo em `motivo_backup`. Aqui há uma
    # segunda rede: quem protege o dump mais novo é o `! -samefile` do `find`
    # abaixo, que compara inode e não nome.
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
    local projetos desaparecidos

    projetos=$(descobrir_projetos)

    # "Nenhum banco encontrado" NUNCA pode sair como sucesso: um ciclo que não
    # salvou nada e terminou bem é exatamente o silêncio que este backup existe
    # para não produzir. Quando havia lista fixa, um Docker fora do ar dava
    # cinco erros barulhentos; a descoberta precisa fazer esse barulho sozinha.
    if [ -z "$projetos" ]; then
        log "ERRO: nenhum contêiner postgres rodando — nada foi salvo"
        log "  (docker fora do ar, ou os bancos não subiram: docker ps)"
        return 1
    fi

    for entrada in $projetos; do
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

    # Banco que já teve dump e não está mais de pé: não há o que salvar, mas há
    # o que dizer. Conta como falha de propósito — o `OnFailure=` do serviço é
    # o que transforma isto em aviso, e um banco de produção que sumiu sem
    # ninguém mandar sumir é precisamente o que se quer ouvir.
    desaparecidos=$(descobrir_desaparecidos "$projetos")
    if [ -n "$desaparecidos" ]; then
        while IFS= read -r slug; do
            [ -n "$slug" ] || continue
            log "ERRO: $slug tem backup anterior e nenhum contêiner postgres rodando"
            falhas=$((falhas + 1))
        done <<<"$desaparecidos"
    fi

    if [ "$falhas" -gt 0 ]; then
        log "$falhas projeto(s) falharam"
        return 1
    fi
    log "ciclo concluído sem falhas"
}

# A união do que está rodando agora com o que já tem pasta em disco.
#
# Os dois lados importam e por motivos opostos: um banco recém-subido e ainda
# sem dump precisa aparecer (é o estado de um VPS novo, e "não aparece" seria
# lido como "não existe"), e um banco que sumiu também precisa (é justamente o
# que se quer investigar). Nenhuma lista escrita à mão daria as duas coisas.
slugs_conhecidos() {
    local entrada dir
    {
        for entrada in $(descobrir_projetos); do
            printf '%s\n' "${entrada%%:*}"
        done
        for dir in "$DEST"/*/; do
            [ -d "$dir" ] || continue
            basename "$dir"
        done
    } | sed '/^$/d' | sort -u
}

estado() {
    printf '%-26s %-6s %-22s %-10s %s\n' PROJETO DUMPS ULTIMO_BACKUP TAMANHO CONFERIDO
    for slug in $(slugs_conhecidos); do
        local dir="$DEST/$slug"
        local n ultimo quando tam conf
        # Contagem por glob: `ls | wc -l` com pipefail dispara o ramo de erro
        # quando a pasta está vazia, e a contagem sai duplicada.
        local -a arquivos=()
        shopt -s nullglob; arquivos=("$dir"/*.dump); shopt -u nullglob
        n=${#arquivos[@]}
        # shellcheck disable=SC2012  # ver o motivo em `motivo_backup`.
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
