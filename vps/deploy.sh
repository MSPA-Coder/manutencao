#!/usr/bin/env bash
# Implanta um projeto no VPS a partir do main do GitHub.
#
#   ./deploy.sh <projeto>            implanta o main
#   ./deploy.sh <projeto> --refresh  remonta a versão que já está no ar com
#                                    imagens-base novas, sem aplicar commits
#   ./deploy.sh --status             estado de todos os projetos
#
# Recusa implantar se houver alteração não commitada no servidor: o código do
# servidor é sempre um espelho do main, nunca a origem de uma mudança. O
# rollback usa `git reset --hard`, portanto só pode operar sobre checkout
# limpo.
#
# POR QUE NÃO CONSULTA A CI: desde 20/10/2026 a validação completa é feita na
# máquina do usuário antes do commit, e o deploy só roda quando ele manda. A
# CI do GitHub ficou como aviso. As imagens são montadas aqui, a partir do
# código do main, sem esperar nem baixar nada do GitHub (`montar_imagens`).
#
# POR QUE NADA MUDA SOZINHO: não há timer que implante ou remonte apps. Um
# deploy comum monta sem `--pull`, então as imagens-base continuam as que já
# estavam no servidor; bases novas só entram por `--refresh`.
#
# POR QUE A SONDA É `/health` E NÃO `/login`: a tela de login responde 200 com
# o banco inteiramente fora do ar. Os seis projetos expõem `/health`, que
# consulta o banco e responde 503 quando não consegue. O critério é o CORPO
# conter `"status":"ok"`, não apenas o código HTTP.
#
# POR QUE ROLLBACK AUTOMÁTICO: sem ele, um deploy que quebra o site avisa e
# deixa quebrado; o conserto é para frente, sob pressão, com o site fora. O
# estado anterior é conhecido (o commit de onde saímos) e comprovadamente
# funcionava, então voltar é a ação de menor risco disponível.
#
# LIMITE DO ROLLBACK: ele volta o código e a imagem preservada, mas NÃO desfaz
# migração de banco. Um deploy que execute migração exige antes um backup
# verificado e uma migração retrocompatível, ou um procedimento manual de
# reversão do schema. Este script deliberadamente não tenta adivinhar como
# reverter dados.

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=app-lock.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/app-lock.sh"

APPS=${APPS:-/home/ubuntu/apps}
ALERTA=${ALERTA:-/home/ubuntu/alerta.sh}
ESTADO_DIR=${ESTADO_DIR:-/home/ubuntu/.local/state/mspa-deploy}

# Quanto esperar o endereço público ficar bom antes de declarar falha.
# 12 x 5s = 60s depois de o Compose já ter parado de reportar `starting`.
# Generoso de propósito: um rollback disparado por app lento a aquecer seria
# um estrago causado pela própria rede de proteção.
TENTATIVAS_SAUDE=12

# O `jsonify` do Flask serializa `"status":"ok"` e o `JsonResponse` do Django
# serializa `"status": "ok"`. Espaço em JSON não é parte de contrato nenhum —
# quem tem de ser tolerante é o verificador.
PADRAO_OK='"status"[[:space:]]*:[[:space:]]*"ok"'
PADRAO_SAUDE=$PADRAO_OK

