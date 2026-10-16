#!/usr/bin/env bash
# Implanta um projeto no VPS a partir do main do GitHub.
#
#   ./deploy.sh <projeto>           implanta
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
# o commit só é aplicado se todos os check-runs de produto/segurança terminaram
# verdes no GitHub e os checks de teste daquele app estão presentes. No
# Wealthfolio, a CI do app pertence ao commit candidato, mas a suíte lenta da
# imagem só roda quando mudam Dockerfile/patches; nesse caso, conferimos o
# último commit que alterou essas entradas, que pode ser ancestral do candidato.
# Os checks auxiliares não testam o artefato e não substituem a CI. Ver
# `validar_ci_deploy`.
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
# correspondência já precisou ser consultada mais de uma vez. O portal pulou
# para 56xx: o 55xx era do site estático, que ele substituiu, e reaproveitar a
# faixa enquanto os dois coexistiam na virada teria colidido as portas. O
# NetWorth, consolidador que lê o bancário e o renda, entrou em 17/09/2026 no 57xx
# e foi aposentado em 29/09/2026: o Wealthfolio (18088) opera no domínio dele.
#
# `REPO_GITHUB` é onde a CI do commit é conferida. Todos os repositórios de
# aplicativos deste deploy são públicos; a API anônima basta e nenhum token do
# GitHub precisa ficar no VPS.
projeto_info() {
    CI_EXIGIDA=1
    CI_MOTIVO=
    CI_TESTE_1=
    CI_TESTE_2=
    CI_IMAGEM_TESTE_1=
    case "$1" in
        bancario|controle-bancario)
            DIR=controle-bancario;      ENVF=.env.vps;    PORTA=5201
            DOMINIO=bancario-mspa.duckdns.org
            REPO_GITHUB=MSPA-Coder/sistema-financeiro
            CI_TESTE_1=Qualidade ;;
        conforto|conforto-termico)
            DIR=conforto-termico;       ENVF=.env.vps;    PORTA=5401
            DOMINIO=conforto-mspa.duckdns.org
            REPO_GITHUB=MSPA-Coder/Sistema-de-Controle-de-Indice-de-Conforto-Termico
            CI_TESTE_1=Qualidade
            CI_TESTE_2='Runtime contracts' ;;
        megasena|mega-sena)
            DIR=mega-sena;              ENVF=.env.vps;    PORTA=5101
            DOMINIO=megasena-mspa.duckdns.org
            REPO_GITHUB=MSPA-Coder/mega-sena
            CI_TESTE_1=Qualidade ;;
        renda|controle-renda-variavel)
            DIR=controle-renda-variavel; ENVF=.env.vps;   PORTA=5301
            DOMINIO=renda-mspa.duckdns.org
            REPO_GITHUB=MSPA-Coder/ControleRendaVariavel
            CI_TESTE_1=Qualidade
            CI_TESTE_2='Contratos de runtime' ;;
        portal|mp-portal)
            DIR=mp-portal;              ENVF=.env.vps;    PORTA=5601
            DOMINIO=mp-solucoes.duckdns.org
            REPO_GITHUB=MSPA-Coder/mp-portal
            CI_EXIGIDA=0; CI_MOTIVO="repositório privado; a API anônima não o alcança" ;;
        wealthfolio)
            DIR=wealthfolio-teste;      ENVF=.env;        PORTA=18088
            DOMINIO=wealthfolio-mspa.duckdns.org
            REPO_GITHUB=MSPA-Coder/WealthfolioTeste
            CI_EXIGIDA=1
            CI_TESTE_1='Patches, add-on e Compose'
            CI_IMAGEM_TESTE_1='Build, testes dos patches e partida'
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
        if grep -Eq "$PADRAO_SAUDE" <<<"$VERIF_CORPO"; then
            return 0
        fi
    done
    return 1
}

