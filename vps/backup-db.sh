#!/usr/bin/env bash
# Backup diário dos bancos de produção e dos volumes rotulados.
#
#   ./backup-db.sh            faz o ciclo dos bancos e volumes que encontrar rodando
#   ./backup-db.sh --estado   mostra o estado sem alterar nada
#   ./backup-db.sh --forcar   ignora a checagem de alteração e grava de novo
#
# O que este script NUNCA faz: ligar, parar ou recriar contêiner. Se o Postgres
# de um projeto não estiver de pé, ele registra a falha e segue para o próximo.
# Consertar a produção às 3 da manhã não é tarefa de um backup. A única
# intervenção é a pausa de segundos durante a cópia de um volume, explicada em
# `copiar_volume`.
#
# Ordem de cada dump (e de cada cópia de volume), e o motivo de cada passo:
#   1. nasce em .tmp                  um dump cortado nunca tem nome de dump bom
#   2. relido com pg_restore --list   código de saída zero não prova nada
#      (o volume, com gzip -t e tar)
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

# Rótulo que um contêiner declara no próprio Compose para ter um diretório
# copiado: o valor é o caminho absoluto, DENTRO do contêiner, do que precisa
# voltar depois de um desastre. Ver `descobrir_volumes`.
ROTULO_VOLUME=mspa.backup.volume