# shellcheck disable=SC2034  # `PORTA` não é lida por este script -- a sonda de
# saúde bate na URL pública, não em 127.0.0.1, de propósito. Ela fica aqui
# porque este `case` é o único lugar do repositório onde a numeração da frota
# (51/52/53/54/56/57) aparece ao lado do projeto correspondente, e essa
# correspondência já precisou ser consultada mais de uma vez. O portal (56xx)
# saiu da frota em 19/10/2026: virou site estático, entregue a um cliente; a
# faixa 56xx fica sem dono. O NetWorth, consolidador que lê o bancário e o renda, entrou em 17/09/2026 no 57xx
# e foi aposentado em 29/09/2026: o Wealthfolio (18088) opera no domínio dele.
projeto_info() {
    APP_SERVICES=(web)
    MIGRATION_SERVICE=migrate
    case "$1" in
        bancario|controle-bancario)
            DIR=controle-bancario;      ENVF=.env.vps;    PORTA=5201
            DOMINIO=bancario-mspa.duckdns.org ;;
        conforto|conforto-termico)
            DIR=conforto-termico;       ENVF=.env.vps;    PORTA=5401
            DOMINIO=conforto-mspa.duckdns.org
            APP_SERVICES=(ict coletor)
            MIGRATION_SERVICE=schema ;;
        megasena|mega-sena)
            DIR=mega-sena;              ENVF=.env.vps;    PORTA=5101
            DOMINIO=megasena-mspa.duckdns.org
            APP_SERVICES=(app) ;;
        renda|controle-renda-variavel)
            DIR=controle-renda-variavel; ENVF=.env.vps;   PORTA=5301
            DOMINIO=renda-mspa.duckdns.org ;;
        wealthfolio)
            DIR=wealthfolio-teste;      ENVF=.env;        PORTA=18088
            DOMINIO=wealthfolio-mspa.duckdns.org
            PADRAO_SAUDE='^ok$' ;;
        *)  echo "Projeto desconhecido: $1" >&2
            echo "Use: bancario | conforto | megasena | renda | wealthfolio" >&2
            return 1 ;;
    esac
}

# Bancário e renda podem compartilhar a rede interna de patrimônio. Recalcular
# antes de cada chamada faz deploy e rollback refletirem o checkout atual.
compose_files() {
    COMPOSE_FILES=(-f compose.yaml)
    if { [ "$DIR" = controle-bancario ] || [ "$DIR" = controle-renda-variavel ] || [ "$DIR" = wealthfolio-teste ]; } \
        && [ -f compose.patrimonio-internal.yaml ]; then
        COMPOSE_FILES+=(-f compose.patrimonio-internal.yaml)
    fi
    if [ -n "${DEPLOY_OVERRIDE:-}" ]; then
        COMPOSE_FILES+=(-f "$DEPLOY_OVERRIDE")
    fi
}

compose() {
    compose_files
    APP_IMAGE="${APP_IMAGE:-}" POSTGRES_IMAGE="${POSTGRES_IMAGE:-}" \
        docker compose --env-file "$ENVF" "${COMPOSE_FILES[@]}" "$@"
}

# Monta aqui, a partir do código do candidato, as imagens do app e do
# PostgreSQL que o `compose.release.yaml` vai fixar por ID. A validação é feita
# na máquina antes do commit (decisão de 20/10/2026); o servidor só monta o que
# foi gravado no main -- ~45 s no bancário. Sem `--pull` num deploy comum: as
# bases que já estão aqui não mudam junto com o código. `--refresh` é que pede
# bases novas, e só quando o usuário manda.
#
# `config --images <serviço>` lista também as imagens das dependências; a do
# app é a lista dele menos a do banco. Daqui em diante só o ID é usado, e o
# rollback volta para os IDs que estavam no ar.
montar_imagens() {
    local opcoes=() servico_banco imagem_banco imagem_app
    if [ "$REFRESH" = 1 ]; then opcoes=(--pull --no-cache); fi
    compose build "${opcoes[@]}" || return 1
    servico_banco=$(compose config --services | grep -xE 'postgres|db') || return 1
    imagem_banco=$(compose config --images "$servico_banco" | sort -u) || return 1
    imagem_app=$(compose config --images "${APP_SERVICES[0]}" | sort -u | grep -vxF -- "$imagem_banco") || return 1
    if [ "$(wc -l <<<"$imagem_banco")" != 1 ] || [ "$(wc -l <<<"$imagem_app")" != 1 ]; then
        echo "Não foi possível identificar uma única imagem de app e de banco." >&2
        return 1
    fi
    APP_IMAGE=$(docker image inspect --format '{{.Id}}' "$imagem_app") || return 1
    POSTGRES_IMAGE=$(docker image inspect --format '{{.Id}}' "$imagem_banco") || return 1
    guardar_imagem "$APP_IMAGE" && guardar_imagem "$POSTGRES_IMAGE" || return 1
    echo "Imagens montadas: $imagem_app ($APP_IMAGE) / $imagem_banco ($POSTGRES_IMAGE)."
}

