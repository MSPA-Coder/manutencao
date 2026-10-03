#!/usr/bin/env bash
# Implanta um projeto no VPS a partir do main do GitHub.
#
#   ./deploy.sh <projeto>           implanta
#   ./deploy.sh <projeto> --check   só mostra o que mudaria, CI inclusa
#   ./deploy.sh <projeto> --sem-ci  implanta mesmo sem CI verde (emergência)
#   ./deploy.sh --status            estado de todos os projetos
#
# Recusa implantar se houver alteração não commitada no servidor: o código do
# servidor é sempre um espelho do main, nunca a origem de uma mudança. O
# rollback usa `git reset --hard`, portanto só pode operar sobre checkout
# limpo.
#
# POR QUE CONFERIR A CI ANTES: o servidor espelha o `main`, e nada impedia de
# publicar um `main` vermelho -- o do NetWorth ficou assim em 28/09/2026. Agora
# o commit só é aplicado se todos os check-runs dele terminaram verdes no
# GitHub. Ver `conferir_ci`.
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
PADRAO_SAUDE=$PADRAO_OK

# shellcheck disable=SC2034  # `PORTA` não é lida por este script -- a sonda de
# saúde bate na URL pública, não em 127.0.0.1, de propósito. Ela fica aqui
# porque este `case` é o único lugar do repositório onde a numeração da frota
# (51/52/53/54/56/57) aparece ao lado do projeto correspondente, e essa
# correspondência já precisou ser consultada mais de uma vez. O portal pulou
# para 56xx: o 55xx era do site estático, que ele substituiu, e reaproveitar a
# faixa enquanto os dois coexistiam na virada teria colidido as portas. O
# NetWorth, consolidador que lê o bancário e o renda, entrou em 17/09/2026 no 57xx
# e foi aposentado em 29/09/2026: o Wealthfolio (18088) opera no domínio dele.
#
# `REPO_GITHUB` é onde a CI do commit é conferida. Os dois privados ficam com
# `CI_EXIGIDA=0` e o motivo escrito: a API anônima não alcança repositório
# privado, e o Wealthfolio nem tem CI. Para ligar num deles, o servidor precisa
# de um token de leitura e este script, de enviá-lo.
projeto_info() {
    CI_EXIGIDA=1
    CI_MOTIVO=
    case "$1" in
        bancario|controle-bancario)
            DIR=controle-bancario;      ENVF=.env.vps;    PORTA=5201
            DOMINIO=bancario-mspa.duckdns.org
            REPO_GITHUB=MSPA-Coder/sistema-financeiro ;;
        conforto|conforto-termico)
            DIR=conforto-termico;       ENVF=.env.vps;    PORTA=5401
            DOMINIO=conforto-mspa.duckdns.org
            REPO_GITHUB=MSPA-Coder/Sistema-de-Controle-de-Indice-de-Conforto-Termico ;;
        megasena|mega-sena)
            DIR=mega-sena;              ENVF=.env.vps;    PORTA=5101
            DOMINIO=megasena-mspa.duckdns.org
            REPO_GITHUB=MSPA-Coder/mega-sena ;;
        renda|controle-renda-variavel)
            DIR=controle-renda-variavel; ENVF=.env.vps;   PORTA=5301
            DOMINIO=renda-mspa.duckdns.org
            REPO_GITHUB=MSPA-Coder/ControleRendaVariavel ;;
        portal|mp-portal)
            DIR=mp-portal;              ENVF=.env.vps;    PORTA=5601
            DOMINIO=mp-solucoes.duckdns.org
            REPO_GITHUB=MSPA-Coder/mp-portal
            CI_EXIGIDA=0; CI_MOTIVO="repositório privado; a API anônima não o alcança" ;;
        wealthfolio)
            DIR=wealthfolio-teste;      ENVF=.env;        PORTA=18088
            DOMINIO=networth-mspa.duckdns.org
            REPO_GITHUB=MSPA-Coder/WealthfolioTeste
            CI_EXIGIDA=0; CI_MOTIVO="repositório privado e sem CI"
            PADRAO_SAUDE='^ok$' ;;
        *)  echo "Projeto desconhecido: $1" >&2
            echo "Use: bancario | conforto | megasena | renda | portal | wealthfolio" >&2
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
}

