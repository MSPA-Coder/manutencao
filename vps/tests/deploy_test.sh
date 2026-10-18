#!/usr/bin/env bash
# Testes herméticos de regressão do deploy. Todos os efeitos externos são
# comandos falsos no PATH; o único estado real vive sob um diretório temporário.

set -u

# shellcheck disable=SC1007  # `CDPATH=` é prefixo de ambiente para um comando,
# não assinalamento com espaço sobrando. Mesmo motivo escrito em `instalar.sh`.
TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEPLOY="$TESTS_DIR/../deploy.sh"
OLD_SHA=1111111111111111111111111111111111111111
NEW_SHA=2222222222222222222222222222222222222222
TOTAL=0
FAILED=0
SUITE_TMP=$(mktemp -d)
trap 'rm -rf -- "$SUITE_TMP"' EXIT HUP INT TERM

fail() {
    printf '    FALHA: %s\n' "$1" >&2
    CASE_FAILED=1
}

assert_eq() {
    local expected=$1 actual=$2 description=$3
    [ "$actual" = "$expected" ] || fail "$description (esperado '$expected', obtido '$actual')"
}

assert_log() {
    local pattern=$1 description=$2
    grep -Fq -- "$pattern" "$CALL_LOG" || fail "$description (ausente: $pattern)"
}

assert_no_log() {
    local pattern=$1 description=$2
    if grep -Fq -- "$pattern" "$CALL_LOG"; then
        fail "$description (encontrado: $pattern)"
    fi
}

assert_output() {
    local pattern=$1 description=$2
    grep -Fq -- "$pattern" "$CASE_TMP/output" || fail "$description (ausente na saída: $pattern)"
}

assert_log_count() {
    local pattern=$1 expected=$2 description=$3 actual
    actual=$(grep -Fc -- "$pattern" "$CALL_LOG" || true)
    assert_eq "$expected" "$actual" "$description"
}

read_file() {
    # shellcheck disable=SC2015  # o alerta é sobre `C` rodar quando `A` é
    # verdadeiro. Aqui `C` é `true`, então rodar não muda nada: a função devolve
    # o conteúdo quando o arquivo existe e string vazia quando não existe, que é
    # exatamente o contrato desejado.
    [ -f "$1" ] && cat "$1" || true
}

make_fakes() {
    mkdir -p "$CASE_TMP/bin" \
        "$CASE_TMP/apps/controle-bancario" \
        "$CASE_TMP/apps/controle-renda-variavel" \
        "$CASE_TMP/apps/conforto-termico" \
        "$CASE_TMP/apps/mega-sena" \
        "$CASE_TMP/apps/wealthfolio-teste" \
        "$CASE_TMP/state"
    : >"$CASE_TMP/calls.log"
    printf '%s\n' "$OLD_SHA" >"$CASE_TMP/head"

    cat >"$CASE_TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'git' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
case "${1:-}" in
    cat-file) [ "$ARTIFACT" = 1 ]; exit $? ;;
    status) exit 0 ;;
    fetch) exit 0 ;;
    rev-parse)
        if [ "${2:-}" = "--short" ]; then cut -c1-7 "$FAKE_HEAD"
        elif [ "${2:-}" = "origin/main" ]; then printf '%s\n' "${REMOTE_SHA:-$NEW_SHA}"
        else cat "$FAKE_HEAD"
        fi ;;
    log)
        if [ "${2:-}" = "-1" ]; then printf '%s\n' "${IMAGE_SHA:-}"
        else printf '2222222 mudança de teste\n'
        fi ;;
    diff)
        if [ "${2:-}" = --quiet ]; then [ "$RUN_VARIANT" != schema_changed ]; exit $?; fi
        printf ' arquivo | 1 +\n' ;;
    merge)
        [ "$SCENARIO" = ff_failure ] && exit 1
        if [ "$SCENARIO" = override_merge_rollback ]; then
            cat >"$APPS/controle-bancario/compose.patrimonio-internal.yaml" <<'YAML'
services:
  web:
    networks:
      - patrimonio-internal
networks:
  patrimonio-internal:
    external: true
YAML
        fi
        printf '%s\n' "$NEW_SHA" >"$FAKE_HEAD" ;;
    reset)
        if [ "$SCENARIO" = override_merge_rollback ]; then
            rm -f -- "$APPS/controle-bancario/compose.patrimonio-internal.yaml"
        fi
        printf '%s\n' "$3" >"$FAKE_HEAD" ;;
    *) printf 'git fake: comando inesperado: %s\n' "$*" >&2; exit 90 ;;
esac
EOF

    cat >"$CASE_TMP/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
if [ "${1:-}" = builder ]; then exit 0; fi
if [ "${1:-}" = info ]; then
    case "$RUN_VARIANT" in
        unsupported_host) printf 'linux/riscv64\n' ;;
        amd64_host) printf 'linux/x86_64\n' ;;
        *) printf 'linux/aarch64\n' ;;
    esac
    exit 0
fi
if [ "${1:-}" = pull ]; then
    [ "$RUN_VARIANT" != missing_image ]; exit $?