# Os quatro apps dão o mesmo nome à imagem do banco (`mspa-postgres:17-alpine`).
# Montar um app move esse nome, e no image store do containerd a imagem que fica
# sem nome é apagada -- inclusive a que outro app está rodando, que perde o
# ponto de volta (aconteceu em 20/10/2026 com o banco do CB, do Conforto e do
# Mega-Sena). Por isso cada app guarda, com nome próprio, as imagens que estão
# no ar e as que acabou de montar; `podar_guardas` mantém só a atual e a
# anterior.
GUARDA=mspa-deploy
guardar_imagem() {
    local id=$1
    [[ "$id" =~ ^sha256:[a-f0-9]{64}$ ]] || return 1
    docker image tag "$id" "$GUARDA/$DIR:${id:7:12}"
}

podar_guardas() {
    local manter tag container id
    manter=$(cut -d' ' -f1 "$IMAGENS_ANTERIORES" 2>/dev/null || true)
    for container in $(compose ps -q 2>/dev/null); do
        id=$(docker inspect --format '{{.Image}}' "$container" 2>/dev/null) || continue
        if [ "$(docker image inspect --format '{{.Id}}' "$id" 2>/dev/null)" != "$id" ]; then
            id=$(id_pelo_manifesto "$container" "$(docker inspect --format '{{.Config.Image}}' "$container")") || continue
        fi
        guardar_imagem "$id" || true
        manter+=$'\n'"$id"
    done
    docker image ls --format '{{.Repository}}:{{.Tag}}' "$GUARDA/$DIR" 2>/dev/null | while read -r tag; do
        grep -q "^sha256:${tag##*:}" <<<"$manter" && continue
        docker image rm "$tag" >/dev/null 2>&1 || true
    done
}

# Nunca deixa a notificação derrubar o deploy: um alerta que não sai não pode
# virar o segundo incidente da noite.
alertar() {
    [ -x "$ALERTA" ] || { echo "  (alerta.sh ausente — mensagem não enviada)" >&2; return 0; }
    "$ALERTA" "$1" "${2:-}" >/dev/null 2>&1 || true
}

# Consulta o /health público e devolve 0 só se o corpo trouxer "status":"ok".
# Pública de propósito: assim a verificação atravessa DNS, TLS, nginx,
# aplicação e banco. Uma sonda em 127.0.0.1 aprovaria um site que o mundo não
# alcança.
#
# `-L` porque os seis não concordam sobre a barra final e o APPEND_SLASH do
# Django responde 301 ao caminho sem barra. Seguir o redirecionamento não
# afrouxa nada: o critério continua sendo o corpo.
VERIF_CODE=000
VERIF_CORPO=
verificar_saude() {
    local tentativas="${1:-1}" i resposta
    for i in $(seq 1 "$tentativas"); do
        # `if` e nao `[ ] && sleep`: com `set -e`, um `&&` que reprova no
        # teste devolve 1 como statement e derruba o script inteiro.
        if [ "$i" -gt 1 ]; then sleep 5; fi
        resposta=$(curl -sSL --max-time 15 -w '\n%{http_code}' \
                       "https://$DOMINIO/health" 2>/dev/null || true)
        VERIF_CODE=$(printf '%s' "$resposta" | tail -1)
        VERIF_CORPO=$(printf '%s' "$resposta" | sed '$d')
        if grep -Eq "$PADRAO_SAUDE" <<<"$VERIF_CORPO"; then
            return 0
        fi
    done
    return 1
}

esperar_compose() {
    local i estados
    for ((i = 1; i <= 40; i++)); do
        if ! sleep 5; then
            echo "A espera pelos contêineres foi interrompida." >&2
            return 1
        fi
        if ! estados=$(compose ps --format '{{.Name}}  {{.Status}}' 2>/dev/null); then
            echo "Não foi possível consultar o estado do Compose." >&2
            return 1
        fi
        if ! grep -qi 'starting' <<<"$estados"; then
            printf '%s\n' "$estados" | sed 's/^/  /'
            return 0
        fi
    done
    printf '%s\n' "$estados" | sed 's/^/  /' >&2
    echo "O Compose continuou em estado 'starting' após 200 segundos." >&2
    return 1
}