# Teto da pausa, que dura a cópia inteira, compressão incluída. O volume que
# existe hoje (o SQLite do Wealthfolio, poucos MB) copia em menos de um
# segundo; passar disto é sinal de problema ou de um volume que cresceu além do
# que este método serve, e a aplicação não pode ficar congelada esperando. A
# cópia cortada pelo teto é falha, e alerta.
PAUSA_MAX_SEGUNDOS=120

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
# A mesma pergunta vale para os volumes, trocando a extensão (`tar.gz`) e a
# lista do que está rodando (a de `descobrir_volumes`).
descobrir_desaparecidos() {
    local rodando="$1" ext="$2" dir slug
    for dir in "$DEST"/*/; do
        [ -d "$dir" ] || continue
        slug=$(basename "$dir")
        compgen -G "$dir/*.$ext" >/dev/null || continue
        printf '%s\n' "$rodando" | grep -q "^${slug}:" && continue
        printf '%s\n' "$slug"
    done
}

# Volumes que precisam de cópia: contêineres rodando com o rótulo
# `mspa.backup.volume`. Saída `slug:contêiner:caminho`.
#
# POR QUE EXISTE (02/10/2026): o Wealthfolio guarda o patrimônio num SQLite
# dentro do volume `wealthfolio-teste-data`, e o critério `postgres:*` acima
# não o enxerga. O histórico de snapshots que ele acumula não sai de nenhum
# dos bancos de origem, então perder o volume é perder esse histórico.
#
# POR QUE RÓTULO, e não nome de volume ou imagem: quem sabe onde mora o estado
# é a própria aplicação, e o rótulo fica no Compose dela, ao lado do volume.
# Uma lista de volumes aqui seria a sexta lista escrita à mão (ver o porquê da
# descoberta em `descobrir_projetos`).
descobrir_volumes() {
    local c caminho projeto
    for c in $(docker ps --format '{{.Names}}' 2>/dev/null); do
        caminho=$(docker inspect -f \
            "{{index .Config.Labels \"$ROTULO_VOLUME\"}}" "$c" 2>/dev/null) || continue
        [ -n "$caminho" ] || continue
        projeto=$(docker inspect -f \
            '{{index .Config.Labels "com.docker.compose.project"}}' "$c" 2>/dev/null)
        [ -n "$projeto" ] || continue
        printf '%s:%s:%s\n' "${projeto//-/_}" "$c" "$caminho"
    done | sort
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
    # `ls` possa quebrar. Vale para as quatro ocorrências deste arquivo.
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

# A retenção é por tipo de arquivo (`dump` ou `tar.gz`): o mais recente de
# cada tipo é o piso, e um não protege o outro.
aplicar_retencao() {
    local dir="$1" ext="$2" mais_novo
    # shellcheck disable=SC2012  # ver o motivo em `motivo_backup`. Aqui há uma
    # segunda rede: quem protege o dump mais novo é o `-ef` abaixo, que compara
    # inode e não nome.
    mais_novo=$(ls -1t "$dir"/*."$ext" 2>/dev/null | head -1 || true)
    [ -z "$mais_novo" ] && return 0

    # O `-ef` é o piso: o mais recente nunca sai, por mais velho que seja. Era
    # o `! -samefile` do `find`, que só o GNU tem. No VPS funcionava; no
    # busybox da imagem `bash:5.2`, onde a suíte roda localmente, o `find`
    # recusava a opção e a retenção não removia nada, sem erro.
    while IFS= read -r -d '' velho; do
        [ "$velho" -ef "$mais_novo" ] && continue
        rm -f "$velho" "$velho.sha256"
        log "  retenção: removido $(basename "$velho")"
    done < <(find "$dir" -maxdepth 1 -name "*.$ext" -mtime +"$RETENCAO_DIAS" \
                  -print0 2>/dev/null)
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

# --------------------------------------------------------------------------
# Cópia de volume rotulado
#
# POR QUE PAUSAR. Um SQLite em modo WAL vive em dois arquivos que mudam juntos
# (o banco e o `-wal`), e o checkpoint move páginas de um para o outro. Copiar
# os dois com a aplicação escrevendo pode juntar o banco de antes com o `-wal`
# de depois: uma cópia que abre sem erro e perdeu dado.
#
# Medido em 02/10/2026, com um SQLite sob escrita contínua que só transfere
# saldo entre contas (a soma nunca muda): sem a pausa, 39 de 40 cópias
# passaram no `PRAGMA integrity_check` com a soma errada; com a pausa, as 12
# cópias fecharam a soma.
#
# `docker pause` congela os processos do contêiner (o freezer do cgroup) sem
# reiniciar nada, e a cópia sai de um instante só, que é o estado que o SQLite
# sabe reabrir. Conexões abertas e requisições em voo continuam de onde
# pararam. A cópia online pela API do SQLite não serve aqui: a imagem não traz
# `sqlite3`, e o banco do Wealthfolio é cifrado.
#
# O contêiner pausado fica em `PAUSADO`, e o `trap` de EXIT o devolve ao
# normal mesmo quando o script morre no meio da cópia: o bash roda o EXIT
# também ao receber TERM (conferido). Só um KILL escapa, e aí quem acusa é o
# vigia, pelo /health parado.
#
# A pausa deixa o contêiner `unhealthy` por alguns segundos sem nenhuma sonda
# reprovada: o Docker o marca assim ao pausar e só o devolve a `healthy` na
# sonda seguinte. O `autocura.sh` reconhece esse caso e não o reinicia.
# --------------------------------------------------------------------------
PAUSADO=""

despausar() {
    [ -n "$PAUSADO" ] || return 0
    if ! docker unpause "$PAUSADO" >/dev/null 2>&1; then
        log "  ERRO: não foi possível despausar $PAUSADO (docker unpause $PAUSADO)"
    fi
    PAUSADO=""
}
trap despausar EXIT

# Absoluto, sem `..` e só com caracteres que o `docker cp` e a lista
# `slug:contêiner:caminho` atravessam sem ambiguidade.
caminho_valido() {
    [[ "$1" =~ ^/[A-Za-z0-9._/-]+$ ]] && [[ "/$1/" != *"/../"* ]]
}

# Copia o diretório para "$3" (tar.gz) com o contêiner pausado e relê a cópia.
# Volume sem nenhum arquivo é reprovado: vazio é suspeito demais para ser
# gravado como backup e, pela retenção, um dia virar o único que sobrou.
copiar_volume() {
    local container="$1" caminho="$2" tmp="$3" copiou=0 listagem

    if ! docker pause "$container" >/dev/null 2>&1; then
        log "  ERRO: não foi possível pausar $container — nada foi copiado"
        return 1
    fi
    PAUSADO="$container"
    # `gzip -n` não grava nome nem hora no cabeçalho: o mesmo conteúdo dá o
    # mesmo arquivo, e é o hash que decide se houve alteração.
    timeout "$PAUSA_MAX_SEGUNDOS" docker cp "$container:$caminho" - 2>/dev/null \
        | gzip -n > "$tmp" || copiou=1
    despausar

    if [ "$copiou" -ne 0 ]; then
        rm -f "$tmp"
        log "  ERRO: docker cp de $container:$caminho falhou"
        return 1
    fi

    # `gzip -t` confere o fluxo inteiro (o CRC fica no fim, e o `tar` pode
    # parar de ler antes dele), e o `tar` confere a estrutura. A listagem vai
    # para uma variável antes do `grep`: com `pipefail`, um `grep -q` que sai
    # cedo derruba o `tar` com SIGPIPE e a cópia boa sairia reprovada.
    if ! gzip -t "$tmp" 2>/dev/null || ! listagem=$(tar -tvzf "$tmp" 2>/dev/null); then
        rm -f "$tmp"
        log "  ERRO: cópia reprovada na releitura (gzip -t, tar)"
        return 1
    fi
    if ! grep -q '^-' <<<"$listagem"; then
        rm -f "$tmp"
        log "  ERRO: a cópia não tem nenhum arquivo — volume vazio?"
        return 1
    fi
}

# Decisão: a cópia nova merece ser gravada?
#
# O SQLite não tem um LSN para perguntar ANTES, como o Postgres. A prova de que
# nada mudou é a própria cópia sair idêntica à última gravada (mesmo SHA-256).
# Fora isso, vale a regra dos dumps: na dúvida, grava.
motivo_copia() {
    local dir="$1" sha="$2" ultimo idade_d
    # shellcheck disable=SC2012  # ver o motivo em `motivo_backup`.
    ultimo=$(ls -1t "$dir"/*.tar.gz 2>/dev/null | head -1 || true)
    [ -z "$ultimo" ] && { echo "primeira cópia"; return 0; }

    idade_d=$(( ( $(date +%s) - $(stat -c %Y "$ultimo") ) / 86400 ))
    [ "$idade_d" -ge "$INTERVALO_MAX_DIAS" ] && \
        { echo "teto de $INTERVALO_MAX_DIAS dias sem cópia"; return 0; }

    [ "$(cat "$ultimo.sha256" 2>/dev/null || true)" = "$sha" ] || \
        { echo "volume alterado"; return 0; }

    return 1
}

# Um volume do começo ao fim. "Sem alterações" é sucesso; só falha devolve
# diferente de zero.
fazer_copia() {
    local slug="$1" container="$2" caminho="$3" forcar="$4"
    local dir="$DEST/$slug" carimbo nome tmp final sha motivo

    if ! caminho_valido "$caminho"; then
        log "  ERRO: rótulo $ROTULO_VOLUME inválido em $container: '$caminho'"
        return 1
    fi
    mkdir -p "$dir"

    carimbo=$(date -u '+%Y%m%d_%H%M%S')
    nome="${slug}_volume_${carimbo}.tar.gz"
    tmp="$dir/.${nome}.tmp"
    final="$dir/$nome"

    copiar_volume "$container" "$caminho" "$tmp" || return 1

    sha=$(sha256sum "$tmp" | awk '{print $1}')
    if [ "$forcar" = sim ]; then
        motivo="forçado"
    elif ! motivo=$(motivo_copia "$dir" "$sha"); then
        rm -f "$tmp"
        date -u '+%Y-%m-%dT%H:%M:%SZ' > "$dir/.ultima_conferencia"
        log "  sem alterações desde a última cópia — nada a fazer"
        return 0
    fi

    log "  motivo: $motivo"
    if ! mv "$tmp" "$final"; then
        rm -f "$tmp"
        log "  ERRO: não foi possível dar o nome final à cópia"
        return 1
    fi
    printf '%s\n' "$sha" > "$final.sha256"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "$dir/.ultima_conferencia"
    log "  gravado $nome ($(du -h "$final" | cut -f1))"
    aplicar_retencao "$dir" tar.gz
}

ciclo() {
    local forcar="${1:-nao}"
    local falhas=0
    local projetos volumes desaparecidos

    projetos=$(descobrir_projetos)

    # "Nenhum banco encontrado" NUNCA pode sair como sucesso: um ciclo que não
    # salvou nada e terminou bem é exatamente o silêncio que este backup existe
    # para não produzir. Quando havia lista fixa, um Docker fora do ar dava
    # cinco erros barulhentos; a descoberta precisa fazer esse barulho sozinha.
    #
    # Conta como falha e segue, em vez de encerrar: os volumes, mais abaixo,
    # não dependem de Postgres nenhum estar de pé.
    if [ -z "$projetos" ]; then
        log "ERRO: nenhum contêiner postgres rodando — nenhum banco foi salvo"
        log "  (docker fora do ar, ou os bancos não subiram: docker ps)"
        falhas=$((falhas + 1))
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
            aplicar_retencao "$dir" dump
        else
            falhas=$((falhas + 1))
        fi
    done

    # Banco que já teve dump e não está mais de pé: não há o que salvar, mas há
    # o que dizer. Conta como falha de propósito — o `OnFailure=` do serviço é
    # o que transforma isto em aviso, e um banco de produção que sumiu sem
    # ninguém mandar sumir é precisamente o que se quer ouvir. Com a descoberta
    # vazia, a guarda lá em cima já disse isso de todos de uma vez.
    desaparecidos=""
    [ -z "$projetos" ] || desaparecidos=$(descobrir_desaparecidos "$projetos" dump)
    if [ -n "$desaparecidos" ]; then
        while IFS= read -r slug; do
            [ -n "$slug" ] || continue
            log "ERRO: $slug tem backup anterior e nenhum contêiner postgres rodando"
            falhas=$((falhas + 1))
        done <<<"$desaparecidos"
    fi

    # Volumes rotulados. Máquina sem nenhum é o normal (o VPS do portal), por
    # isso o vazio aqui não é erro; o que é erro é um volume que já teve cópia
    # e sumiu, acusado logo abaixo como os bancos.
    volumes=$(descobrir_volumes)
    for entrada in $volumes; do
        local slug="${entrada%%:*}" resto="${entrada#*:}"
        log "== $slug (volume)"
        if ! fazer_copia "$slug" "${resto%%:*}" "${resto#*:}" "$forcar"; then
            falhas=$((falhas + 1))
        fi
    done

    desaparecidos=$(descobrir_desaparecidos "$volumes" tar.gz)
    if [ -n "$desaparecidos" ]; then
        while IFS= read -r slug; do
            [ -n "$slug" ] || continue
            log "ERRO: $slug tem cópia de volume anterior e nenhum contêiner com o rótulo $ROTULO_VOLUME rodando"
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
        for entrada in $(descobrir_projetos) $(descobrir_volumes); do
            printf '%s\n' "${entrada%%:*}"
        done
        for dir in "$DEST"/*/; do
            [ -d "$dir" ] || continue
            basename "$dir"
        done
    } | sed '/^$/d' | sort -u
}

