#!/usr/bin/env bash
# Implanta um projeto no VPS a partir do main do GitHub.
#
#   ./deploy.sh <projeto>          implanta
#   ./deploy.sh <projeto> --check  só mostra o que mudaria
#   ./deploy.sh --status           estado dos quatro projetos
#
# Recusa implantar se houver alteração não commitada no servidor: o código do
# servidor é sempre um espelho do main, nunca a origem de uma mudança. Isso
# deixou de ser só higiene e virou pré-requisito de segurança — o rollback
# abaixo faz `git reset --hard`, que descartaria em silêncio qualquer edição
# feita no servidor.
#
# POR QUE A SONDA É `/health` E NÃO `/login`: a tela de login responde 200 com
# o banco inteiramente fora do ar. Um deploy que quebra a conexão com o banco
# passava na verificação e era declarado bem-sucedido. Os quatro projetos
# expõem `/health`, que consulta o banco de verdade e responde 503 quando não
# consegue — e o critério aqui é o CORPO conter `"status":"ok"`, não o código
# HTTP, justamente para não repetir o erro de aceitar um 200 vazio de sentido.
#
# POR QUE ROLLBACK AUTOMÁTICO: sem ele, um deploy que quebra o site avisa e
# deixa quebrado; o conserto é para frente, sob pressão, com o site fora. O
# estado anterior é conhecido (o commit de onde saímos) e comprovadamente
# funcionava, então voltar é a ação de menor risco disponível.

set -euo pipefail

APPS=/home/ubuntu/apps
ALERTA=/home/ubuntu/alerta.sh

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
    for _ in $(seq 1 40); do
        sleep 5
        if ! compose ps --format '{{.Status}}' 2>/dev/null | grep -qi 'starting'; then
            break
        fi
    done
    compose ps --format '  {{.Name}}  {{.Status}}'
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

git fetch --quiet origin main
atual=$(git rev-parse HEAD)
novo=$(git rev-parse origin/main)

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
git merge --ff-only origin/main

echo "-- reconstruindo e subindo --"
compose up -d --build

echo "-- aguardando saúde --"
esperar_compose

echo "-- verificando o endereço público --"
if verificar_saude "$TENTATIVAS_SAUDE"; then
    echo "  https://$DOMINIO/health -> HTTP $VERIF_CODE  $VERIF_CORPO"
    echo "OK: $DIR em $(git rev-parse --short HEAD)"

    # Poda do cache de build. O deploy constrói no servidor, então o cache
    # cresce a cada implantação e nunca encolhe sozinho — 5,8 GB acumulados em
    # 262 entradas quando isto foi escrito.
    #
    # O teto é de TAMANHO e não de idade. A primeira versão disto filtrava por
    # `until=168h` e não podava absolutamente nada: com deploys frequentes,
    # nenhuma entrada chega a ter uma semana. Idade mede há quanto tempo a
    # camada foi criada; o que interessa é quanto disco ela ocupa. Medido, não
    # suposto — o cache subiu de 5,8 para 6,8 GB com a poda por idade ligada.
    #
    # 3 GB cabe a camada recente dos quatro projetos (o que mantém o deploy
    # seguinte rápido) e descarta o resto. Nunca falha o deploy.
    docker builder prune -f --max-used-space 3GB >/dev/null 2>&1 || true
    exit 0
fi

# --------------------------------------------------------------------------
# Rollback
#
# Só se chega aqui com a verificação reprovada depois de TENTATIVAS_SAUDE.
# O rollback NÃO tem rollback: se voltar e ainda assim reprovar, o script para
# e grita. Tentar consertar em cascata a partir daqui seria mexer às cegas num
# sistema já fora do ar.
# --------------------------------------------------------------------------
quebrado=$(git rev-parse --short HEAD)
echo >&2
echo "FALHOU: https://$DOMINIO/health não confirmou \"status\":\"ok\"." >&2
echo "  HTTP $VERIF_CODE" >&2
printf '%s\n' "$VERIF_CORPO" | head -c 400 | sed 's/^/  /' >&2 || true
echo >&2
echo "-- revertendo para ${atual:0:7} --" >&2

git reset --hard "$atual"
compose up -d --build
esperar_compose

if verificar_saude "$TENTATIVAS_SAUDE"; then
    echo "REVERTIDO: $DIR voltou para $(git rev-parse --short HEAD) e responde." >&2
    alertar "DEPLOY REVERTIDO: $DIR" \
"A implantação de $quebrado quebrou o /health e foi desfeita.

O site está de pé de novo em ${atual:0:7} — o estado anterior.

HTTP observado na versão ruim: $VERIF_CODE

O commit ruim CONTINUA no main do GitHub. O próximo deploy deste projeto
vai tentar aplicá-lo outra vez. Conferir antes:

  cd /home/ubuntu/apps/$DIR && git log --oneline ${atual:0:7}..origin/main"
    exit 1
fi

echo "GRAVE: a reversão para ${atual:0:7} também não respondeu." >&2
alertar "DEPLOY QUEBRADO E REVERSÃO FALHOU: $DIR" \
"A implantação de $quebrado reprovou no /health, a reversão para ${atual:0:7}
foi feita e TAMBÉM reprovou.

HTTP na última tentativa: $VERIF_CODE

Resposta:
$(printf '%s' "$VERIF_CORPO" | head -c 300)

Isto não é o deploy: código que funcionava antes não está funcionando agora.
Suspeitar de banco, disco, rede ou nginx, nesta ordem:

  cd /home/ubuntu/apps/$DIR
  docker compose --env-file $ENVF -f compose.yaml ps
  docker compose --env-file $ENVF -f compose.yaml logs --tail 50
  df -h /"
exit 1