# Grava somente o SHA, sem segredo, no diretório estável do usuário de deploy.
# O rename no mesmo filesystem torna a troca atômica: nunca fica um SHA parcial.
registrar_implantacao_saudavel() {
    local commit temporario arquivo
    commit=$(git rev-parse HEAD) || return 1
    arquivo="$ESTADO_DIR/$DIR.commit"

    install -d -m 700 "$ESTADO_DIR" || return 1
    temporario=$(mktemp "$ESTADO_DIR/.${DIR}.commit.XXXXXX") || return 1
    if ! chmod 600 "$temporario" || ! printf '%s\n' "$commit" >"$temporario"; then
        rm -f -- "$temporario"
        return 1
    fi
    if ! mv -f -- "$temporario" "$arquivo"; then
        rm -f -- "$temporario"
        return 1
    fi
    if [ "$IMAGEM_POR_ID" = 1 ]; then
        temporario=$(mktemp "$ESTADO_DIR/.${DIR}.images.XXXXXX") || return 1
        chmod 600 "$temporario" || return 1
        printf 'app=%s\npostgres=%s\n' "$APP_IMAGE" "$POSTGRES_IMAGE" >"$temporario" || return 1
        mv -f -- "$temporario" "$ESTADO_DIR/$DIR.images" || return 1
    fi
}

# Guarda as imagens exatas que estão servindo antes de reconstruir. As tags de
# base são móveis; reconstruir o código antigo durante um rollback poderia
# baixar a mesma base que causou a falha. O rollback retagueia os IDs antigos e
# sobe sem build, preservando a imagem que já estava saudável.
IMAGENS_ANTERIORES=
ROLLBACK_OVERRIDE=
IMAGEM_POR_ID=0
trap 'rm -f -- "${IMAGENS_ANTERIORES:-}" "${ROLLBACK_OVERRIDE:-}"' EXIT
capturar_imagens_anteriores() {
    local containers container imagem servico id
    local -A servicos_anteriores=()
    containers=$(compose ps -q) || {
        echo "Não foi possível listar os contêineres atuais para rollback." >&2
        return 1
    }
    if [ -z "$containers" ]; then
        echo "Nenhum contêiner atual para preservar antes do deploy." >&2
        return 1
    fi
    install -d -m 700 "$ESTADO_DIR" || return 1
    IMAGENS_ANTERIORES=$(mktemp "$ESTADO_DIR/.${DIR}.imagens.XXXXXX") || return 1
    chmod 600 "$IMAGENS_ANTERIORES" || return 1
    if [ "$IMAGEM_POR_ID" = 1 ]; then
        ROLLBACK_OVERRIDE=$(mktemp "$ESTADO_DIR/.${DIR}.rollback.XXXXXX") || return 1
        chmod 600 "$ROLLBACK_OVERRIDE" || return 1
        printf 'services:\n' >"$ROLLBACK_OVERRIDE" || return 1
    fi
    while IFS= read -r container; do
        [ -n "$container" ] || continue
        if ! imagem=$(docker inspect --format '{{.Image}} {{.Config.Image}}' "$container") ||
           ! [[ "$imagem" =~ ^sha256:[a-f0-9]{64}[[:space:]]+[^[:space:]]+$ ]]; then
            echo "Não foi possível registrar a imagem atual do contêiner $container." >&2
            return 1
        fi
        servico=
        if [ "$IMAGEM_POR_ID" = 1 ]; then
            servico=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.service"}}' "$container") || return 1
            [[ "$servico" =~ ^[a-z][a-z0-9_-]*$ ]] || return 1
        fi
        # Contêineres legados podem apontar para um ID já indisponível no
        # image store. Descobrir isso só durante rollback deixa o site fora.
        id=${imagem%% *}
        if [ "$(docker image inspect --format '{{.Id}}' "$id" 2>/dev/null)" != "$id" ]; then
            if ! id=$(id_pelo_manifesto "$container" "${imagem#* }"); then
                echo "Imagem anterior indisponível para rollback: ${imagem%% *} ($container)." >&2
                return 1
            fi
            imagem="$id ${imagem#* }"
        fi
        printf '%s\n' "$imagem" >>"$IMAGENS_ANTERIORES" || return 1
        guardar_imagem "${imagem%% *}" || return 1
        if [ "$IMAGEM_POR_ID" = 1 ]; then
            id=${imagem%% *}
            servicos_anteriores[$servico]=$id
            printf '  %s:\n    image: %s\n    pull_policy: never\n' "$servico" "$id" >>"$ROLLBACK_OVERRIDE" || return 1
            case "$servico" in
                db|postgres)
                    POSTGRES_IMAGE_ANTERIOR=$id
                    # O checkout anterior pode preceder a adoção do rótulo.
                    # O ID restaurado não tem o prefixo legado da imagem.
                    printf '    labels:\n      mspa.backup.postgres: "true"\n' >>"$ROLLBACK_OVERRIDE" || return 1
                    printf '  db-provision:\n    image: %s\n    pull_policy: never\n' "$id" >>"$ROLLBACK_OVERRIDE" || return 1 ;;
            esac
        fi
    done <<<"$containers"
    if [ "$IMAGEM_POR_ID" = 1 ]; then
        for servico in "${APP_SERVICES[@]}"; do
            if [ -z "${servicos_anteriores[$servico]:-}" ]; then
                echo "Snapshot de rollback exige $servico em execução." >&2
                return 1
            fi
        done
        APP_IMAGE_ANTERIOR=${servicos_anteriores[${APP_SERVICES[0]}]}
        # ICT e coletor podem ter IDs anteriores diferentes; os dois ficam
        # fixados acima. Schema/migrate usa o primário sem chave YAML repetida.
        if [ -z "${servicos_anteriores[$MIGRATION_SERVICE]:-}" ]; then
            printf '  %s:\n    image: %s\n    pull_policy: never\n' "$MIGRATION_SERVICE" "$APP_IMAGE_ANTERIOR" >>"$ROLLBACK_OVERRIDE" || return 1
        fi
    fi
    if [ "$IMAGEM_POR_ID" = 1 ] &&
       { [ -z "${APP_IMAGE_ANTERIOR:-}" ] || [ -z "${POSTGRES_IMAGE_ANTERIOR:-}" ]; }; then
        echo "Snapshot de rollback exige aplicação e PostgreSQL em execução." >&2
        return 1
    fi
    [ -s "$IMAGENS_ANTERIORES" ]
}