fi
if [ "${1:-}" = image ] && [ "${2:-}" = inspect ]; then
    if [[ "$*" == *'{{.Os}}/{{.Architecture}}'* ]]; then
        case "$RUN_VARIANT:${!#}" in
            app_wrong_arch:*sistema-financeiro@*) printf 'linux/amd64\n' ;;
            postgres_wrong_arch:*sistema-financeiro-postgres@*) printf 'linux/amd64\n' ;;
            missing_arch:*) exit 1 ;;
            amd64_host:*) printf 'linux/amd64\n' ;;
            *) printf 'linux/arm64\n' ;;
        esac
    elif [[ "$*" == *'{{.Id}}'* ]]; then
        if [ "$RUN_VARIANT" = missing_previous ]; then exit 1; fi
        if [[ "${!#}" == "sha256:$(printf '%064d' 1)" ]]; then exit 1; fi
        if [[ "${!#}" == sha256:* ]]; then printf '%s\n' "${!#}"
        else printf 'sha256:%s\n' "$FAKE_IMAGE_ID"; fi
    elif [[ "$*" == *RepoDigests* ]]; then
        repo=${!#}; repo=${repo%:run-*}
        if [ "$RUN_VARIANT" = malformed_digest ]; then printf '%s@sha256:bad\n' "$repo"
        else printf '%s@sha256:%s\n' "$repo" "$FAKE_IMAGE_ID"
        fi
    else
        if [ "$RUN_VARIANT" = wrong_label ] || { [ "$RUN_VARIANT" = wrong_postgres_label ] && [[ "${!#}" == *-postgres@* ]]; }; then printf 'wrong-sha 900-2\n'
        else printf '%s 900-2\n' "$REMOTE_SHA"
        fi
    fi
    exit 0
fi
if [ "${1:-}" = inspect ]; then
    if [[ "$*" == *com.docker.compose.service* ]]; then
        case "${!#}" in
            fake-ict) printf 'ict\n' ;;
            fake-coletor) printf 'coletor\n' ;;
            fake-app) printf 'app\n' ;;
            fake-web) printf 'web\n' ;;
            *) printf 'postgres\n' ;;
        esac
    elif [ "$RUN_VARIANT" = missing_postgres ] && [ "${!#}" = fake-db ]; then
        printf 'sha256:%064d mspa-postgres:17-alpine\n' 1
    elif [ "$RUN_VARIANT" = missing_runtime ] && [ "${!#}" = fake-app ]; then
        printf 'sha256:%064d app:local\n' 1
    elif [ "$RUN_VARIANT" = previous_digest ]; then
        printf 'sha256:%s ghcr.io/mspa-coder/sistema-financeiro@sha256:%s\n' "$FAKE_IMAGE_ID" "$FAKE_IMAGE_ID"
    else printf 'sha256:%s %s\n' "$FAKE_IMAGE_ID" "$FAKE_IMAGE_NAME"
    fi
    exit 0
fi
if [ "${1:-}" = image ] && [ "${2:-}" = tag ]; then exit 0; fi
case " $* " in
    *' up -d --no-build '*)
        # Preserva a override temporária para conferir o contrato do rollback.
        previous=
        for argument in "$@"; do
            if [ "$previous" = -f ] && [[ "$argument" == *".rollback."* ]]; then
                cp -- "$argument" "$CALL_LOG.rollback"
            fi
            previous=$argument
        done
        ;;
esac
case " $* " in
    *' ps -q '*)
        if [ "$ARTIFACT" = 1 ]; then
            case "$FAKE_PROJECT:$RUN_VARIANT" in
                conforto:missing_collector) printf 'fake-ict\nfake-db\n' ;;
                conforto:*) printf 'fake-ict\nfake-coletor\nfake-db\n' ;;
                megasena:*) printf 'fake-app\nfake-db\n' ;;
                *) printf 'fake-web\nfake-db\n' ;;
            esac
        else printf 'fake-container\n'
        fi
        exit 0 ;;
    *' up -d --build '*|*' up -d --no-build '*)
        count=0; [ ! -f "$UP_COUNT" ] || count=$(cat "$UP_COUNT")
        count=$((count + 1)); printf '%s\n' "$count" >"$UP_COUNT"
        case "$SCENARIO:$count" in
            compose_failure:1|override_merge_rollback:1|rollback_failure:1|rollback_failure:2) exit 1 ;;
        esac
        exit 0 ;;
    *' ps --format '*) printf 'app  Up 1 second (healthy)\n'; exit 0 ;;
esac
printf 'docker fake: comando inesperado: %s\n' "$*" >&2
exit 90
EOF

    # A API do GitHub responde com respostas reais reduzidas, em
    # `check-runs/`: a do CRV verde (formatada) e a do NetWorth vermelho
    # (minificada), mais variações delas. `CI_HTTP` diferente de 200 simula a
    # API fora do ar ou recusando.
    cat >"$CASE_TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