compose() {
    compose_files
    docker compose --env-file "$ENVF" "${COMPOSE_FILES[@]}" "$@"
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
        if printf '%s' "$VERIF_CORPO" | grep -Eq "$PADRAO_SAUDE"; then
            return 0
        fi
    done
    return 1
}

# CI DO COMMIT (02/10/2026). Antes de tocar na produção, pergunta ao GitHub se
# todos os check-runs do commit terminaram, e terminaram bem.
#
# TODOS, e não um nome: a CI dos aplicativos tem mais de um job (o CRV roda
# `Qualidade` e `Contratos de runtime`), o CodeQL roda junto, e uma lista de
# nomes aqui apodreceria a cada job novo -- a mesma lição das listas escritas
# à mão do backup. `neutral` e `skipped` contam como verdes; o resto não. A API
# devolve só a tentativa mais recente de cada job (`filter=latest`, o padrão),
# então um job refeito e aprovado substitui o que tinha falhado.
#
# SEM jq NEM python, porque a suíte também roda na imagem `bash:5.2`, que não
# tem nenhum dos dois. As chaves `"status"` e `"conclusion"` aparecem uma vez
# por check-run (texto livre que as contenha vem com as aspas escapadas e não
# casa), e as duas contagens são conferidas contra `total_count`: uma resposta
# que não bata é tratada como desconhecida, e desconhecida não publica.
#
# A API anônima basta porque os repositórios conferidos são públicos, e o
# limite dela (60 pedidos por hora por IP) sobra para deploy feito à mão.
CI_RESUMO=
conferir_ci() {
    local sha=$1 resposta codigo corpo total estados conclusoes
    local n_estados n_conclusoes pendentes reprovados
    resposta=$(curl -sS --max-time 20 -w '\n%{http_code}' \
                   -H 'Accept: application/vnd.github+json' \
                   "https://api.github.com/repos/$REPO_GITHUB/commits/$sha/check-runs?per_page=100" \
                   2>/dev/null || true)
    codigo=$(printf '%s' "$resposta" | tail -1)
    corpo=$(printf '%s' "$resposta" | sed '$d')
    if [ "$codigo" != 200 ]; then
        CI_RESUMO="a API do GitHub respondeu HTTP ${codigo:-sem resposta}"
        return 1
    fi
    total=$(printf '%s' "$corpo" \
            | grep -oE '"total_count"[[:space:]]*:[[:space:]]*[0-9]+' \
            | grep -oE '[0-9]+$' | head -n 1 || true)
    estados=$(printf '%s' "$corpo" \
              | grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z_]+"' \
              | sed -E 's/.*"([a-z_]+)"$/\1/' || true)
    conclusoes=$(printf '%s' "$corpo" \
                 | grep -oE '"conclusion"[[:space:]]*:[[:space:]]*("[a-z_]+"|null)' \
                 | sed -E 's/.*:[[:space:]]*"?([a-z_]+)"?$/\1/' || true)
    n_estados=$(printf '%s' "$estados" | grep -c . || true)
    n_conclusoes=$(printf '%s' "$conclusoes" | grep -c . || true)

    if [ -z "$total" ] || [ "$total" -eq 0 ]; then
        CI_RESUMO="nenhum check-run neste commit (a CI ainda não começou?)"
        return 1
    fi
    if [ "$total" -gt 100 ] || [ "$n_estados" -ne "$total" ] || [ "$n_conclusoes" -ne "$total" ]; then
        CI_RESUMO="resposta da API fora do esperado ($total check-runs, $n_estados estados, $n_conclusoes conclusões)"
        return 1
    fi
    pendentes=$(printf '%s\n' "$estados" | grep -cv '^completed$' || true)
    if [ "$pendentes" -gt 0 ]; then
        CI_RESUMO="$pendentes de $total check-runs ainda não terminaram"
        return 1
    fi
    reprovados=$(printf '%s\n' "$conclusoes" | grep -Ev '^(success|neutral|skipped)$' \
                 | sort | uniq -c | awk '{printf "%s%s %s", sep, $1, $2; sep=", "}' || true)
    if [ -n "$reprovados" ]; then
        CI_RESUMO="check-runs reprovados: $reprovados"
        return 1
    fi
    CI_RESUMO="$total check-runs verdes"
    return 0
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
  docker compose --env-file $ENVF ${COMPOSE_FILES[*]} ps
  docker compose --env-file $ENVF ${COMPOSE_FILES[*]} logs --tail 50
  df -h /"
    return 1
}

