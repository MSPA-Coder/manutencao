#!/usr/bin/env bash
# Implanta um projeto no VPS a partir do main do GitHub.
#
#   ./deploy.sh <projeto>          implanta
#   ./deploy.sh <projeto> --check  só mostra o que mudaria
#   ./deploy.sh --status           estado dos quatro projetos
#
# Recusa implantar se houver alteração não commitada no servidor: o código do
# servidor é sempre um espelho do main, nunca a origem de uma mudança. O
# rollback usa `git reset --hard`, portanto só pode operar sobre checkout
# limpo.
#
# POR QUE A SONDA É `/health` E NÃO `/login`: a tela de login responde 200 com
# o banco inteiramente fora do ar. Os quatro projetos expõem `/health`, que
# consulta o banco e responde 503 quando não consegue. O critério é o CORPO
# conter `"status":"ok"`, não apenas o código HTTP.
#
# POR QUE ROLLBACK AUTOMÁTICO: sem ele, um deploy que quebra o site avisa e
# deixa quebrado; o conserto é para frente, sob pressão, com o site fora. O
# estado anterior é conhecido (o commit de onde saímos) e comprovadamente
# funcionava, então voltar é a ação de menor risco disponível.
#
# LIMITE DO ROLLBACK: ele volta o código e reconstrói a imagem, mas NÃO desfaz
# migração de banco. Um deploy que execute migração exige antes um backup
# verificado e uma migração retrocompatível, ou um procedimento manual de
# reversão do schema. Este script deliberadamente não tenta adivinhar como
# reverter dados.

set -euo pipefail

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
# `-L` porque os quatro não concordam sobre a barra final e o APPEND_SLASH do
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
        if printf '%s' "$VERIF_CORPO" | grep -Eq "$PADRAO_OK"; then
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
        if ! printf '%s\n' "$estados" | grep -qi 'starting'; then
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

    if ! git reset --hard "$atual"; then
        detalhe_rollback="git reset --hard não conseguiu restaurar ${atual:0:7}"
    elif ! compose up -d --build; then
        detalhe_rollback="Compose não conseguiu reconstruir/subir ${atual:0:7}"
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
  docker compose --env-file $ENVF -f compose.yaml ps
  docker compose --env-file $ENVF -f compose.yaml logs --tail 50
  df -h /"
    return 1
}

status_geral() {
    printf '%-26s %-10s %-10s %-8s %-6s %s\n' PROJETO VPS GITHUB LIMPO HTTP SAUDE
    for p in bancario conforto megasena renda; do
        projeto_info "$p"
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

if ! git fetch --quiet origin main; then
    echo "ABORTADO: não foi possível buscar origin/main; o HEAD local não foi alterado." >&2
    exit 1
fi
if ! atual=$(git rev-parse HEAD) || ! novo=$(git rev-parse origin/main); then
    echo "ABORTADO: não foi possível resolver os commits local e remoto; o deploy não começou." >&2
    exit 1
fi

if [ "$atual" = "$novo" ]; then
    echo "Já está na versão do main ($(git rev-parse --short HEAD)). Nada a fazer."
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

# A partir daqui produção é tocada. `atual` é a rede: o commit que estava no ar
# e comprovadamente respondia.
echo
echo "-- atualizando código (voltando para ${atual:0:7} se der errado) --"
if ! git merge --ff-only origin/main; then
    echo "ABORTADO: origin/main não pôde ser aplicado por fast-forward." >&2
    echo "O deploy não começou e o HEAD permanece em ${atual:0:7}; não há rollback a fazer." >&2
    exit 1
fi
quebrado=$novo

echo "-- reconstruindo e subindo --"
if ! compose up -d --build; then
    rollback_deploy "compose up -d --build falhou" "$quebrado"
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

    # Poda o cache por tamanho, pois deploys frequentes podem manter todas as
    # camadas jovens mesmo quando o consumo de disco cresce. O teto preserva
    # as camadas recentes dos quatro projetos e a poda nunca falha o deploy.
    docker builder prune -f --max-used-space 3GB >/dev/null 2>&1 || true
    exit 0
fi
rollback_deploy \
    "/health não confirmou \"status\":\"ok\" (HTTP $VERIF_CODE; corpo: $(printf '%s' "$VERIF_CORPO" | head -c 300))" \
    "$quebrado"
exit 1