case " $* " in
    *actions/workflows/ci.yml/runs?*)
        sha=$REMOTE_SHA; branch=main; conclusion=success; evento=push
        case "$RUN_VARIANT" in
            empty_run) printf '{"total_count":0,"workflow_runs":[]}\n200'; exit 0 ;;
            wrong_sha) sha=$OLD_SHA ;;
            wrong_branch) branch=feature ;;
            failed_run) conclusion=failure ;;
            pr_run) evento=pull_request ;;
            api_failure) printf 'unavailable\n503'; exit 0 ;;
        esac
        printf '{"total_count":1,"workflow_runs":[{"actor":{"id":123,"login":"bot"},"id":900,"head_branch":"%s","head_sha":"%s","event":"%s","status":"completed","conclusion":"%s","run_attempt":2,"repository":{"id":456}}]}\n200' \
            "$branch" "$sha" "$evento" "$conclusion"
        exit 0 ;;
    *api.github.com*)
        if [ "$CI_HTTP" = 200 ]; then
            if [ -n "${IMAGE_SHA:-}" ] && [[ "$*" == *"/commits/$IMAGE_SHA/check-runs?"* ]]; then
                cat "$CHECK_RUNS_DIR/$IMAGE_FIXTURE.json"
            else
                cat "$CHECK_RUNS_DIR/$CI_FIXTURE.json"
            fi
        fi
        printf '\n%s' "$CI_HTTP"
        exit 0 ;;
esac
head=$(cat "$FAKE_HEAD")
if [ "$SCENARIO" = wealthfolio_success ]; then
    printf 'ok\n200'
elif [ "$SCENARIO" = health_failure ] && [ "$head" = "$NEW_SHA" ]; then
    printf '{"status":"error"}\n503'
else
    printf '{"status":"ok"}\n200'
fi
EOF

    cat >"$CASE_TMP/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf 'sleep' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
exit 0
EOF

    cat >"$CASE_TMP/bin/mv" <<'EOF'
#!/usr/bin/env bash
printf 'mv' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
exec /bin/mv "$@"
EOF

    cat >"$CASE_TMP/alerta.sh" <<'EOF'
#!/usr/bin/env bash
printf 'alerta' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
EOF
    chmod +x "$CASE_TMP/bin/"* "$CASE_TMP/alerta.sh"
}

run_deploy() {
    local projeto=${1:-bancario}
    set +e
    env PATH="$CASE_TMP/bin:$PATH" \
        APPS="$CASE_TMP/apps" ALERTA="$CASE_TMP/alerta.sh" ESTADO_DIR="$CASE_TMP/state" \
        APP_LOCK_DIR="$CASE_TMP/app-locks" APP_LOCK_TIMEOUT_SEGUNDOS="${APP_LOCK_TIMEOUT_SEGUNDOS:-300}" \
        CALL_LOG="$CASE_TMP/calls.log" FAKE_HEAD="$CASE_TMP/head" UP_COUNT="$CASE_TMP/up-count" \
        SCENARIO="$SCENARIO" OLD_SHA="$OLD_SHA" NEW_SHA="$NEW_SHA" \
        REMOTE_SHA="${REMOTE_SHA:-$NEW_SHA}" FAKE_IMAGE_ID="$(printf '%064d' 0)" FAKE_IMAGE_NAME="app:local" \
        CHECK_RUNS_DIR="$TESTS_DIR/check-runs" CI_FIXTURE="$CI_FIXTURE" CI_HTTP="$CI_HTTP" \
        IMAGE_SHA="${IMAGE_SHA:-}" IMAGE_FIXTURE="$IMAGE_FIXTURE" \
        ARTIFACT="$ARTIFACT" RUN_VARIANT="$RUN_VARIANT" \
        FAKE_PROJECT="$projeto" \
        bash "$DEPLOY" "$projeto" "${@:2}" >"$CASE_TMP/output" 2>&1
    EXIT_CODE=$?
    set -e
}

begin_case() {
    TOTAL=$((TOTAL + 1))
    CASE_FAILED=0
    CI_FIXTURE=verde
    CI_HTTP=200
    REMOTE_SHA=$NEW_SHA
    IMAGE_SHA=3333333333333333333333333333333333333333
    IMAGE_FIXTURE=wealthfolio
    APP_LOCK_TIMEOUT_SEGUNDOS=300
    ARTIFACT=0
    RUN_VARIANT=valid
    CASE_TMP="$SUITE_TMP/case-$TOTAL"
    CALL_LOG="$CASE_TMP/calls.log"
    mkdir -p "$CASE_TMP"
    make_fakes
}

end_case() {
    local name=$1
    if [ "$CASE_FAILED" -eq 0 ]; then
        printf 'ok %d - %s\n' "$TOTAL" "$name"
    else
        printf 'not ok %d - %s\n' "$TOTAL" "$name"
        sed 's/^/    | /' "$CASE_TMP/output" >&2
        FAILED=$((FAILED + 1))
    fi
}

add_patrimonio_override() {
    cat >"$CASE_TMP/apps/$1/compose.patrimonio-internal.yaml" <<'YAML'
services:
  web:
    networks:
      - patrimonio-internal
networks:
  patrimonio-internal:
    external: true
YAML
}

set -e
printf 'TAP version 13\n'