# No image store do containerd, um contêiner subido por tag (o Wealthfolio)
# guarda em `.Image` o digest da configuração, que `docker image inspect` não
# resolve; o que resolve é o ID do índice da imagem. Foi isso que deixou o
# Wealthfolio sem deploy desde 18/10/2026: a imagem estava lá, mas a guarda a
# dava por perdida. A tag do contêiner só vale como ponto de retorno se o
# manifesto dela, na plataforma do contêiner, for exatamente o que ele roda.
id_pelo_manifesto() {
    local container=$1 referencia=$2 descritor manifesto plataforma id
    descritor=$(docker inspect --format '{{.ImageManifestDescriptor.Digest}} {{.ImageManifestDescriptor.Platform.OS}}/{{.ImageManifestDescriptor.Platform.Architecture}}' "$container" 2>/dev/null) || return 1
    read -r manifesto plataforma <<<"$descritor"
    [[ "$manifesto" =~ ^sha256:[a-f0-9]{64}$ && "$plataforma" =~ ^[a-z0-9]+/[a-z0-9]+$ ]] || return 1
    [ "$(docker image inspect --platform "$plataforma" --format '{{.Descriptor.Digest}}' "$referencia" 2>/dev/null)" = "$manifesto" ] || return 1
    id=$(docker image inspect --format '{{.Id}}' "$referencia" 2>/dev/null) || return 1
    [[ "$id" =~ ^sha256:[a-f0-9]{64}$ ]] || return 1
    printf '%s\n' "$id"
}

