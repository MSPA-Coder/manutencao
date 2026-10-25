#!/usr/bin/env bash
# Backup diário dos bancos de produção, dos volumes rotulados, dos sites que o
# nginx publica e da configuração do servidor.
#
#   ./backup-db.sh            faz o ciclo de tudo o que encontrar
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
# Dump de banco é o dado inteiro em claro: nasce legível só pelo dono. Quem lê
# os backups (agente, vigia, bot) roda como o mesmo usuário (25/10/2026).
umask 077

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=app-lock.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/app-lock.sh"

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
# O CRITÉRIO É O RÓTULO mspa.backup.postgres=true OU A IMAGEM LEGADA
# (`postgres:*` / `mspa-postgres:*`). O rótulo declara o papel do contêiner
# independentemente do registry, digest ou ID local usado num rollback.
# Só o serviço de banco o declara; migrate/db-provision não são servidores.
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
    local c imagem projeto rotulo
    for c in $(docker ps --format '{{.Names}}' 2>/dev/null); do
        imagem=$(docker inspect -f '{{.Config.Image}}' "$c" 2>/dev/null) || continue
        case "$imagem" in
            postgres:*|mspa-postgres:*) ;;
            *)
                rotulo=$(docker inspect -f '{{index .Config.Labels "mspa.backup.postgres"}}' "$c" 2>/dev/null) || continue
                [ "$rotulo" = true ] || continue ;;
        esac
        projeto=$(docker inspect -f \
            '{{index .Config.Labels "com.docker.compose.project"}}' "$c" 2>/dev/null)
        [ -n "$projeto" ] || continue
        printf '%s:%s\n' "${projeto//-/_}" "$c"
    done | sort
}