begin_case
SCENARIO=success
run_deploy
assert_eq 0 "$EXIT_CODE" 'deploy saudável deve sair zero'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/head")" 'HEAD deve ficar no commit novo'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/state/controle-bancario.commit")" 'estado deve registrar o SHA novo'
assert_log 'mv <-f> <-->' 'registro deve terminar por rename atômico'
[ -z "$(find "$CASE_TMP/state" -name '.controle-bancario.commit.*' -print)" ] || fail 'rename atômico não deve deixar arquivo temporário'
assert_no_log 'git <reset>' 'sucesso não deve executar rollback'
assert_log "https://api.github.com/repos/MSPA-Coder/sistema-financeiro/commits/$NEW_SHA/check-runs?per_page=100" 'a CI conferida deve ser a do commit novo, no repositório do projeto'
assert_output '2 check-runs verdes' 'a saída deve contar só os checks de produto'
end_case 'sucesso registra SHA novo atomicamente'

begin_case
SCENARIO=ff_failure
run_deploy
[ "$EXIT_CODE" -ne 0 ] || fail 'falha de fast-forward deve sair não zero'
assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/head")" 'HEAD deve permanecer no commit antigo'
assert_no_log 'git <reset>' 'falha de fast-forward não deve executar reset'
assert_no_log '<up>' 'falha de fast-forward não deve subir ou alterar contêineres'
end_case 'falha de fast-forward não tenta rollback'

begin_case
SCENARIO=compose_failure
add_patrimonio_override controle-bancario
run_deploy
[ "$EXIT_CODE" -ne 0 ] || fail 'deploy revertido deve continuar saindo não zero'
assert_log "git <reset> <--hard> <$OLD_SHA>" 'rollback deve restaurar exatamente o SHA antigo'
assert_log 'docker <image> <tag> <sha256:0000000000000000000000000000000000000000000000000000000000000000> <app:local>' 'rollback deve retaggear a imagem que estava saudável'
assert_log 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <up> <-d> <--no-build>' 'rollback deve subir a imagem anterior sem rebuild'
assert_log_count 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <up>' 2 'deploy e rollback devem usar as duas definições Compose'
assert_log 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <ps>' 'rollback deve conferir o mesmo projeto Compose'
assert_log 'curl <-sSL>' 'rollback deve confirmar /health'
assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/state/controle-bancario.commit")" 'rollback saudável deve registrar SHA antigo'
assert_log 'alerta <DEPLOY REVERTIDO: controle-bancario>' 'rollback saudável deve emitir alerta de reversão'
end_case 'bancario usa os dois Compose no deploy e no rollback'

begin_case
SCENARIO=override_merge_rollback
run_deploy
[ "$EXIT_CODE" -ne 0 ] || fail 'deploy com Compose quebrado deve falhar após rollback'
assert_log 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <up> <-d> <--build>' 'override criada no merge deve entrar no deploy novo'
assert_log 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <up> <-d> <--no-build>' 'rollback deve recalcular os Compose após restaurar checkout sem override'
assert_log_count 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <up> <-d> <--build>' 1 'override só deve ser usada no deploy novo'
assert_log_count 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <up> <-d> <--no-build>' 1 'rollback deve usar somente compose.yaml após a remoção da override'
[ ! -e "$CASE_TMP/apps/controle-bancario/compose.patrimonio-internal.yaml" ] || fail 'checkout antigo deve remover a override após rollback'
end_case 'override que chega no merge é removida da configuração após rollback'

begin_case
SCENARIO=success
CI_FIXTURE=renda-verde
add_patrimonio_override controle-renda-variavel
run_deploy renda
assert_eq 0 "$EXIT_CODE" 'deploy saudável de renda deve sair zero'
assert_log 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <up> <-d> <--build>' 'renda deve adicionar a override presente no checkout'
end_case 'renda usa a override quando ela existe'

begin_case
SCENARIO=success
CI_FIXTURE=conforto-verde
run_deploy conforto
assert_eq 0 "$EXIT_CODE" 'deploy saudável sem override deve sair zero'
assert_log 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <up> <-d> <--build>' 'projeto sem override deve usar apenas compose.yaml'
assert_no_log 'compose.patrimonio-internal.yaml' 'projeto sem override não deve mencionar a override'
end_case 'projeto sem override continua usando apenas compose.yaml'

begin_case
SCENARIO=health_failure
run_deploy
[ "$EXIT_CODE" -ne 0 ] || fail 'health ruim com rollback deve sair não zero'
assert_log "git <reset> <--hard> <$OLD_SHA>" 'health ruim deve restaurar exatamente o SHA antigo'
assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/state/controle-bancario.commit")" 'health ruim revertido deve registrar SHA antigo'
assert_log 'alerta <DEPLOY REVERTIDO: controle-bancario>' 'health ruim revertido deve alertar reversão'
assert_log 'sleep <5>' 'tentativas de health devem usar o sleep falso'
end_case 'health ruim após deploy segue o rollback completo'

begin_case
SCENARIO=rollback_failure
run_deploy
[ "$EXIT_CODE" -ne 0 ] || fail 'falha da reversão deve sair não zero'
assert_log "git <reset> <--hard> <$OLD_SHA>" 'reversão falha ainda deve restaurar o código antigo'
assert_log_count 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <up>' 2 'deve tentar subir a imagem nova e restaurar a anterior'
assert_log 'alerta <DEPLOY QUEBRADO E REVERSÃO FALHOU: controle-bancario>' 'falha da reversão deve emitir alerta grave'
[ ! -e "$CASE_TMP/state/controle-bancario.commit" ] || fail 'falha da reversão não deve registrar SHA'
assert_no_log "mv <-f> <-->" 'falha da reversão não deve publicar arquivo de estado'
end_case 'falha também durante rollback alerta grave e não registra SHA novo'