retaggear_imagens_anteriores() {
    local id referencia
    [ -s "$IMAGENS_ANTERIORES" ] || {
        echo "O registro das imagens anteriores está ausente." >&2
        return 1
    }
    while read -r id referencia; do
        [ -n "$id" ] && [ -n "$referencia" ] || return 1
        if [[ "$referencia" != *@sha256:* && "$referencia" != sha256:* ]]; then
            docker image tag "$id" "$referencia" || return 1
        fi
    done <"$IMAGENS_ANTERIORES"
}

# Único caminho para toda falha posterior a um fast-forward bem-sucedido.
# Cada comando potencialmente falho está dentro de um `if`: `set -e` nunca
# consegue encerrar o processo antes de tentarmos restaurar a versão anterior.
rollback_deploy() {
    local motivo="$1" quebrado="$2" detalhe_rollback estado_nota=

    echo >&2
    echo "FALHOU após atualizar para ${quebrado:0:7}: $motivo" >&2
    echo "-- revertendo código/imagem para ${atual:0:7} --" >&2
    echo "AVISO: migrações de banco não são revertidas automaticamente." >&2
    if [ "$IMAGEM_POR_ID" = 1 ]; then
        DEPLOY_OVERRIDE=$ROLLBACK_OVERRIDE
        APP_IMAGE=${APP_IMAGE_ANTERIOR:-}
        POSTGRES_IMAGE=${POSTGRES_IMAGE_ANTERIOR:-}
    fi

    if ! git reset --hard "$atual"; then
        detalhe_rollback="git reset --hard não conseguiu restaurar ${atual:0:7}"
    elif ! retaggear_imagens_anteriores; then
        detalhe_rollback="não foi possível restaurar as imagens que estavam saudáveis"
    elif ! compose up -d --no-build --pull never; then
        detalhe_rollback="Compose não conseguiu subir as imagens anteriores de ${atual:0:7}"
    elif ! esperar_compose; then
        detalhe_rollback="a espera do Compose falhou ao restaurar ${atual:0:7}"
    elif verificar_saude "$TENTATIVAS_SAUDE"; then
        if ! registrar_implantacao_saudavel; then
            printf -v estado_nota \
                '\n\nATENÇÃO: o site respondeu saudável, mas não foi possível atualizar o arquivo de estado em %s.' \
                "$ESTADO_DIR"
        fi
        echo "REVERTIDO: $DIR voltou para $(git rev-parse --short HEAD) e responde." >&2
        alertar "DEPLOY REVERTIDO: $DIR" \
"A implantação de ${quebrado:0:7} falhou e foi desfeita.

Motivo original: $motivo

O site está de pé de novo em ${atual:0:7} — o estado anterior.
$estado_nota

O commit ruim CONTINUA no main do GitHub. O próximo deploy deste projeto
vai tentar aplicá-lo outra vez. Conferir antes:

  cd /home/ubuntu/apps/$DIR && git log --oneline ${atual:0:7}..origin/main"
        rm -f -- "$IMAGENS_ANTERIORES" "${ROLLBACK_OVERRIDE:-}"
        return 1
    else
        detalhe_rollback="/health não confirmou saúde após restaurar ${atual:0:7} (HTTP $VERIF_CODE)"
    fi

    echo "GRAVE: reversão falhou: $detalhe_rollback." >&2
    alertar "DEPLOY QUEBRADO E REVERSÃO FALHOU: $DIR" \
"A implantação de ${quebrado:0:7} falhou e a reversão para ${atual:0:7} também falhou.

Falha original: $motivo
Falha da reversão: $detalhe_rollback

HTTP na última sonda: $VERIF_CODE
Resposta:
$(printf '%s' "$VERIF_CORPO" | head -c 300)

O rollback só reverte código/imagem; não reverte migrações de banco.

Diagnóstico inicial:
  cd /home/ubuntu/apps/$DIR
  docker compose --env-file $ENVF ${COMPOSE_FILES[*]} ps
  docker compose --env-file $ENVF ${COMPOSE_FILES[*]} logs --tail 50
  df -h /"
    rm -f -- "$IMAGENS_ANTERIORES" "${ROLLBACK_OVERRIDE:-}"
    return 1
}