status_geral() {
    printf '%-26s %-10s %-10s %-8s %-6s %s\n' PROJETO VPS GITHUB LIMPO HTTP SAUDE
    for p in bancario conforto megasena renda portal wealthfolio; do
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
    echo "uso: $0 <bancario|conforto|megasena|renda|portal|wealthfolio> [--check] [--sem-ci]" >&2
    echo "     $0 --status" >&2
    exit 1
fi

projeto_info "$1"
CHECK=
SEM_CI=0
for opcao in "${@:2}"; do
    case "$opcao" in
        --check) CHECK=--check ;;
        --sem-ci) SEM_CI=1 ;;
        *) echo "Opção desconhecida: $opcao (use --check ou --sem-ci)" >&2; exit 1 ;;
    esac
done
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

if [ "$atual" = "$novo" ]; then
    echo "Já está na versão do main ($(git rev-parse --short HEAD)). Nada a fazer."
    exit 0
fi

echo "Mudanças a aplicar:"
git log --oneline "$atual..$novo" | sed 's/^/  /'
echo "Arquivos:"
git diff --stat "$atual..$novo" | tail -20 | sed 's/^/  /'

echo "CI do commit ${novo:0:7}:"
if [ "$CI_EXIGIDA" != 1 ]; then
    ci_verde=1
    echo "  não conferida: $CI_MOTIVO"
elif conferir_ci "$novo"; then
    ci_verde=1
    echo "  $CI_RESUMO"
else
    ci_verde=0
    echo "  NÃO VERDE: $CI_RESUMO"
fi

if [ "$CHECK" = "--check" ]; then
    echo
    echo "(--check: nada foi alterado)"
    exit 0
fi

# Recusar aqui não exige rollback: nada mudou no servidor ainda. A saída de
# emergência existe porque a API do GitHub pode estar fora justo quando um
# conserto precisa subir, e ela grita: alerta e aviso no terminal.
if [ "$ci_verde" != 1 ]; then
    if [ "$SEM_CI" != 1 ]; then
        echo "ABORTADO: a CI de ${novo:0:7} não está verde ($CI_RESUMO)." >&2
        echo "O deploy não começou e o HEAD permanece em ${atual:0:7}." >&2
        echo "Espere a CI terminar ou corrija o main. Em emergência: $0 $1 --sem-ci" >&2
        exit 1
    fi
    echo "AVISO: implantando ${novo:0:7} sem CI verde, por --sem-ci ($CI_RESUMO)." >&2
    alertar "DEPLOY SEM CI VERDE: $DIR" \
"O commit ${novo:0:7} foi implantado com --sem-ci.

CI no momento do deploy: $CI_RESUMO

Conferir a CI no GitHub e, se ela reprovar, corrigir o main e implantar de novo."
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
    # as camadas recentes dos seis projetos e a poda nunca falha o deploy.
    docker builder prune -f --max-used-space 3GB >/dev/null 2>&1 || true
    exit 0
fi
rollback_deploy \
    "/health não confirmou \"status\":\"ok\" (HTTP $VERIF_CODE; corpo: $(printf '%s' "$VERIF_CORPO" | head -c 300))" \
    "$quebrado"
exit 1