begin_case
SCENARIO=wealthfolio_success
CI_FIXTURE=wealthfolio-addon
IMAGE_FIXTURE=wealthfolio
add_patrimonio_override wealthfolio-teste
run_deploy wealthfolio
assert_eq 0 "$EXIT_CODE" 'deploy saudável do Wealthfolio deve sair zero'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/state/wealthfolio-teste.commit")" 'Wealthfolio deve registrar o SHA novo'
assert_log 'docker <compose> <--env-file> <.env> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <up> <-d> <--build>' 'Wealthfolio deve usar a rede privada quando a override existe'
assert_log 'https://api.github.com/repos/MSPA-Coder/WealthfolioTeste/commits/2222222222222222222222222222222222222222/check-runs?per_page=100' 'Wealthfolio público deve conferir a CI do SHA exato'
assert_log 'https://api.github.com/repos/MSPA-Coder/WealthfolioTeste/commits/3333333333333333333333333333333333333333/check-runs?per_page=100' 'Wealthfolio deve conferir o último commit que alterou a imagem'
assert_output 'app 2222222: 1 check-run verde; imagem 3333333: 1 check-run verde' 'Wealthfolio deve exigir a CI atual do add-on e os testes do SHA que mudou a imagem'
end_case 'Wealthfolio valida a CI do candidato e a imagem no último commit que a alterou'

begin_case
SCENARIO=success
REMOTE_SHA=$OLD_SHA
add_patrimonio_override controle-bancario
run_deploy bancario --refresh
assert_eq 0 "$EXIT_CODE" 'refresh de tags-base com CI verde deve sair zero'
assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/head")" 'refresh não deve mover o checkout'
assert_no_log 'git <merge>' 'refresh sem alteração não deve fazer fast-forward'
assert_log 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <up> <-d> <--build>' 'refresh deve reconstruir o Compose depois da CI'
assert_log "https://api.github.com/repos/MSPA-Coder/sistema-financeiro/commits/$OLD_SHA/check-runs?per_page=100" 'refresh deve validar a CI do SHA atual'
end_case 'refresh reconstrói tags móveis sem mudança de código e exige CI verde'

# ---------------------------------------------------------------------------
# CI do commit: o deploy só aplica um commit com todos os check-runs de
# produto/segurança terminados e verdes, além dos grupos de testes esperados.
# Atualizadores de dependências e auto-merge não validam o artefato. Recusar
# acontece antes do fast-forward, então nada muda no servidor.
# ---------------------------------------------------------------------------
recusou_antes_de_tocar() {
    [ "$EXIT_CODE" -ne 0 ] || fail 'deploy recusado deve sair não zero'
    assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/head")" 'HEAD deve permanecer no commit antigo'
    assert_no_log 'git <merge>' 'recusa pela CI não deve fazer fast-forward'
    assert_no_log 'docker <compose>' 'recusa pela CI não deve chamar o Compose'
    [ ! -e "$CASE_TMP/state/controle-bancario.commit" ] || fail 'recusa pela CI não deve registrar estado'
    assert_output 'ABORTADO: a CI de 2222222 não está verde' 'a recusa deve dizer que a CI não está verde'
}

begin_case
SCENARIO=success
CI_FIXTURE=wealthfolio-addon
IMAGE_FIXTURE=wealthfolio-image-failure
run_deploy wealthfolio
recusou_antes_de_tocar
assert_output 'imagem em 3333333 não está verde (check-runs de CI/teste reprovados: 1 failure)' 'falha da imagem ancestral deve bloquear o deploy'
end_case 'Wealthfolio recusa quando os testes do último commit de imagem falham'

begin_case
SCENARIO=success
CI_FIXTURE=wealthfolio-addon
IMAGE_SHA=
run_deploy wealthfolio
recusou_antes_de_tocar
assert_output 'não foi possível localizar o último commit que alterou as entradas da imagem' 'ausência de SHA de imagem deve falhar fechada'
end_case 'Wealthfolio recusa quando não consegue localizar o commit de imagem'

begin_case
SCENARIO=success
CI_FIXTURE=vermelho
run_deploy
recusou_antes_de_tocar
assert_output 'check-runs de CI/teste reprovados: 1 failure' 'a recusa deve contar o check-run reprovado'
assert_no_log 'alerta <' 'recusa sem mudança no servidor não deve alertar'
end_case 'CI vermelha recusa antes de tocar no servidor'

begin_case
SCENARIO=success
CI_FIXTURE=pendente
run_deploy
assert_eq 0 "$EXIT_CODE" 'atualizador pendente não deve bloquear testes já concluídos'
assert_output '2 check-runs verdes' 'a contagem deve excluir o updater pendente'
end_case 'Dependabot ainda rodando não bloqueia produto validado'