status_geral() {
    printf '%-26s %-10s %-10s %-8s %-6s %s\n' PROJETO VPS GITHUB LIMPO HTTP SAUDE
    for p in bancario conforto megasena renda wealthfolio; do
        projeto_info "$p"
        # Um projeto ainda não clonado no servidor não deve derrubar o --status
        # dos demais.
        [ -d "$APPS/$DIR/.git" ] || { printf '%-26s %s\n' "$DIR" '(não clonado)'; continue; }
        cd "$APPS/$DIR"
        local loc rem limpo saude
        loc=$(git rev-parse --short HEAD)
        rem=$(git ls-remote origin refs/heads/main 2>/dev/null | cut -c1-7)
        [ -z "$(git status --porcelain)" ] && limpo=sim || limpo=NAO
        if verificar_saude 1; then saude=ok; else saude=FORA; fi
        printf '%-26s %-10s %-10s %-8s %-6s %s\n' \
            "$DIR" "$loc" "${rem:-?}" "$limpo" "$VERIF_CODE" "$saude"
    done
}

if [ "${1:-}" = "--status" ]; then status_geral; exit 0; fi
if [ $# -lt 1 ]; then
    echo "uso: $0 <bancario|conforto|megasena|renda|wealthfolio> [--refresh]" >&2
    echo "     $0 --status" >&2
    exit 1
fi

projeto_info "$1"
REFRESH=0
for opcao in "${@:2}"; do
    case "$opcao" in
        --refresh) REFRESH=1 ;;
        *) echo "Opção desconhecida: $opcao (use --refresh)" >&2; exit 1 ;;
    esac
done

# O mesmo lock é tomado pelo backup quando ele copia o volume rotulado. Sem
# isto, `docker pause` poderia congelar o contêiner entre o `compose up` e a
# sonda do deploy, ou o deploy poderia recriá-lo no meio do snapshot SQLite.
if travar_app "$DIR"; then
    :
else
    exit $?
fi
cd "$APPS/$DIR"

echo "== $DIR =="

sujo=$(git status --porcelain)
if [ -n "$sujo" ]; then
    echo "ABORTADO: há alteração não commitada no servidor." >&2
    # shellcheck disable=SC2001  # `${var//}` não sabe prefixar linha a linha:
    # ele veria a saída inteira como uma string só. O que se quer aqui é indentar
    # cada linha do `git status`, e é para isso que o `sed` existe.
    echo "$sujo" | sed 's/^/  /' >&2
    echo >&2
    echo "O servidor espelha o main; ele não é lugar de editar código." >&2
    echo "Leve a mudança para a sua máquina, commite, envie ao GitHub e rode de novo." >&2
    exit 1
fi

if ! git fetch --quiet origin main; then
    echo "ABORTADO: não foi possível buscar origin/main; o HEAD local não foi alterado." >&2
    exit 1
fi
if ! atual=$(git rev-parse HEAD) || ! novo=$(git rev-parse origin/main); then
    echo "ABORTADO: não foi possível resolver os commits local e remoto; o deploy não começou." >&2
    exit 1
fi

# `--refresh` remonta o que já está no ar com bases novas e NUNCA aplica commit
# novo: código que o usuário ainda não mandou implantar não entra por aqui.
if [ "$REFRESH" = 1 ]; then
    if [ "$atual" != "$novo" ]; then
        echo "O main tem commits ainda não implantados; --refresh não os aplica:"
        git log --oneline "$atual..$novo" | sed 's/^/  /'
    fi
    novo=$atual
    echo "Remontando ${atual:0:7} com imagens-base novas."
elif [ "$atual" = "$novo" ]; then
    echo "Já está na versão do main ($(git rev-parse --short HEAD)). Nada a fazer."
    exit 0
else
    echo "Mudanças a aplicar:"
    git log --oneline "$atual..$novo" | sed 's/^/  /'
    echo "Arquivos:"
    git diff --stat "$atual..$novo" | tail -20 | sed 's/^/  /'
fi