# Só é backup de um projeto o nome que este script produz para ele
# (`fazer_dump` e `fazer_copia`): `<slug>_banco_<carimbo>.dump` e
# `<slug>_volume_<carimbo>.tar.gz`. `eh_backup <pasta> <ext> <arquivo>`.
#
# POR QUE (10/10/2026): um dump manual deixado em `~/backups/manual/` fez o
# ciclo acusar "manual tem backup anterior e nenhum contêiner postgres" e sair
# com falha, e o mesmo arquivo derrubou a sincronização do BackupRestore (ver
# `eh_backup_do_projeto` no `backup-agent.sh`, que segue a mesma regra). Dump
# manual mora em `~/backups-arquivados/`; se cair aqui, não vira histórico de
# projeto, não conta como o mais recente e a retenção não o apaga.
eh_backup() {
    local slug tipo
    slug=$(basename "$1")
    case "$2" in
        dump)   tipo=banco ;;
        tar.gz) tipo=volume ;;
        *)      return 1 ;;
    esac
    [[ "$(basename "$3")" =~ ^${slug}_${tipo}_[0-9]{8}_[0-9]{6}\.${2//./\\.}$ ]]
}

# Os backups de uma pasta, do mais novo para o mais velho, um por linha.
# `backups_do_projeto <pasta> <ext>`.
backups_do_projeto() {
    local arq
    # shellcheck disable=SC2012  # o `ls -t` só ordena; quem decide é o nome que
    # passa por `eh_backup` (slug e carimbo, sem espaço nem quebra de linha).
    ls -1t "$1"/*."$2" 2>/dev/null | while IFS= read -r arq; do
        eh_backup "$1" "$2" "$arq" || continue
        printf '%s\n' "$arq"
    done || true
}

# Projetos que JÁ tiveram dump e agora não têm contêiner rodando.
#
# É o único caso que a descoberta sozinha não enxerga: contêiner parado não
# aparece em `docker ps`, e um banco que sumiu ficaria indistinguível de um
# banco que nunca existiu aqui. Comparar com o histórico em disco recupera o
# aviso que a lista fixa dava — e amplia, porque vale para qualquer projeto já
# visto, e não só para os que alguém lembrou de escrever.
#
# Pasta sem nenhum backup do projeto não conta: é resto de tentativa, ou dump
# manual (ver `eh_backup`), não banco perdido. A mesma pergunta vale para os
# volumes, trocando a extensão (`tar.gz`) e a lista do que está rodando (a de
# `descobrir_volumes`).
descobrir_desaparecidos() {
    local rodando="$1" ext="$2" dir slug
    for dir in "$DEST"/*/; do
        [ -d "$dir" ] || continue
        slug=$(basename "$dir")
        [ -n "$(backups_do_projeto "$dir" "$ext")" ] || continue
        grep -Eq "^${slug}:" <<<"$rodando" && continue
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

    ultimo=$(backups_do_projeto "$dir" dump | head -1 || true)
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
    # Quem protege o mais novo é o `-ef` abaixo, que compara inode e não nome.
    mais_novo=$(backups_do_projeto "$dir" "$ext" | head -1 || true)
    [ -z "$mais_novo" ] && return 0

    # O `-ef` é o piso: o mais recente nunca sai, por mais velho que seja. Era
    # o `! -samefile` do `find`, que só o GNU tem. No VPS funcionava; no
    # busybox da imagem `bash:5.2`, onde a suíte roda localmente, o `find`
    # recusava a opção e a retenção não removia nada, sem erro.
    while IFS= read -r -d '' velho; do
        [ "$velho" -ef "$mais_novo" ] && continue
        eh_backup "$dir" "$ext" "$velho" || continue
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
    ultimo=$(backups_do_projeto "$dir" tar.gz | head -1 || true)
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

    # A trava é deliberadamente estreita: só protege o snapshot que pausa o
    # contêiner. Dumps PostgreSQL e backups de outros apps continuam podendo
    # rodar durante o deploy de uma aplicação diferente.
    if travar_app "$slug"; then
        :
    else
        return $?
    fi
    if ! copiar_volume "$container" "$caminho" "$tmp"; then
        destravar_app
        return 1
    fi
    destravar_app

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

# --------------------------------------------------------------------------
# Sites publicados e configuração do servidor (25/10/2026)
#
# POR QUE EXISTE. O backup cobria só o ESTADO das aplicações (bancos e volumes
# rotulados), porque o código delas é espelho do `main` no GitHub. Mas os
# servidores passaram a hospedar sites estáticos que não estão em Git nenhum
# (o villa-rica, no VPS2, só existia no servidor), e a reconstrução de uma
# máquina perdida dependia de configuração que também só existia nela: vhosts
# do nginx, unidades do systemd, regras do firewall.
#
# O QUE É "SITE": tudo o que o nginx publica, descoberto dos vhosts habilitados,
# nunca de uma lista (o porquê está em `descobrir_projetos`).
#   - `root`/`alias` -> a pasta servida (site estático);
#   - `proxy_pass` para uma porta local -> a pasta do Compose do contêiner que
#     publica essa porta (o rótulo `com.docker.compose.project.working_dir`).
# Um site novo entra sozinho no ciclo seguinte; o slug é `site_<pasta>`.
#
# O QUE NÃO ENTRA: segredos (`.env*`, `.secrets/`, `*.key`, `*.pem`) e o que se
# regenera (`.git`, dependências, caches). Os segredos continuam no cofre, à mão,
# como os dos aplicativos (KIT_RECUPERACAO.md do BackupRestore); os certificados
# o certbot emite de novo.
#
# SÓ GRAVA QUANDO MUDA, pela mesma regra de `motivo_copia`: a cópia é montada de
# forma determinística (lista ordenada, `gzip -n`), então o mesmo conteúdo dá o
# mesmo SHA-256 e não vira arquivo novo. O nome segue o formato que o agente já
# entrega (`<slug>_volume_<carimbo>.tar.gz`): o `backup-agent.sh` não muda.
#
# SITE QUE SAI DO NGINX não é falha, ao contrário de um banco que some: é o
# operador tirando uma experiência do ar. O ciclo avisa no log e continua
# marcando a conferência, para o vigia não alertar todo dia; as cópias antigas
# ficam (o agente nunca apaga a mais recente). Para esquecê-lo de vez, apague
# `~/backups/site_<pasta>`.
# --------------------------------------------------------------------------

# Sobrescrevíveis para a suíte, pelo mesmo motivo de `DEST`.
CONFIG_RAIZ=${CONFIG_RAIZ:-}
NGINX_HABILITADOS=${NGINX_HABILITADOS:-$CONFIG_RAIZ/etc/nginx/sites-enabled}
# Pastas do nginx que não são site: a página padrão e o webroot do certbot.
PASTAS_NAO_SITE=${PASTAS_NAO_SITE:-/var/www/html /var/www/certbot}
# Leitura com `sudo -n`: há arquivos de site e de `/etc` que só o root lê. Só
# leitura; o arquivo gravado continua do usuário do serviço.
LEITOR=${LEITOR-sudo -n}
SLUG_CONFIG=configuracao_servidor
# Caminho de arquivo de configuração que é segredo (ver `copiar_configuracao`).
PADRAO_SEGREDO='(^|/)(segredos|\.secrets)/|\.(key|pem)$|(^|/)\.env(\.[^/]*)?$|(^|/)letsencrypt/(live|archive|accounts|keys)/'

# O que a configuração do servidor leva, relativo à raiz. Pasta entra inteira
# (só arquivos regulares). O que não existir na máquina é pulado.
CONFIG_ITENS=(
    etc/nginx
    etc/systemd/system
    etc/letsencrypt/renewal
    etc/letsencrypt/renewal-hooks
    etc/letsencrypt/options-ssl-nginx.conf
    etc/fail2ban/jail.local
    etc/fail2ban/jail.d
    etc/ssh/sshd_config
    etc/ssh/sshd_config.d
    etc/iptables
    etc/docker/daemon.json
    etc/sudoers.d
    etc/crontab
    etc/cron.d
    etc/hosts
    etc/hostname
    etc/timezone
    home/ubuntu/.ssh/config
    home/ubuntu/.ssh/authorized_keys
)

slug_de_pasta() {
    local nome
    nome=$(basename "$1" | tr 'A-Z.-' 'a-z__' | tr -cd 'a-z_')
    nome=$(sed -e 's/__*/_/g' -e 's/^_//' -e 's/_$//' <<<"$nome")
    [ -n "$nome" ] || return 1
    printf 'site_%s\n' "$nome"
}

# Pasta do Compose do contêiner que publica a porta local `$1`.
pasta_da_porta() {
    local porta="$1" nome portas
    while IFS=$'\t' read -r nome portas; do
        [ -n "$nome" ] || continue
        case ",$portas," in
            *":$porta->"*)
                docker inspect -f \
                    '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' \
                    "$nome" 2>/dev/null
                return 0 ;;
        esac
    done < <(docker ps --format $'{{.Names}}	{{.Ports}}' 2>/dev/null)
    return 1
}

# As diretivas de um vhost, uma por linha (`nome argumentos`), qualquer que
# seja a formatação: sem comentários e quebrado em `{`, `}` e `;`. Ler linha a
# linha perdia `location / { proxy_pass ...; }` escrito numa linha só.
diretivas_do_vhost() {
    sed -e 's/#.*//' -e 's/[{};]/\n/g' "$1" \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]\{1,\}/ /g' -e 's/ $//' \
        | sed '/^$/d'
}

# Saída: `slug|pasta|origem|domínios`, uma linha por pasta, ordenada.
# `origem` é `estático` ou `porta <n>`.
descobrir_sites() {
    local vhost linha pasta porta dominios origem slug diretivas
    [ -d "$NGINX_HABILITADOS" ] || return 0
    for vhost in "$NGINX_HABILITADOS"/*; do
        [ -f "$vhost" ] || continue
        diretivas=$(diretivas_do_vhost "$vhost")
        dominios=$(sed -n 's/^server_name //p' <<<"$diretivas" \
            | tr ' ' '\n' | sed '/^_\{0,1\}$/d' | sort -u | tr '\n' ' ' | sed 's/ $//')
        while IFS= read -r linha; do
            pasta=""; origem=""
            case "$linha" in
                root\ *|alias\ *)
                    pasta=${linha#* }; origem="estático" ;;
                proxy_pass\ *)
                    porta=$(sed -n 's#^proxy_pass https\{0,1\}://\(127\.0\.0\.1\|localhost\):\([0-9]\{1,5\}\).*#\2#p' <<<"$linha")
                    [ -n "$porta" ] || continue
                    pasta=$(pasta_da_porta "$porta") || continue
                    origem="porta $porta" ;;
            esac
            pasta=${pasta%/}
            [ -n "$pasta" ] || continue
            case " $PASTAS_NAO_SITE " in *" $pasta "*) continue ;; esac
            caminho_valido "$pasta" || continue
            slug=$(slug_de_pasta "$pasta") || continue
            printf '%s|%s|%s|%s\n' "$slug" "$pasta" "$origem" "${dominios:--}"
        done < <(grep -E '^(root|alias|proxy_pass) ' <<<"$diretivas" | cut -d' ' -f1,2)
    done | sort -t'|' -k1,1 -k3,3 | awk -F'|' '!visto[$1 "|" $2]++'
}

# Lista ordenada (relativa a `$1`) dos arquivos regulares de um site, sem o que
# é segredo ou se regenera.
arquivos_do_site() {
    (cd "$1" && $LEITOR find . \
        \( -name .git -o -name node_modules -o -name .venv -o -name venv \
           -o -name __pycache__ -o -name .pytest_cache -o -name .mypy_cache \
           -o -name .ruff_cache -o -name .secrets \) -prune \
        -o -type f ! -name '.env' ! -name '.env.*' ! -name '*.key' ! -name '*.pem' \
        -print) | LC_ALL=C sort
}

# Os segredos que `arquivos_do_site` deixa de fora, só os nomes, para o
# inventário dizer o que buscar no cofre.
segredos_do_site() {
    (cd "$1" && $LEITOR find . \
        \( -name .git -o -name node_modules -o -name .venv -o -name venv \
           -o -name __pycache__ \) -prune \
        -o -type f \( -name '.env' -o -name '.env.*' -o -name '*.key' -o -name '*.pem' \
                      -o -path '*/.secrets/*' \) -print) 2>/dev/null \
        | sed 's#^\./##' | LC_ALL=C sort
}

# Grava `$2` (tar.gz) a partir da lista `$3`, relativa a `$1`, e o relê.
empacotar() {
    local base="$1" tmp="$2" lista="$3" listagem
    if ! $LEITOR tar -C "$base" -cf - -T "$lista" 2>/dev/null | gzip -n >"$tmp"; then
        rm -f "$tmp"
        log "  ERRO: não foi possível empacotar $base"
        return 1
    fi
    if ! gzip -t "$tmp" 2>/dev/null || ! listagem=$(tar -tvzf "$tmp" 2>/dev/null); then
        rm -f "$tmp"
        log "  ERRO: cópia reprovada na releitura (gzip -t, tar)"
        return 1
    fi
    if ! grep -q '^-' <<<"$listagem"; then
        rm -f "$tmp"
        log "  ERRO: a cópia não tem nenhum arquivo"
        return 1
    fi
}

# Dá o nome final a `$2` se `motivo_copia` aprovar; senão o descarta.
# `gravar_se_mudou <pasta do projeto> <tmp> <final> <forcar>`.
gravar_se_mudou() {
    local dir="$1" tmp="$2" final="$3" forcar="$4" sha motivo
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
    log "  gravado $(basename "$final") ($(du -h "$final" | cut -f1))"
    aplicar_retencao "$dir" tar.gz
}

copiar_site() {
    local slug="$1" pasta="$2" forcar="$3"
    local dir="$DEST/$slug" nome tmp lista
    if [ ! -d "$pasta" ]; then
        log "  ERRO: a pasta $pasta, publicada pelo nginx, não existe"
        return 1
    fi
    mkdir -p "$dir"
    nome="${slug}_volume_$(date -u '+%Y%m%d_%H%M%S').tar.gz"
    tmp="$dir/.${nome}.tmp"
    lista="$dir/.lista.tmp"
    if ! arquivos_do_site "$pasta" >"$lista" || [ ! -s "$lista" ]; then
        rm -f "$lista"
        log "  ERRO: nenhum arquivo legível em $pasta"
        return 1
    fi
    if ! empacotar "$pasta" "$tmp" "$lista"; then
        rm -f "$lista"
        return 1
    fi
    rm -f "$lista"
    gravar_se_mudou "$dir" "$tmp" "$dir/$nome" "$forcar"
}

# Texto que explica a máquina a quem for reconstruí-la. Sem nada que mude
# sozinho (hora, uptime, estado de contêiner): uma linha diferente aqui é uma
# mudança de verdade, e vira cópia nova.
inventario() {
    local sites="$1" segredos="${2:-}" slug pasta origem dominios git item segs
    printf 'INVENTÁRIO DO SERVIDOR %s\n\n' "$(cat "$CONFIG_RAIZ/etc/hostname" 2>/dev/null || hostname)"
    printf 'Sistema: %s (%s)\n' \
        "$(sed -n 's/^PRETTY_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$CONFIG_RAIZ/etc/os-release" 2>/dev/null || true)" \
        "$(uname -m)"
    if command -v tailscale >/dev/null 2>&1; then
        printf 'Tailscale: %s\n' "$(tailscale ip -4 2>/dev/null | head -1)"
    fi

    printf '\nSITES PUBLICADOS PELO NGINX (cópia dos arquivos em ~/backups/<slug>)\n'
    if [ -z "$sites" ]; then
        printf '  nenhum\n'
    fi
    while IFS='|' read -r slug pasta origem dominios; do
        [ -n "$slug" ] || continue
        git="sem Git"
        if [ -d "$pasta/.git" ]; then
            git="Git $(git -C "$pasta" remote get-url origin 2>/dev/null || echo '(sem origin)')"
            git="$git @ $(git -C "$pasta" rev-parse --short HEAD 2>/dev/null || echo '?')"
            if [ -n "$(git -C "$pasta" status --porcelain 2>/dev/null)" ]; then
                git="$git, COM ALTERAÇÕES LOCAIS"
            fi
        fi
        printf '  %s\n    domínios: %s\n    servido por: %s\n    pasta: %s\n    código: %s\n' \
            "$slug" "$dominios" "$origem" "$pasta" "$git"
        segs=$(segredos_do_site "$pasta" | tr '\n' ' ' | sed 's/ $//')
        printf '    segredos fora da cópia (do cofre): %s\n' "${segs:-nenhum}"
    done <<<"$sites"

    printf '\nVHOSTS HABILITADOS (links em sites-enabled)\n'
    for vhost in "$NGINX_HABILITADOS"/*; do
        [ -e "$vhost" ] && printf '  %s\n' "$(basename "$vhost")"
    done
    printf '\nCONTÊINERES (nome e imagem)\n'
    docker ps --format '{{.Names}}  {{.Image}}' 2>/dev/null | LC_ALL=C sort | sed 's/^/  /' || true

    if command -v systemctl >/dev/null 2>&1; then
        printf '\nTIMERS HABILITADOS\n'
        systemctl list-unit-files --type=timer --state=enabled --no-legend --no-pager 2>/dev/null \
            | awk '{print "  " $1}' | LC_ALL=C sort || true
    fi
    if command -v apt-mark >/dev/null 2>&1; then
        printf '\nPACOTES INSTALADOS À MÃO (apt-mark showmanual)\n'
        apt-mark showmanual 2>/dev/null | LC_ALL=C sort | tr '\n' ' ' | fold -s -w 78 | sed 's/^/  /'
        printf '\n'
    fi

    printf '\nSEGREDOS QUE NÃO ESTÃO NESTE PACOTE (recriar a partir do cofre)\n'
    if [ -n "$segredos" ]; then
        while IFS= read -r item; do printf '  /%s\n' "$item"; done <<<"$segredos"
    else
        printf '  nenhum encontrado\n'
    fi

    cat <<'FIM'

COMO RECONSTRUIR ESTA MÁQUINA (roteiro curto)
  1. Criar a VM (mesma arquitetura e versão do Ubuntu acima), entrar no
     Tailscale e instalar docker, nginx, certbot e fail2ban.
  2. Clonar o repositório `manutencao` em ~/manutencao e rodar
     `bash vps/instalar.sh` (scripts e timers).
  3. Copiar os arquivos deste pacote de volta para os mesmos caminhos
     (etc/nginx -> /etc/nginx etc.), conferindo antes de sobrescrever, e
     religar os vhosts listados acima:
     `ln -s /etc/nginx/sites-available/<nome> /etc/nginx/sites-enabled/`.
  4. Para cada site acima: com Git, clonar o repositório na pasta indicada;
     sem Git, extrair a cópia de ~/backups/<slug>. Depois, os segredos do cofre.
  5. Emitir os certificados de novo (`certbot --nginx -d <domínio>`),
     `nginx -t` e recarregar. Aplicativos com banco: RESTAURAR.md do BackupRestore.
FIM
}

copiar_configuracao() {
    local sites="$1" forcar="$2"
    local dir="$DEST/$SLUG_CONFIG" nome tmp lista area item
    mkdir -p "$dir"
    nome="${SLUG_CONFIG}_volume_$(date -u '+%Y%m%d_%H%M%S').tar.gz"
    tmp="$dir/.${nome}.tmp"
    area=$(mktemp -d "$dir/.area.XXXXXX")
    lista="$area.lista"

    # Uma área com os arquivos nos caminhos de origem e o inventário na raiz:
    # o pacote abre como uma árvore de `/`. A hora de cada arquivo é a da
    # origem, para o pacote só mudar quando algo mudou.
    local -a presentes=()
    for item in "${CONFIG_ITENS[@]}"; do
        [ -e "$CONFIG_RAIZ/$item" ] && presentes+=("$item")
    done
    # Segredo fica fora, como nos sites; só o NOME vai para o inventário, para
    # quem reconstrói saber o que buscar no cofre.
    local todos segredos=""
    todos=$(cd "${CONFIG_RAIZ:-/}" && $LEITOR find "${presentes[@]}" -type f 2>/dev/null \
        | LC_ALL=C sort || true)
    segredos=$(grep -E "$PADRAO_SEGREDO" <<<"$todos" || true)
    grep -Ev "$PADRAO_SEGREDO" <<<"$todos" | sed '/^$/d' >"$lista" || true
    # Um `tar` com o leitor e outro sem ele: uma leitura privilegiada só, em vez
    # de duas por arquivo (o `sudo` de cada uma enchia o journal), e a hora de
    # cada arquivo vem junto -- inclusive de pasta que só o root atravessa
    # (`/etc/sudoers.d`), onde o `touch -r` do usuário falhava e o pacote mudava
    # todo dia (visto no ensaio do VPS2).
    if [ -s "$lista" ] && ! { $LEITOR tar -C "${CONFIG_RAIZ:-/}" -cf - -T "$lista" 2>/dev/null \
            | tar -C "$area" -xf - 2>/dev/null; }; then
        rm -rf "$area" "$lista"
        log "  ERRO: não foi possível copiar a configuração"
        return 1
    fi
    # O que veio com modo restrito (`0440` do sudoers, pasta `0555`) precisa
    # ser lido e apagado pelo usuário do serviço daqui em diante.
    chmod -R u+rwX "$area"
    inventario "$sites" "$segredos" >"$area/INVENTARIO.txt"
    touch -d '@0' "$area/INVENTARIO.txt" 2>/dev/null || touch -t 197001010000 "$area/INVENTARIO.txt"

    (cd "$area" && find . -type f) | LC_ALL=C sort >"$lista"
    if ! LEITOR='' empacotar "$area" "$tmp" "$lista"; then
        rm -rf "$area" "$lista"
        return 1
    fi
    rm -rf "$area" "$lista"
    gravar_se_mudou "$dir" "$tmp" "$dir/$nome" "$forcar"
}

# Pastas de site que já tiveram cópia e não estão mais no nginx.
sites_fora_do_ar() {
    local sites="$1" dir slug
    for dir in "$DEST"/site_*/; do
        [ -d "$dir" ] || continue
        slug=$(basename "$dir")
        [ -n "$(backups_do_projeto "$dir" tar.gz)" ] || continue
        grep -Eq "^${slug}\|" <<<"$sites" && continue
        printf '%s\n' "$slug"
    done
}

ciclo() {
    local forcar="${1:-nao}"
    local falhas=0
    local projetos volumes desaparecidos sites

    projetos=$(descobrir_projetos)

    # "Nenhum banco encontrado" NUNCA pode sair como sucesso: um ciclo que não
    # salvou nada e terminou bem é exatamente o silêncio que este backup existe
    # para não produzir. Quando havia lista fixa, um Docker fora do ar dava
    # cinco erros barulhentos; a descoberta precisa fazer esse barulho sozinha.
    #
    # Conta como falha e segue, em vez de encerrar: os volumes, mais abaixo,
    # não dependem de Postgres nenhum estar de pé.
    #
    # Desde 25/10/2026 a máquina sem banco nenhum é normal (o VPS2 só serve
    # sites), então o barulho ficou com quem o merece: o Docker que não
    # responde. Banco que existia e não subiu continua acusado logo abaixo,
    # como desaparecido, porque deixou histórico em disco.
    if ! docker ps >/dev/null 2>&1; then
        log "ERRO: o docker não responde — nenhum banco nem volume foi salvo"
        log "  (docker fora do ar: systemctl status docker)"
        falhas=$((falhas + 1))
    elif [ -z "$projetos" ]; then
        log "nenhum contêiner postgres nesta máquina — sem bancos a salvar"
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

    # Sites e a configuração também gravam `.tar.gz`, mas não vêm de contêiner
    # rotulado: o sumiço deles é tratado mais abaixo.
    desaparecidos=$(descobrir_desaparecidos "$volumes" tar.gz \
        | grep -Ev "^(site_.*|$SLUG_CONFIG)$" || true)
    if [ -n "$desaparecidos" ]; then
        while IFS= read -r slug; do
            [ -n "$slug" ] || continue
            log "ERRO: $slug tem cópia de volume anterior e nenhum contêiner com o rótulo $ROTULO_VOLUME rodando"
            falhas=$((falhas + 1))
        done <<<"$desaparecidos"
    fi

    sites=$(descobrir_sites)
    local vistos=" " slug pasta origem dominios
    while IFS='|' read -r slug pasta origem dominios; do
        [ -n "$slug" ] || continue
        log "== $slug (site: $dominios)"
        if [[ "$vistos" == *" $slug "* ]]; then
            log "  ERRO: outra pasta já usa o slug $slug ($pasta) — renomeie uma das duas"
            falhas=$((falhas + 1))
            continue
        fi
        vistos="$vistos$slug "
        if ! copiar_site "$slug" "$pasta" "$forcar"; then
            falhas=$((falhas + 1))
        fi
    done <<<"$sites"

    while IFS= read -r slug; do
        [ -n "$slug" ] || continue
        log "== $slug (site)"
        log "  AVISO: não está mais no nginx — as cópias antigas ficam;"
        log "  para esquecê-lo, apague $DEST/$slug"
        date -u '+%Y-%m-%dT%H:%M:%SZ' > "$DEST/$slug/.ultima_conferencia"
    done < <(sites_fora_do_ar "$sites")

    log "== $SLUG_CONFIG"
    if ! copiar_configuracao "$sites" "$forcar"; then
        falhas=$((falhas + 1))
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
        descobrir_sites | cut -d'|' -f1
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
        # Só os backups do projeto (ver `eh_backup`); `mapfile` e não
        # `ls | wc -l`, que com pipefail dispara o ramo de erro quando a pasta
        # está vazia e a contagem sai duplicada.
        local -a arquivos=()
        mapfile -t arquivos < <(backups_do_projeto "$dir" dump; backups_do_projeto "$dir" tar.gz)
        n=${#arquivos[@]}
        ultimo=""
        if [ "$n" -gt 0 ]; then
            # shellcheck disable=SC2012  # nomes já filtrados por `eh_backup`.
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