begin_case
SCENARIO=success
CI_FIXTURE=ci-pendente
run_deploy
recusou_antes_de_tocar
assert_output '1 de 2 check-runs de CI/teste ainda não terminaram' 'a recusa deve dizer que o teste ainda roda'
end_case 'CI ainda rodando recusa'

begin_case
SCENARIO=success
CI_FIXTURE=helpers
run_deploy
assert_eq 0 "$EXIT_CODE" 'falhas apenas nas automações auxiliares não devem bloquear'
assert_output '2 check-runs verdes' 'a saída deve contar só análise e testes de produto'
end_case 'falhas de Dependabot e auto-merge não substituem nem bloqueiam CI verde'

begin_case
SCENARIO=success
CI_FIXTURE=helper-only
run_deploy
recusou_antes_de_tocar
assert_output 'nenhum check-run de CI/teste para validar' 'sem check de produto o deploy deve recusar'
end_case 'checks auxiliares sozinhos não autorizam deploy'

begin_case
SCENARIO=success
CI_FIXTURE=product-red-helpers
run_deploy
recusou_antes_de_tocar
assert_output 'check-runs de CI/teste reprovados: 1 failure' 'falha de produto deve bloquear mesmo com falhas auxiliares'
end_case 'falha de teste continua bloqueando apesar dos erros dos bots'

begin_case
SCENARIO=success
CI_HTTP=000
run_deploy
recusou_antes_de_tocar
assert_output 'a API do GitHub respondeu HTTP 000' 'API fora do ar deve recusar, e não aprovar'
end_case 'API do GitHub fora do ar recusa'

begin_case
SCENARIO=success
CI_FIXTURE=vazio
run_deploy
recusou_antes_de_tocar
assert_output 'nenhum check-run neste commit' 'commit sem check-run deve recusar'
end_case 'commit sem check-run recusa'

begin_case
SCENARIO=success
CI_FIXTURE=inconsistente
run_deploy
recusou_antes_de_tocar
assert_output 'resposta da API fora do esperado (4 check-runs, 3 estados, 3 conclusões)' 'resposta que não bate com total_count deve recusar'
end_case 'resposta da API que não bate com o total recusa'

begin_case
SCENARIO=success
CI_FIXTURE=neutro
run_deploy
assert_eq 0 "$EXIT_CODE" 'neutral e skipped devem contar como verdes'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/head")" 'CI verde com neutral e skipped deve aplicar o commit novo'
end_case 'neutral e skipped contam como verdes'

begin_case
SCENARIO=success
CI_FIXTURE=vermelho
run_deploy bancario --sem-ci
assert_eq 0 "$EXIT_CODE" '--sem-ci deve implantar mesmo com a CI vermelha'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/head")" '--sem-ci deve aplicar o commit novo'
assert_output 'AVISO: implantando 2222222 sem CI verde' '--sem-ci deve avisar no terminal'
assert_log 'alerta <DEPLOY SEM CI VERDE: controle-bancario>' '--sem-ci deve alertar'
end_case '--sem-ci implanta, avisa e alerta'

begin_case
SCENARIO=success
run_deploy bancario --check
[ "$EXIT_CODE" -ne 0 ] || fail '--check removido deve ser recusado'
assert_no_log 'git <fetch>' '--check removido deve parar antes de buscar o main'
assert_output 'Opção desconhecida: --check' '--check removido deve apontar a opção recusada'
end_case '--check removido é recusado antes de tocar no servidor'

begin_case
SCENARIO=success
run_deploy bancario --forcar
[ "$EXIT_CODE" -ne 0 ] || fail 'opção desconhecida deve sair não zero'
assert_no_log 'git <fetch>' 'opção desconhecida deve parar antes de buscar o main'
assert_output 'Opção desconhecida: --forcar' 'a saída deve nomear a opção recusada'
end_case 'opção desconhecida para antes de qualquer coisa'

begin_case
SCENARIO=success
mkdir -p "$CASE_TMP/app-locks"
(
    exec 9>"$CASE_TMP/app-locks/controle-bancario.lock"
    flock -n 9
    sleep 3
) &
lock_pid=$!
sleep 0.1
APP_LOCK_TIMEOUT_SEGUNDOS=0
run_deploy bancario
wait "$lock_pid"
assert_eq 75 "$EXIT_CODE" 'lock ocupado deve sinalizar indisponibilidade temporária'
assert_no_log 'git <fetch>' 'lock ocupado deve parar antes de ler ou alterar o checkout'
assert_output 'controle-bancario está em outra operação' 'a contenção deve identificar o app'
end_case 'deploy manual não concorre com outra operação do mesmo app'

begin_case
SCENARIO=success
ARTIFACT=1
run_deploy
assert_eq 0 "$EXIT_CODE" 'artefato validado deve implantar'
assert_log 'docker <pull> <ghcr.io/mspa-coder/sistema-financeiro:run-900-2>' 'deve baixar a tentativa exata'
assert_log '<-f> <compose.release.yaml> <up> <-d> <--no-build> <--pull> <never>' 'deploy por digest nunca reconstrói'
assert_no_log '<--build>' 'não pode reconstruir nenhuma imagem no caminho de artefato'
assert_output 'run 900-2' 'saída deve identificar o run'
assert_eq "app=ghcr.io/mspa-coder/sistema-financeiro@sha256:$(printf '%064d' 0)
postgres=ghcr.io/mspa-coder/sistema-financeiro-postgres@sha256:$(printf '%064d' 0)" \
    "$(read_file "$CASE_TMP/state/controle-bancario.images")" 'estado guarda os dois digests'