# CI DO COMMIT. Antes de tocar na produção, pergunta ao GitHub se todos os
# check-runs de produto/segurança terminaram bem e se os testes do app estão
# presentes. Os checks exatos são definidos em `projeto_info`. Para conferir
# o workflow composto da imagem num SHA ancestral, `somente_nome` limita a
# análise àquele check-run; a CI completa do candidato já foi conferida antes.
#
# Checks de dependabot (`Dependabot`, `update-uv-graph`, `update-pip-graph`) e
# do auto-merge são automações auxiliares, não validam o app e às vezes falham
# por limitações do próprio atualizador. Todos os demais continuam bloqueando
# se falharem ou não terminarem. `neutral` e `skipped` contam como verdes. A
# API devolve a tentativa mais recente de cada job (`filter=latest`, o padrão).
#
# O parser pequeno em awk preserva o vínculo entre nome, status e conclusão de
# cada objeto JSON. As contagens também são comparadas com `total_count`; JSON
# incompleto, sem os testes esperados ou desconhecido nunca publica. Não usa jq
# nem Python, para a suíte seguir executável na imagem mínima `bash:5.2`.
#
# A API anônima basta porque os repositórios conferidos são públicos, e o
# limite dela (60 pedidos por hora por IP) sobra para deploy feito à mão.
CI_RESUMO=
conferir_ci() {
    local sha=$1 somente_nome=${2:-} resposta codigo corpo total estados conclusoes
    local n_estados n_conclusoes analise parse_ok n_runs n_ci pendentes
    local encontrou_1 encontrou_2 reprovados
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

    analise=$(printf '%s\n' "$corpo" | awk -v esperado1="$CI_TESTE_1" -v esperado2="$CI_TESTE_2" -v somente="$somente_nome" '
        function campo(objeto, chave, padrao, valor) {
            padrao = "\"" chave "\"[[:space:]]*:[[:space:]]*\"[^\"]*\""
            if (!match(objeto, padrao)) return ""
            valor = substr(objeto, RSTART, RLENGTH)
            sub(/^[^:]*:[[:space:]]*\"/, "", valor)
            sub(/\"$/, "", valor)
            return valor
        }
        function processar(objeto, nome, estado, conclusao, padrao) {
            nome = campo(objeto, "name")
            estado = campo(objeto, "status")
            conclusao = campo(objeto, "conclusion")
            if (conclusao == "") {
                padrao = "\"conclusion\"[[:space:]]*:[[:space:]]*null"
                if (match(objeto, padrao)) conclusao = "null"
            }
            if (nome == "" || estado == "" || conclusao == "") {
                malformados++
                return
            }
            if (somente != "" && nome != somente) return
            if (nome == "Dependabot" || nome == "update-uv-graph" ||
                nome == "update-pip-graph" || nome == "Auto merge") return

            ativos++
            if (nome == esperado1) achou1 = 1
            if (esperado2 != "" && nome == esperado2) achou2 = 1
            if (estado != "completed") pendentes++
            else if (conclusao != "success" && conclusao != "neutral" && conclusao != "skipped")
                falhas[++n_falhas] = conclusao
        }
        { json = json $0 "\n" }
        END {
            inicio = index(json, "\"check_runs\"")
            if (!inicio) { print "ERRO"; exit }
            posicao = inicio + index(substr(json, inicio), "[")
            if (posicao <= inicio) { print "ERRO"; exit }

            dentro = 0
            em_string = 0
            escape = 0
            for (i = posicao; i <= length(json); i++) {
                caractere = substr(json, i, 1)
                if (em_string) {
                    if (dentro) objeto = objeto caractere
                    if (escape) escape = 0
                    else if (caractere == "\\") escape = 1
                    else if (caractere == "\"") em_string = 0
                    continue
                }
                if (caractere == "\"") {
                    em_string = 1
                    if (dentro) objeto = objeto caractere
                } else if (caractere == "{") {
                    if (dentro == 0) objeto = ""
                    dentro++
                    objeto = objeto caractere
                } else if (caractere == "}") {
                    objeto = objeto caractere
                    dentro--
                    if (dentro == 0) {
                        n_runs++
                        processar(objeto)
                    }
                } else if (dentro > 0) objeto = objeto caractere
                else if (caractere == "]") break
            }

            if (malformados > 0) { print "ERRO"; exit }
            printf "OK\t%d\t%d\t%d\t%d\t%d\n", n_runs, ativos, pendentes, achou1, achou2
            for (i = 1; i <= n_falhas; i++) print falhas[i]
        }
    ')
    parse_ok=$(printf '%s\n' "$analise" | sed -n '1p')
    if [[ "$parse_ok" != OK$'\t'* ]]; then
        CI_RESUMO="não foi possível interpretar os check-runs da API"
        return 1
    fi
    IFS=$'\t' read -r parse_ok n_runs n_ci pendentes encontrou_1 encontrou_2 \
        <<<"$(printf '%s\n' "$analise" | sed -n '1p')"
    if [ "$n_runs" -ne "$total" ]; then
        CI_RESUMO="resposta da API fora do esperado ($total check-runs, $n_runs objetos)"
        return 1
    fi
    if [ "$n_ci" -eq 0 ]; then
        CI_RESUMO="nenhum check-run de CI/teste para validar (só automações auxiliares)"
        return 1
    fi
    if [ "$encontrou_1" -ne 1 ] || { [ -n "$CI_TESTE_2" ] && [ "$encontrou_2" -ne 1 ]; }; then
        CI_RESUMO="check-run obrigatório ausente: ${CI_TESTE_1}${CI_TESTE_2:+ e $CI_TESTE_2}"
        return 1
    fi
    if [ "$pendentes" -gt 0 ]; then
        CI_RESUMO="$pendentes de $n_ci check-runs de CI/teste ainda não terminaram"
        return 1
    fi
    reprovados=$(printf '%s\n' "$analise" | sed '1d' | grep -Ev '^(success|neutral|skipped)$' \
                 | sort | uniq -c | awk '{printf "%s%s %s", sep, $1, $2; sep=", "}' || true)
    if [ -n "$reprovados" ]; then
        CI_RESUMO="check-runs de CI/teste reprovados: $reprovados"
        return 1
    fi
    if [ "$n_ci" -eq 1 ]; then
        CI_RESUMO="1 check-run verde"
    else
        CI_RESUMO="$n_ci check-runs verdes"
    fi
    return 0
}

# O workflow de imagem do Wealthfolio tem filtro de caminhos: commits do
# add-on executam e exigem a CI do app, enquanto Dockerfile/patches também
# exigem a suíte lenta da imagem. Quando os dois tipos de commit chegam juntos
# antes do deploy diário, a imagem foi testada no commit ancestral que mudou
# essas entradas, não necessariamente no SHA mais novo. A busca é pelo último
# commit da árvore que altera qualquer entrada coberta pelo workflow; a API
# ainda precisa confirmar verde o check-run composto que inclui testes, partida
# e análise Trivy.
validar_ci_deploy() {
    local sha=$1 resumo_app resumo_imagem imagem_sha
    local teste_1_app=$CI_TESTE_1 teste_2_app=$CI_TESTE_2

    if ! conferir_ci "$sha"; then
        return 1
    fi
    resumo_app=$CI_RESUMO

    if [ -z "$CI_IMAGEM_TESTE_1" ]; then
        CI_RESUMO=$resumo_app
        return 0
    fi

    if ! imagem_sha=$(git log -1 --format=%H "$sha" -- \
            Dockerfile .dockerignore patches .github/workflows/imagem.yml) ||
       ! [[ "$imagem_sha" =~ ^[0-9a-f]{40}$ ]]; then
        CI_RESUMO="não foi possível localizar o último commit que alterou as entradas da imagem"
        return 1
    fi
    CI_TESTE_1=$CI_IMAGEM_TESTE_1
    CI_TESTE_2=
    if conferir_ci "$imagem_sha" "$CI_IMAGEM_TESTE_1"; then
        resumo_imagem=$CI_RESUMO
        CI_TESTE_1=$teste_1_app
        CI_TESTE_2=$teste_2_app
        CI_RESUMO="app ${sha:0:7}: $resumo_app; imagem ${imagem_sha:0:7}: $resumo_imagem"
        return 0
    fi

    resumo_imagem=$CI_RESUMO
    CI_TESTE_1=$teste_1_app
    CI_TESTE_2=$teste_2_app
    CI_RESUMO="CI do app verde ($resumo_app), mas a imagem em ${imagem_sha:0:7} não está verde ($resumo_imagem)"
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
}

# Guarda as imagens exatas que estão servindo antes de reconstruir. As tags de
# base são móveis; reconstruir o código antigo durante um rollback poderia
# baixar a mesma base que causou a falha. O rollback retagueia os IDs antigos e
# sobe sem build, preservando a imagem que já estava saudável.
IMAGENS_ANTERIORES=
capturar_imagens_anteriores() {
    local containers container imagem
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
    while IFS= read -r container; do
        [ -n "$container" ] || continue
        if ! imagem=$(docker inspect --format '{{.Image}} {{.Config.Image}}' "$container") ||
           ! [[ "$imagem" =~ ^sha256:[a-f0-9]{64}[[:space:]]+[^[:space:]]+$ ]]; then
            echo "Não foi possível registrar a imagem atual do contêiner $container." >&2
            return 1
        fi
        printf '%s\n' "$imagem" >>"$IMAGENS_ANTERIORES" || return 1
    done <<<"$containers"
    [ -s "$IMAGENS_ANTERIORES" ]
}

retaggear_imagens_anteriores() {
    local id referencia
    [ -s "$IMAGENS_ANTERIORES" ] || {
        echo "O registro das imagens anteriores está ausente." >&2
        return 1
    }
    while read -r id referencia; do
        [ -n "$id" ] && [ -n "$referencia" ] || return 1
        docker image tag "$id" "$referencia" || return 1
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

    if ! git reset --hard "$atual"; then
        detalhe_rollback="git reset --hard não conseguiu restaurar ${atual:0:7}"
    elif ! retaggear_imagens_anteriores; then
        detalhe_rollback="não foi possível restaurar as imagens que estavam saudáveis"
    elif ! compose up -d --no-build; then
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
        rm -f -- "$IMAGENS_ANTERIORES"
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
    rm -f -- "$IMAGENS_ANTERIORES"
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
    echo "uso: $0 <bancario|conforto|megasena|renda|portal|wealthfolio> [--sem-ci] [--refresh]" >&2
    echo "     $0 --status" >&2
    exit 1
fi

projeto_info "$1"
SEM_CI=0
REFRESH=0
for opcao in "${@:2}"; do
    case "$opcao" in
        --sem-ci) SEM_CI=1 ;;
        --refresh) REFRESH=1 ;;
        *) echo "Opção desconhecida: $opcao (use --sem-ci ou --refresh)" >&2; exit 1 ;;
    esac
done
if [ "$SEM_CI" = 1 ] && [ "$REFRESH" = 1 ]; then
    echo "Opções incompatíveis: --sem-ci e --refresh não podem ser combinadas." >&2
    exit 1
fi

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

if [ "$atual" = "$novo" ] && [ "$REFRESH" = 0 ]; then
    echo "Já está na versão do main ($(git rev-parse --short HEAD)). Nada a fazer."
    exit 0
fi

if [ "$atual" != "$novo" ]; then
    echo "Mudanças a aplicar:"
    git log --oneline "$atual..$novo" | sed 's/^/  /'
    echo "Arquivos:"
    git diff --stat "$atual..$novo" | tail -20 | sed 's/^/  /'
elif [ "$REFRESH" = 1 ]; then
    echo "SHA inalterado; reconstruindo as tags-base móveis após CI verde."
fi

echo "CI do commit ${novo:0:7}:"
if [ "$CI_EXIGIDA" = 0 ]; then
    ci_verde=1
    echo "  não conferida: $CI_MOTIVO"
elif validar_ci_deploy "$novo"; then
    ci_verde=1
    echo "  $CI_RESUMO"
else
    ci_verde=0
    echo "  NÃO VERDE: $CI_RESUMO"
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