# ARQUIVOS conta dumps e cópias de volume juntos; um projeto só tem um dos dois
# hoje, e o nome do arquivo diz qual (`_banco_` ou `_volume_`).
estado() {
    printf '%-26s %-8s %-22s %-10s %s\n' PROJETO ARQUIVOS ULTIMO_BACKUP TAMANHO CONFERIDO
    for slug in $(slugs_conhecidos); do
        local dir="$DEST/$slug"
        local n ultimo quando tam conf
        # Contagem por glob: `ls | wc -l` com pipefail dispara o ramo de erro
        # quando a pasta está vazia, e a contagem sai duplicada.
        local -a arquivos=()
        shopt -s nullglob; arquivos=("$dir"/*.dump "$dir"/*.tar.gz); shopt -u nullglob
        n=${#arquivos[@]}
        ultimo=""
        if [ "$n" -gt 0 ]; then
            # shellcheck disable=SC2012  # ver o motivo em `motivo_backup`.
            ultimo=$(ls -1t "${arquivos[@]}" 2>/dev/null | head -1 || true)
        fi
        if [ -n "$ultimo" ]; then
            quando=$(date -u -d "@$(stat -c %Y "$ultimo")" '+%Y-%m-%d %H:%MZ')
            tam=$(du -h "$ultimo" | cut -f1)
        else
            quando="nunca"; tam="—"
        fi
        conf=$(cat "$dir/.ultima_conferencia" 2>/dev/null || echo "—")
        printf '%-26s %-8s %-22s %-10s %s\n' "$slug" "$n" "$quando" "$tam" "$conf"
    done
}

case "${1:-}" in
    --estado) estado ;;
    --forcar) ciclo sim ;;
    "")       ciclo nao ;;
    *)        echo "Uso: $0 [--estado|--forcar]" >&2; exit 2 ;;
esac