end_case 'artefatos do run verde são implantados e registrados por digest'

for variante in empty_run wrong_sha wrong_branch failed_run pr_run api_failure missing_image malformed_digest wrong_label wrong_postgres_label app_wrong_arch postgres_wrong_arch missing_arch unsupported_host; do
    begin_case
    SCENARIO=success
    ARTIFACT=1
    RUN_VARIANT=$variante
    run_deploy
    [ "$EXIT_CODE" -ne 0 ] || fail 'identidade incompleta/incorreta deve recusar'
    assert_no_log 'git <merge>' 'recusa de artefato ocorre antes do fast-forward'
    assert_no_log 'docker <compose>' 'recusa de artefato não altera contêineres'
    assert_output 'ABORTADO: artefato publicado não pôde ser conferido' 'deve explicar recusa'
    end_case "artefato inválido recusa sem alterar app: $variante"
done

for modo in 0 1; do
    begin_case
    SCENARIO=success
    ARTIFACT=$modo
    RUN_VARIANT=missing_previous
    run_deploy
    [ "$EXIT_CODE" -ne 0 ] || fail 'snapshot irrecuperável deve recusar'
    assert_no_log 'git <merge>' 'imagem anterior ausente recusa antes do fast-forward'
    assert_no_log '<up>' 'imagem anterior ausente não substitui contêineres'
    assert_no_log 'git <reset>' 'recusa não precisa de rollback'
    assert_output 'Imagem anterior indisponível para rollback' 'deve explicar a falta da rede de proteção'
    end_case "imagem anterior indisponível recusa sem tocar app: artefato=$modo"
done

begin_case
SCENARIO=success
ARTIFACT=1
RUN_VARIANT=amd64_host
run_deploy
assert_eq 0 "$EXIT_CODE" 'daemon x86_64 aceita imagens amd64 correspondentes'
end_case 'normaliza arquitetura x86_64 do daemon sem limitar deploy a ARM64'

begin_case
SCENARIO=health_failure
ARTIFACT=1
RUN_VARIANT=previous_digest
run_deploy
[ "$EXIT_CODE" -ne 0 ] || fail 'deploy revertido continua falhando'
assert_log 'git <reset> <--hard>' 'rollback devolve código'
assert_no_log 'docker <image> <tag>' 'referência por digest não pode ser retagueada'
assert_log '<--no-build> <--pull> <never>' 'rollback não reconstrói nem busca outra imagem'
assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/state/controle-bancario.commit")" 'rollback registra commit anterior'
assert_eq "app=sha256:$(printf '%064d' 0)
postgres=sha256:$(printf '%064d' 0)" "$(read_file "$CASE_TMP/state/controle-bancario.images")" 'rollback registra IDs exatos anteriores'
assert_log 'alerta <DEPLOY REVERTIDO: controle-bancario>' 'reversão saudável alerta'
grep -Fq 'mspa.backup.postgres: "true"' "$CALL_LOG.rollback" || fail 'rollback mantém descoberta de backup por rótulo'
grep -Fq '  migrate:' "$CALL_LOG.rollback" || fail 'rollback também fixa migrate'
grep -Fq '  db-provision:' "$CALL_LOG.rollback" || fail 'rollback também fixa provisionamento'
end_case 'rollback de artefato restaura IDs locais, inclusive migrations e provisionamento'

begin_case
SCENARIO=success
ARTIFACT=1
REMOTE_SHA=$OLD_SHA
run_deploy bancario --refresh
assert_eq 0 "$EXIT_CODE" 'refresh usa novo artefato do mesmo commit'
assert_no_log 'git <merge>' 'refresh não move código'
assert_no_log '<--build>' 'refresh por artefato não reconstrói no VPS'
end_case 'refresh semanal resolve run testado sem rebuild no servidor'

for projeto in megasena conforto; do
    begin_case
    SCENARIO=success
    ARTIFACT=1
    [ "$projeto" != conforto ] || CI_FIXTURE=conforto-verde
    run_deploy "$projeto"
    assert_eq 0 "$EXIT_CODE" 'novo aplicativo deve implantar o artefato'
    registry=mega-sena
    [ "$projeto" != conforto ] || registry=conforto-termico
    assert_log "docker <pull> <ghcr.io/mspa-coder/$registry:run-900-2>" 'baixa runtime do app correto'
    assert_log "docker <pull> <ghcr.io/mspa-coder/$registry-postgres:run-900-2>" 'banco tem referência distinta'
    assert_no_log '<--build>' 'artefato novo não recompila'
    end_case "$projeto implanta run validado sem rebuild"

    begin_case
    SCENARIO=health_failure
    ARTIFACT=1
    [ "$projeto" != conforto ] || CI_FIXTURE=conforto-verde
    run_deploy "$projeto"
    [ "$EXIT_CODE" -ne 0 ] || fail 'reversão conserva falha do deploy original'
    for role in postgres db-provision; do
        grep -Fq "  $role:" "$CALL_LOG.rollback" || fail "rollback exige $role"
    done
    if [ "$projeto" = conforto ]; then roles='ict coletor schema'; else roles='app migrate'; fi
    for role in $roles; do
        grep -Fq "  $role:" "$CALL_LOG.rollback" || fail "rollback exige $role"
    done
    assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/head")" 'código volta ao SHA anterior'
    assert_no_log '<--build>' 'reversão não recompila'
    end_case "$projeto restaura todos os papéis por ID local"