# O gate é o arquivo do commit candidato, não o checkout antigo: os apps com
# `compose.release.yaml` sobem por ID fixo; os demais, pelo `up --build`.
if git cat-file -e "$novo:compose.release.yaml" 2>/dev/null; then
    IMAGEM_POR_ID=1
fi

# A partir daqui produção é tocada. `atual` é a rede: o commit que estava no ar
# e comprovadamente respondia.
echo
echo "-- atualizando código (voltando para ${atual:0:7} se der errado) --"
if ! capturar_imagens_anteriores; then
    echo "ABORTADO: não foi possível preservar as imagens atuais; nada foi alterado." >&2
    exit 1
fi
if [ "$atual" != "$novo" ] && ! git merge --ff-only origin/main; then
    rm -f -- "$IMAGENS_ANTERIORES"
    echo "ABORTADO: origin/main não pôde ser aplicado por fast-forward." >&2
    echo "O deploy não começou e o HEAD permanece em ${atual:0:7}; não há rollback a fazer." >&2
    exit 1
fi
quebrado=$novo

# Montar não troca contêiner nenhum: se falhar, basta devolver o código.
echo "-- montando as imagens no servidor --"
montou=1
if [ "$IMAGEM_POR_ID" = 1 ]; then
    montar_imagens || montou=0
elif [ "$REFRESH" = 1 ]; then
    compose build --pull --no-cache || montou=0
fi
if [ "$montou" != 1 ]; then
    echo "ABORTADO: a montagem das imagens falhou; nenhum contêiner foi trocado." >&2
    if ! git reset --hard "$atual" || ! retaggear_imagens_anteriores; then
        echo "GRAVE: não foi possível devolver o checkout e as tags para ${atual:0:7}." >&2
        alertar "DEPLOY: MONTAGEM FALHOU E O CHECKOUT NÃO VOLTOU: $DIR" \
"A montagem de ${novo:0:7} falhou antes de trocar contêineres, mas o checkout
ou as tags não voltaram para ${atual:0:7}. Os contêineres continuam no ar.

  cd /home/ubuntu/apps/$DIR && git status && git log --oneline -1"
    fi
    rm -f -- "$IMAGENS_ANTERIORES"
    exit 1
fi

echo "-- subindo a versão nova --"
if [ "$IMAGEM_POR_ID" = 1 ]; then
    DEPLOY_OVERRIDE=compose.release.yaml
    SUBIDA=(up -d --no-build --pull never)
else
    SUBIDA=(up -d --build)
fi
if ! compose "${SUBIDA[@]}"; then
    rollback_deploy "compose ${SUBIDA[*]} falhou" "$quebrado"
    exit 1
fi

echo "-- aguardando saúde --"
if ! esperar_compose; then
    rollback_deploy "a espera do Compose falhou ou excedeu 200 segundos" "$quebrado"
    exit 1
fi

echo "-- verificando o endereço público --"
if verificar_saude "$TENTATIVAS_SAUDE"; then
    echo "  https://$DOMINIO/health -> HTTP $VERIF_CODE  $VERIF_CORPO"
    echo "OK: $DIR em $(git rev-parse --short HEAD)"

    if ! registrar_implantacao_saudavel; then
        echo "FALHOU: deploy saudável, mas o commit não pôde ser registrado em $ESTADO_DIR." >&2
        alertar "DEPLOY SEM REGISTRO DE ESTADO: $DIR" \
"O deploy de ${quebrado:0:7} está saudável, mas não foi possível registrar o
commit confirmado em $ESTADO_DIR. O código não foi revertido."
        exit 1
    fi
    podar_guardas || true
    rm -f -- "$IMAGENS_ANTERIORES"

    # Poda o cache por tamanho, pois deploys frequentes podem manter todas as
    # camadas jovens mesmo quando o consumo de disco cresce. O teto preserva
    # as camadas recentes dos seis projetos e a poda nunca falha o deploy.
    docker builder prune -f --max-used-space 3GB >/dev/null 2>&1 || true
    exit 0
fi
rollback_deploy \
    "/health não confirmou \"status\":\"ok\" (HTTP $VERIF_CODE; corpo: $(printf '%s' "$VERIF_CORPO" | head -c 300))" \
    "$quebrado"
exit 1