done

begin_case
SCENARIO=success
ARTIFACT=1
CI_FIXTURE=conforto-verde
RUN_VARIANT=missing_collector
run_deploy conforto
[ "$EXIT_CODE" -ne 0 ] || fail 'snapshot sem coletor deve recusar'
assert_no_log 'git <merge>' 'sem coletor não altera código'
assert_no_log '<up>' 'sem coletor não altera serviços'
assert_output 'Snapshot de rollback exige coletor em execução' 'recusa explica papel ausente'
end_case 'Conforto exige snapshot de ICT e coletor antes de tocar na produção'

BASELINE="sha256:$(printf '%064d' 0)"
for projeto in megasena conforto; do
    for cenario in success health_failure; do
        begin_case
        SCENARIO=$cenario
        ARTIFACT=1
        RUN_VARIANT=missing_postgres
        [ "$projeto" != conforto ] || CI_FIXTURE=conforto-verde
        run_deploy "$projeto" "--postgres-baseline=$BASELINE"
        assert_output 'MANUTENÇÃO: PostgreSQL anterior' 'troca deliberada de baseline deve ficar explícita'
        assert_no_log '<--build>' 'recuperação não constrói no VPS'
        assert_no_log "docker <image> <tag> <sha256:$(printf '%064d' 1)>" 'não finge recuperar imagem ausente'
        if [ "$cenario" = success ]; then
            assert_eq 0 "$EXIT_CODE" 'manutenção com baseline validado deve concluir'
        else
            [ "$EXIT_CODE" -ne 0 ] || fail 'rollback conserva erro do deploy'
            assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/head")" 'rollback devolve código antigo'
            # Arquivo produzido pelo script real, não uma cópia da política.
            postgres_id=$(sed -n '/^  postgres:/{n;s/.*image: //;p;}' "$CALL_LOG.rollback")
            assert_eq "$BASELINE" "$postgres_id" 'rollback usa novo ponto de retorno deliberado'
            grep -Fq 'mspa.backup.postgres: "true"' "$CALL_LOG.rollback" || fail 'baseline conserva rótulo de backup'
        fi
        end_case "$projeto: baseline explícito conserva deploy/rollback ($cenario)"
    done
done

for variante in missing_runtime schema_changed valid; do
    begin_case
    SCENARIO=success
    ARTIFACT=1
    RUN_VARIANT=$variante
    run_deploy megasena "--postgres-baseline=$BASELINE"
    [ "$EXIT_CODE" -ne 0 ] || fail 'baseline não admite app ausente, migrations ou uso desnecessário'
    assert_no_log 'git <merge>' 'recusa de baseline antecede alteração de código'
    assert_no_log '<up>' 'recusa de baseline não muda contêineres'
    end_case "baseline recusa condição não autorizada: $variante"
done

for argumento in '--postgres-baseline=sha256:bad' "--postgres-baseline=sha256:$(printf '%064d' 2)"; do
    begin_case
    SCENARIO=success
    ARTIFACT=1
    RUN_VARIANT=missing_postgres
    run_deploy megasena "$argumento"
    [ "$EXIT_CODE" -ne 0 ] || fail 'identidade de baseline incorreta deve recusar'
    assert_no_log 'git <merge>' 'ID incorreto não move código'
    assert_no_log '<up>' 'ID incorreto não muda serviços'
    end_case "baseline exige ID completo da candidata: $argumento"
done

for projeto in bancario megasena; do
    begin_case
    SCENARIO=success
    ARTIFACT=1
    argumentos=("--postgres-baseline=$BASELINE")
    [ "$projeto" != megasena ] || argumentos+=(--sem-ci)
    run_deploy "$projeto" "${argumentos[@]}"
    [ "$EXIT_CODE" -ne 0 ] || fail 'baseline deve recusar outro app ou bypass CI'
    assert_no_log 'git <fetch>' 'opção incompatível recusa antes de operar'
    end_case "baseline não amplia escopo nem ignora CI: $projeto"
done

begin_case
SCENARIO=success
ARTIFACT=1
RUN_VARIANT=missing_postgres
run_deploy megasena
[ "$EXIT_CODE" -ne 0 ] || fail 'execução normal continua recusando PostgreSQL ausente'
assert_no_log 'git <merge>' 'timer não pode selecionar baseline implicitamente'
assert_no_log '<up>' 'timer mantém produção intacta'
end_case 'baseline nunca é implícito, inclusive com candidata válida disponível'

printf '1..%d\n' "$TOTAL"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d de %d testes falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf '# %d testes passaram\n' "$TOTAL"
