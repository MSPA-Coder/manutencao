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
        "$CASE_TMP/apps/viva-passo" \
        "$CASE_TMP/apps/villa-rica" \
        "$CASE_TMP/state"
    : >"$CASE_TMP/calls.log"
    printf '%s\n' "$OLD_SHA" >"$CASE_TMP/head"

    cat >"$CASE_TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'git' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
case "${1:-}" in
    cat-file) [ "$ARTIFACT" = 1 ]; exit $? ;;
    remote) printf '%s\n' "${REMOTE_URL-https://github.com/mspa-coder/projeto-teste.git}" ;;
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
if [ "${1:-}" = image ] && [ "${2:-}" = inspect ]; then
    ultimo=${!#}
    if [[ "$ultimo" == mspa-recebida/* ]]; then
        # Rótulo de revisão da imagem enviada pela máquina.
        case "$RUN_VARIANT" in
            recebida) printf '%s\n' "${ultimo##*:}" ;;
            recebida_errada) printf '%s\n' "$OLD_SHA" ;;
            *) exit 1 ;;
        esac
        exit 0
    fi
    if [ "$RUN_VARIANT" = missing_previous ]; then exit 1; fi
    if [[ "$*" == *'--platform linux/arm64'* ]]; then
        # Manifesto da tag na plataforma do contêiner.
        if [ "$RUN_VARIANT" = config_digest_mismatch ]; then printf 'sha256:%064d
' 9
        else printf 'sha256:%064d
' 8; fi
        exit 0
    fi
    if [[ "${!#}" == "sha256:$(printf '%064d' 1)" ]]; then exit 1; fi
    if [[ "${!#}" == sha256:* ]]; then printf '%s\n' "${!#}"
    else printf 'sha256:%s\n' "$FAKE_IMAGE_ID"; fi
    exit 0
fi
if [ "${1:-}" = inspect ]; then
    if [ "${3:-}" = '{{.Image}}' ]; then
        if [[ "$RUN_VARIANT" == config_digest* ]]; then printf 'sha256:%064d
' 1
        else printf 'sha256:%s
' "$FAKE_IMAGE_ID"; fi
    elif [[ "$*" == *ImageManifestDescriptor* ]]; then
        printf 'sha256:%064d linux/arm64
' 8
    elif [[ "$RUN_VARIANT" == config_digest* ]]; then
        # containerd: `.Image` é o digest da configuração, que não se resolve.
        printf 'sha256:%064d %s
' 1 "$FAKE_IMAGE_NAME"
    elif [[ "$*" == *com.docker.compose.project* ]]; then
        # Contêiner de OUTRO app em execução no servidor.
        printf 'controle-renda-variavel\n'
    elif [[ "$*" == *com.docker.compose.service* ]]; then
        case "${!#}" in
            fake-ict) printf 'ict\n' ;;
            fake-coletor) printf 'coletor\n' ;;
            fake-app) printf 'app\n' ;;
            fake-web) printf 'web\n' ;;
            *) printf 'postgres\n' ;;
        esac
    elif [ "$RUN_VARIANT" = previous_digest ]; then
        printf 'sha256:%s ghcr.io/mspa-coder/controle-bancario@sha256:%s\n' "$FAKE_IMAGE_ID" "$FAKE_IMAGE_ID"
    elif [ "$RUN_VARIANT" = previous_id ]; then
        printf 'sha256:%s sha256:%s\n' "$FAKE_IMAGE_ID" "$FAKE_IMAGE_ID"
    else printf 'sha256:%s %s\n' "$FAKE_IMAGE_ID" "$FAKE_IMAGE_NAME"
    fi
    exit 0
fi
if [ "${1:-}" = image ] && [ "${2:-}" = tag ]; then exit 0; fi
if [ "${1:-}" = image ] && [ "${2:-}" = ls ]; then
    # Guardas do app: a da imagem em uso e uma antiga, que deve ser podada.
    printf '%s:000000000000
%s:abcdefabcdef
' "${!#}" "${!#}"
    exit 0
fi
if [ "${1:-}" = image ] && [ "${2:-}" = rm ]; then exit 0; fi
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
    *' config --services '*)
        case "$FAKE_PROJECT" in
            conforto) printf 'postgres\ndb-provision\nschema\ncoletor\nict\n' ;;
            megasena) printf 'postgres\ndb-provision\nmigrate\napp\n' ;;
            renda) printf 'db\ndb-provision\nmigrate\nweb\n' ;;
            *) printf 'postgres\ndb-provision\nmigrate\nweb\n' ;;
        esac
        exit 0 ;;
    *' config --images wealthfolio '*)
        printf 'wealthfolio-teste:local\n'; exit 0 ;;
    *' config --images postgres '*|*' config --images db '*)
        printf 'mspa-postgres:17-alpine\n'; exit 0 ;;
    *' config --images '*)
        # Como o Compose real: a lista do serviço inclui as dependências.
        if [ "$RUN_VARIANT" = two_app_images ]; then printf 'outra:local\n'; fi
        printf 'app:local\nmspa-postgres:17-alpine\napp:local\n'; exit 0 ;;
    *' build '*)
        [ "$SCENARIO" != build_failure ]; exit $? ;;
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

    # Corpo que a API de check-runs devolveria, conforme CI_MODO.
    cat >"$CASE_TMP/ci-payload" <<'EOF'
#!/usr/bin/env bash
case "${CI_MODO:-verde}" in
    verde) printf '{"total_count":2,"check_runs":[{"name":"lint","status":"completed","conclusion":"success"},{"name":"test","status":"completed","conclusion":"skipped"}]}' ;;
    vermelha) printf '{"total_count":2,"check_runs":[{"name":"lint","status":"completed","conclusion":"success","app":{"name":"GitHub Actions"}},{"name":"test (py3.14)","status":"completed","conclusion":"failure","app":{"name":"GitHub Actions"}}]}' ;;
    andamento) printf '{"total_count":2,"check_runs":[{"name":"lint","status":"completed","conclusion":"success"},{"name":"test","status":"in_progress","conclusion":null}]}' ;;
    vazio) printf '{"total_count":0,"check_runs":[]}' ;;
    lixo) printf '<html>rate limit</html>' ;;
esac
EOF
    # `gh` sem autenticação por padrão (sai 4, como o real); com CI_VIA=gh
    # serve o mesmo corpo; com CI_VIA=gh_lento trava além do limite.
    cat >"$CASE_TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
case "${CI_VIA:-curl}" in
    gh) exec bash "$CASE_TMP/ci-payload" ;;
    gh_lento) exec /bin/sleep 30 ;;
    *) exit 4 ;;
esac
EOF

    # A sonda pública /health e a API de check-runs do GitHub passam por aqui;
    # a API só é atendida conforme CI_MODO (falha e lenta simulam rede ruim).
    cat >"$CASE_TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
if [[ "$*" == *api.github.com* ]]; then
    case "${CI_MODO:-verde}" in
        falha) exit 22 ;;
        lenta) exec /bin/sleep 30 ;;
        *) exec bash "$CASE_TMP/ci-payload" ;;
    esac
fi
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
printf 'alerta' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf ' janela=%s\n' "${ALERTA_JANELA-ausente}" >>"$CALL_LOG"
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
        ARTIFACT="$ARTIFACT" RUN_VARIANT="$RUN_VARIANT" \
        FAKE_PROJECT="$projeto" CASE_TMP="$CASE_TMP" \
        CI_MODO="${CI_MODO:-verde}" CI_VIA="${CI_VIA:-curl}" REMOTE_URL="${REMOTE_URL-https://github.com/mspa-coder/projeto-teste.git}" \
        CI_LIMITE_SEGUNDOS="${CI_LIMITE_SEGUNDOS:-1}" \
        bash "$DEPLOY" "$projeto" "${@:2}" >"$CASE_TMP/output" 2>&1
    EXIT_CODE=$?
    set -e
}

begin_case() {
    TOTAL=$((TOTAL + 1))
    CASE_FAILED=0
    REMOTE_SHA=$NEW_SHA
    APP_LOCK_TIMEOUT_SEGUNDOS=300
    ARTIFACT=0
    RUN_VARIANT=valid
    CI_MODO=verde
    CI_VIA=curl
    unset REMOTE_URL
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
run_deploy viva-passo
assert_eq 0 "$EXIT_CODE" 'deploy estático saudável deve sair zero'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/head")" 'site estático deve ficar no commit novo'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/state/viva-passo.commit")" 'site estático deve registrar SHA novo'
assert_no_log 'docker' 'site estático não deve montar nem subir contêiner'
assert_no_log 'git <reset>' 'site estático saudável não deve executar rollback'
end_case 'site estático faz fast-forward, sonda pública e registro sem Docker'

begin_case
SCENARIO=health_failure
run_deploy viva-passo
[ "$EXIT_CODE" -ne 0 ] || fail 'site estático sem saúde deve sair não zero'
assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/head")" 'site estático sem saúde deve voltar ao SHA anterior'
assert_log 'git <reset> <--hard> <1111111111111111111111111111111111111111>' 'site estático sem saúde deve executar rollback'
assert_no_log 'docker' 'rollback estático não deve tocar Docker'
end_case 'site estático reverte checkout quando a sonda pública falha'

begin_case
SCENARIO=success
run_deploy villa-rica
assert_eq 0 "$EXIT_CODE" 'villa-rica (site estático) saudável deve sair zero'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/state/villa-rica.commit")" 'villa-rica deve registrar SHA novo'
assert_no_log 'docker' 'villa-rica não deve montar nem subir contêiner'
end_case 'villa-rica é implantado como site estático, sem Docker'

begin_case
SCENARIO=success
run_deploy
assert_eq 0 "$EXIT_CODE" 'deploy saudável deve sair zero'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/head")" 'HEAD deve ficar no commit novo'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/state/controle-bancario.commit")" 'estado deve registrar o SHA novo'
assert_log 'mv <-f> <-->' 'registro deve terminar por rename atômico'
[ -z "$(find "$CASE_TMP/state" -name '.controle-bancario.commit.*' -print)" ] || fail 'rename atômico não deve deixar arquivo temporário'
assert_no_log 'git <reset>' 'sucesso não deve executar rollback'
# Decisão de 20/10/2026: a validação é feita na máquina antes do commit.
assert_log 'api.github.com/repos/mspa-coder/projeto-teste/commits/'"$NEW_SHA"'/check-runs' 'consulta a CI do commit que vai implantar'
assert_output 'CI do commit 2222222: verde.' 'diz que a CI está verde'
# Guardas por app (20/10/2026): o nome compartilhado do banco não pode mais
# deixar sem nome, e portanto apagar, a imagem que um app está rodando.
assert_log 'docker <image> <tag> <sha256:0000000000000000000000000000000000000000000000000000000000000000> <mspa-deploy/controle-bancario:000000000000>' 'guarda a imagem em uso com nome do app'
assert_log 'docker <image> <rm> <mspa-deploy/controle-bancario:abcdefabcdef>' 'poda a guarda que não é nem a atual nem a anterior'
assert_no_log 'docker <image> <rm> <mspa-deploy/controle-bancario:000000000000>' 'mantém a guarda da imagem em uso'
end_case 'sucesso registra SHA novo atomicamente, sem consultar a CI'

# A janela que o `sentinela.sh` lê para não alertar o 502 da troca de
# contêiner: início e fim, com o domínio da sonda, no deploy que dá certo e no
# que é revertido.
for SCENARIO in success compose_failure; do
    begin_case
    run_deploy
    janelas="$CASE_TMP/state/janelas.log"
    [ -f "$janelas" ] || fail "o deploy ($SCENARIO) deve registrar a janela"
    assert_eq 'inicio bancario-mspa.duckdns.org
fim bancario-mspa.duckdns.org' "$(cut -d' ' -f1,2 "$janelas" 2>/dev/null)" \
        "início e fim com o domínio ($SCENARIO)"
    grep -Eq '^(inicio|fim) [^ ]+ [0-9]+$' "$janelas" || fail 'cada linha termina no epoch'
    end_case "deploy registra a própria janela para o sentinela ($SCENARIO)"
done

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
# SEG-A3: o título do deploy não carrega o commit, então o `alerta.sh` (que
# deduplica pelo título em 15 min) suprimiria a segunda falha. O deploy pede
# janela zero: toda falha de deploy chega.
assert_log ' janela=0' 'alerta de deploy deve pedir ALERTA_JANELA=0, senão a segunda falha em 15 min some'
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
add_patrimonio_override controle-renda-variavel
run_deploy renda
assert_eq 0 "$EXIT_CODE" 'deploy saudável de renda deve sair zero'
assert_log 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <up> <-d> <--build>' 'renda deve adicionar a override presente no checkout'
end_case 'renda usa a override quando ela existe'

begin_case
SCENARIO=success
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
add_patrimonio_override wealthfolio-teste
run_deploy wealthfolio
assert_eq 0 "$EXIT_CODE" 'deploy saudável do Wealthfolio deve sair zero'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/state/wealthfolio-teste.commit")" 'Wealthfolio deve registrar o SHA novo'
assert_log 'docker <compose> <--env-file> <.env> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <up> <-d> <--build>' 'Wealthfolio deve usar a rede privada quando a override existe'
assert_output 'CI do commit 2222222: verde.' 'Wealthfolio também avisa a CI'
end_case 'Wealthfolio implanta montando no servidor'

begin_case
SCENARIO=wealthfolio_success
RUN_VARIANT=recebida
add_patrimonio_override wealthfolio-teste
run_deploy wealthfolio
assert_eq 0 "$EXIT_CODE" 'deploy com imagem recebida deve sair zero'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/state/wealthfolio-teste.commit")" 'registra o SHA novo'
assert_log "docker <image> <tag> <mspa-recebida/wealthfolio-teste:$NEW_SHA> <wealthfolio-teste:local>" 'a imagem recebida ganha o nome do Compose'
assert_log 'docker <compose> <--env-file> <.env> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <up> <-d> <--no-build> <--pull> <never>' 'sobe sem montar'
assert_no_log '<up> <-d> <--build>' 'não monta no servidor'
assert_no_log '<build>' 'nenhum build no servidor'
assert_output 'Imagem recebida da máquina' 'a saída diz de onde veio a imagem'
end_case 'Wealthfolio sobe a imagem recebida do commit sem montar no servidor'

begin_case
SCENARIO=wealthfolio_success
RUN_VARIANT=recebida_errada
add_patrimonio_override wealthfolio-teste
run_deploy wealthfolio
assert_eq 0 "$EXIT_CODE" 'imagem recebida de outro commit não bloqueia o deploy'
assert_no_log "<image> <tag> <mspa-recebida/" 'imagem de outro commit não é usada'
assert_log '<up> <-d> <--build>' 'monta no servidor como antes'
assert_output 'montando no servidor' 'a saída explica a recusa'
end_case 'imagem recebida com rótulo de outro commit é ignorada e o servidor monta'

begin_case
SCENARIO=success
REMOTE_SHA=$OLD_SHA
add_patrimonio_override controle-bancario
run_deploy bancario --refresh
assert_eq 0 "$EXIT_CODE" 'refresh deve sair zero'
assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/head")" 'refresh não deve mover o checkout'
assert_no_log 'git <merge>' 'refresh sem alteração não deve fazer fast-forward'
assert_log 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <build> <--pull> <--no-cache>' 'refresh deve buscar bases novas'
assert_log 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <up> <-d> <--build>' 'refresh deve subir a versão remontada'
end_case 'refresh remonta a versão no ar com bases novas'

# O receio do usuário (20/10/2026): nada que ele não testou e não mandou entra
# em produção. Com o main à frente, o refresh remonta o que está no ar e só
# lista os commits pendentes.
begin_case
SCENARIO=success
run_deploy bancario --refresh
assert_eq 0 "$EXIT_CODE" 'refresh com o main à frente deve sair zero'
assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/head")" 'refresh nunca aplica commit novo'
assert_no_log 'git <merge>' 'refresh nunca faz fast-forward'
assert_output 'O main tem commits ainda não implantados; --refresh não os aplica' 'refresh deve dizer o que deixou de fora'
assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/state/controle-bancario.commit")" 'estado continua no commit que estava no ar'
end_case 'refresh não aplica commits que o usuário ainda não mandou implantar'

begin_case
SCENARIO=success
REMOTE_SHA=$OLD_SHA
run_deploy bancario
assert_eq 0 "$EXIT_CODE" 'nada a fazer deve sair zero'
assert_output 'Nada a fazer' 'deve dizer que já está na versão do main'
assert_no_log 'docker <compose>' 'sem commit novo, nada é montado nem trocado'
end_case 'deploy sem commit novo não mexe em nada'

for opcao in --sem-ci --check --forcar '--postgres-baseline=sha256:abc'; do
    begin_case
    SCENARIO=success
    run_deploy bancario "$opcao"
    [ "$EXIT_CODE" -ne 0 ] || fail 'opção desconhecida deve sair não zero'
    assert_no_log 'git <fetch>' 'opção desconhecida deve parar antes de buscar o main'
    assert_output "Opção desconhecida: $opcao" 'a saída deve nomear a opção recusada'
    end_case "opção removida ou desconhecida é recusada antes de tudo: $opcao"
done

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

# No image store do containerd, o contêiner subido por tag aponta para o digest
# da configuração, que não se resolve. A tag vale como retorno se o manifesto
# dela for o que o contêiner roda; foi o que travou o Wealthfolio em 18/10/2026.
begin_case
SCENARIO=compose_failure
RUN_VARIANT=config_digest
run_deploy
[ "$EXIT_CODE" -ne 0 ] || fail 'deploy revertido continua falhando'
assert_log "git <merge>" 'manifesto conferido não bloqueia o deploy'
assert_log 'docker <image> <inspect> <--platform> <linux/arm64> <--format> <{{.Descriptor.Digest}}> <app:local>' 'deve conferir o manifesto da tag'
assert_log 'docker <image> <tag> <sha256:0000000000000000000000000000000000000000000000000000000000000000> <app:local>' 'rollback volta para o ID resolvido pela tag'
assert_log 'alerta <DEPLOY REVERTIDO: controle-bancario>' 'reversão saudável alerta'
end_case 'imagem por digest de configuração volta pelo ID da tag cujo manifesto confere'

begin_case
SCENARIO=success
RUN_VARIANT=config_digest_mismatch
run_deploy
[ "$EXIT_CODE" -ne 0 ] || fail 'manifesto divergente deve recusar'
assert_no_log 'git <merge>' 'manifesto divergente recusa antes do fast-forward'
assert_no_log '<up>' 'manifesto divergente não troca contêiner'
assert_output 'Imagem anterior indisponível para rollback' 'deve explicar a recusa'
end_case 'tag com outro manifesto não serve de retorno'

begin_case
SCENARIO=wealthfolio_success
RUN_VARIANT=config_digest
run_deploy wealthfolio
assert_eq 0 "$EXIT_CODE" 'Wealthfolio com digest de configuração deve implantar'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/state/wealthfolio-teste.commit")" 'registra o SHA novo'
end_case 'Wealthfolio implanta quando o contêiner aponta para o digest de configuração'

# ---------------------------------------------------------------------------
# Apps com `compose.release.yaml`: as imagens são montadas aqui e sobem por ID.
# ---------------------------------------------------------------------------
begin_case
SCENARIO=success
ARTIFACT=1
run_deploy
assert_eq 0 "$EXIT_CODE" 'montagem local deve implantar'
assert_log_count 'docker <image> <tag> <sha256:0000000000000000000000000000000000000000000000000000000000000000> <mspa-deploy/controle-bancario:000000000000>' 6 'guarda as anteriores (2), as montadas (2) e as em uso (2)'
assert_log 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <build>' 'deve montar as imagens no servidor'
assert_no_log '<build> <--pull>' 'deploy comum não busca imagens-base novas'
assert_no_log 'docker <pull>' 'nada é baixado do registry'
assert_log '<-f> <compose.release.yaml> <up> <-d> <--no-build> <--pull> <never>' 'sobe por ID, sem remontar'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/head")" 'HEAD fica no commit novo'
assert_eq "app=sha256:$(printf '%064d' 0)
postgres=sha256:$(printf '%064d' 0)" \
    "$(read_file "$CASE_TMP/state/controle-bancario.images")" 'estado guarda os IDs montados'
end_case 'imagens montadas no servidor sobem por ID e ficam registradas'

# 01/11/2026: o banco do CB recriado fora do deploy rodava uma imagem sem guarda,
# e a montagem do CRV levou o nome compartilhado e a apagou. Antes de montar,
# toda imagem em uso no servidor ganha a guarda do projeto do contêiner.
begin_case
SCENARIO=success
ARTIFACT=1
run_deploy
assert_eq 0 "$EXIT_CODE" 'deploy com guarda de todo o servidor deve implantar'
guarda_alheia='docker <image> <tag> <sha256:0000000000000000000000000000000000000000000000000000000000000000> <mspa-deploy/controle-renda-variavel:000000000000>'
assert_log "$guarda_alheia" 'guarda a imagem em uso de outro app com o nome dele'
linha_guarda=$(grep -nF -- "$guarda_alheia" "$CALL_LOG" | head -1 | cut -d: -f1)
linha_build=$(grep -nF -- '<compose.yaml> <build>' "$CALL_LOG" | head -1 | cut -d: -f1)
[ -n "$linha_guarda" ] && [ -n "$linha_build" ] && [ "$linha_guarda" -lt "$linha_build" ] \
    || fail 'a guarda de todo o servidor deve vir antes da montagem'
assert_no_log 'docker <image> <rm> <mspa-deploy/controle-renda-variavel' 'a poda de um app não toca a guarda de outro'
end_case 'antes de montar, toda imagem em uso no servidor fica guardada com o nome do seu projeto'

begin_case
SCENARIO=build_failure
ARTIFACT=1
run_deploy
[ "$EXIT_CODE" -ne 0 ] || fail 'montagem que falha deve sair não zero'
assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/head")" 'o código volta para o commit que estava no ar'
assert_no_log '<up>' 'montagem que falha não troca contêiner nenhum'
assert_output 'a montagem das imagens falhou; nenhum contêiner foi trocado' 'deve explicar a falha'
assert_no_log 'alerta <' 'falha sem efeito em produção não alerta'
[ ! -e "$CASE_TMP/state/controle-bancario.commit" ] || fail 'falha de montagem não registra SHA'
end_case 'montagem que falha devolve o código sem tocar os contêineres'

begin_case
SCENARIO=success
ARTIFACT=1
RUN_VARIANT=two_app_images
run_deploy
[ "$EXIT_CODE" -ne 0 ] || fail 'imagem de app ambígua deve recusar'
assert_no_log '<up>' 'ambiguidade não troca contêiner'
assert_output 'Não foi possível identificar uma única imagem de app e de banco' 'deve explicar a recusa'
end_case 'imagem de app ambígua recusa sem tocar os contêineres'

begin_case
SCENARIO=success
ARTIFACT=1
RUN_VARIANT=valid
run_deploy renda
assert_eq 0 "$EXIT_CODE" 'renda usa o serviço db como banco'
assert_log 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <config> <--images> <db>' 'o banco do renda é o serviço db'
end_case 'renda identifica o banco pelo serviço db'

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
    end_case "imagem anterior indisponível recusa sem tocar app: por_id=$modo"
done

for variante in previous_digest previous_id; do
    begin_case
    SCENARIO=health_failure
    ARTIFACT=1
    RUN_VARIANT=$variante
    run_deploy
    [ "$EXIT_CODE" -ne 0 ] || fail 'deploy revertido continua falhando'
    assert_log 'git <reset> <--hard>' 'rollback devolve código'
    assert_no_log '> <ghcr.io/' 'referência por digest não é tag a restaurar'
    assert_no_log "<tag> <sha256:$(printf '%064d' 0)> <sha256:" 'referência por ID não é tag a restaurar'
    assert_log '<--no-build> <--pull> <never>' 'rollback não remonta nem busca outra imagem'
    assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/state/controle-bancario.commit")" 'rollback registra commit anterior'
    assert_eq "app=sha256:$(printf '%064d' 0)
postgres=sha256:$(printf '%064d' 0)" "$(read_file "$CASE_TMP/state/controle-bancario.images")" 'rollback registra IDs exatos anteriores'
    assert_log 'alerta <DEPLOY REVERTIDO: controle-bancario>' 'reversão saudável alerta'
    grep -Fq 'mspa.backup.postgres: "true"' "$CALL_LOG.rollback" || fail 'rollback mantém descoberta de backup por rótulo'
    grep -Fq '  migrate:' "$CALL_LOG.rollback" || fail 'rollback também fixa migrate'
    grep -Fq '  db-provision:' "$CALL_LOG.rollback" || fail 'rollback também fixa provisionamento'
    end_case "rollback por ID restaura migrations e provisionamento: $variante"
done

begin_case
SCENARIO=success
ARTIFACT=1
REMOTE_SHA=$OLD_SHA
run_deploy bancario --refresh
assert_eq 0 "$EXIT_CODE" 'refresh por ID deve sair zero'
assert_no_log 'git <merge>' 'refresh não move código'
assert_log '<build> <--pull> <--no-cache>' 'refresh busca bases novas'
assert_log '<-f> <compose.release.yaml> <up> <-d> <--no-build> <--pull> <never>' 'refresh sobe por ID'
end_case 'refresh por ID remonta a versão no ar com bases novas'

for projeto in megasena conforto; do
    begin_case
    SCENARIO=success
    ARTIFACT=1
    run_deploy "$projeto"
    assert_eq 0 "$EXIT_CODE" 'app deve implantar as imagens montadas'
    assert_log '<build>' 'monta no servidor'
    assert_no_log 'docker <pull>' 'nada é baixado'
    end_case "$projeto implanta imagens montadas no servidor"

    begin_case
    SCENARIO=health_failure
    ARTIFACT=1
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
    assert_log_count '<build>' 1 'reversão não remonta'
    end_case "$projeto restaura todos os papéis por ID local"
done

begin_case
SCENARIO=success
ARTIFACT=1
RUN_VARIANT=missing_collector
run_deploy conforto
[ "$EXIT_CODE" -ne 0 ] || fail 'snapshot sem coletor deve recusar'
assert_no_log 'git <merge>' 'sem coletor não altera código'
assert_no_log '<up>' 'sem coletor não altera serviços'
assert_output 'Snapshot de rollback exige coletor em execução' 'recusa explica papel ausente'
end_case 'Conforto exige snapshot de ICT e coletor antes de tocar na produção'

# ---------------------------------------------------------------------------
# Aviso da CI (decisão de 11/11/2026): consulta antes de aplicar o commit e só
# avisa. Em todos os casos o deploy termina igual: sai zero, aplica o commit e
# registra o estado; nada é alertado por causa da CI.
# ---------------------------------------------------------------------------
confere_deploy_igual() {
    assert_eq 0 "$EXIT_CODE" "$1: o deploy termina zero"
    assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/head")" "$1: o commit é aplicado"
    assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/state/controle-bancario.commit")" "$1: o estado é gravado"
    assert_no_log 'alerta' "$1: a CI nunca dispara alerta externo"
    assert_output 'OK: controle-bancario' "$1: o deploy chega ao fim"
}

begin_case
SCENARIO=success
CI_MODO=vermelha
run_deploy bancario
confere_deploy_igual 'CI vermelha'
assert_output 'AVISO: CI do commit 2222222 VERMELHA (falhou: test (py3.14)). O deploy segue' 'vermelha chama atenção e nomeia o job'
end_case 'CI vermelha avisa com o job que falhou e o deploy segue'

begin_case
SCENARIO=success
CI_MODO=andamento
run_deploy bancario
confere_deploy_igual 'CI em andamento'
assert_output 'CI do commit 2222222: em andamento' 'diz que está em andamento'
end_case 'CI em andamento avisa e o deploy não espera'

begin_case
SCENARIO=success
CI_MODO=verde
CI_VIA=gh
run_deploy bancario
confere_deploy_igual 'CI via gh'
assert_log 'gh <api>' 'usa o gh quando autenticado'
assert_no_log 'api.github.com' 'com gh funcionando não cai no curl'
assert_output 'CI do commit 2222222: verde.' 'resultado do gh'
end_case 'CI consultada pelo gh quando ele responde'

begin_case
SCENARIO=success
CI_MODO=vermelha
run_deploy bancario
assert_log 'gh <api>' 'tenta o gh primeiro'
assert_log 'api.github.com' 'gh sem autenticação cai na API pública por curl'
assert_output 'VERMELHA' 'o curl público entrega o resultado'
end_case 'gh sem autenticação cai na API pública'

begin_case
SCENARIO=success
CI_MODO=vazio
run_deploy bancario
confere_deploy_igual 'CI sem verificações'
assert_output 'CI do commit 2222222: sem informação' 'commit sem verificação é sem informação'
end_case 'commit sem verificações registradas vira sem informação'

for modo in falha lixo; do
    begin_case
    SCENARIO=success
    CI_MODO=$modo
    run_deploy bancario
    confere_deploy_igual "consulta $modo"
    assert_output 'CI do commit 2222222: sem informação' "consulta $modo vira sem informação"
    end_case "consulta que dá $modo vira sem informação e o deploy segue"
done

begin_case
SCENARIO=success
CI_MODO=lenta
inicio=$SECONDS
run_deploy bancario
duracao=$((SECONDS - inicio))
confere_deploy_igual 'consulta lenta'
assert_output 'CI do commit 2222222: sem informação' 'consulta lenta vira sem informação'
[ "$duracao" -le 4 ] || fail "consulta lenta atrasou o deploy ($duracao s com limite de 1 s)"
end_case 'consulta que demora além do limite é cortada e o deploy segue'

begin_case
SCENARIO=success
CI_MODO=verde
CI_VIA=gh_lento
inicio=$SECONDS
run_deploy bancario
duracao=$((SECONDS - inicio))
confere_deploy_igual 'gh lento'
assert_output 'CI do commit 2222222: sem informação' 'gh lento vira sem informação'
[ "$duracao" -le 4 ] || fail "gh lento atrasou o deploy ($duracao s com limite de 1 s)"
end_case 'gh que trava não passa do orçamento de tempo total'

begin_case
SCENARIO=success
REMOTE_URL='https://exemplo.com/algum/repo.git'
run_deploy bancario
confere_deploy_igual 'remoto fora do GitHub'
assert_no_log 'api.github.com' 'remoto estranho não consulta a API'
assert_output 'sem informação (remoto não é um repositório do GitHub)' 'explica o motivo'
end_case 'remoto que não é do GitHub vira sem informação'

begin_case
SCENARIO=success
REMOTE_URL='git@github.com:mspa-coder/projeto-teste.git'
run_deploy bancario
confere_deploy_igual 'remoto ssh'
assert_log 'api.github.com/repos/mspa-coder/projeto-teste/' 'dono e repo saem também de um remoto SSH'
end_case 'dono e repositório saem de um remoto SSH'

begin_case
SCENARIO=success
CI_MODO=vermelha
run_deploy villa-rica
assert_eq 0 "$EXIT_CODE" 'site estático com CI vermelha termina zero'
assert_eq "$NEW_SHA" "$(read_file "$CASE_TMP/head")" 'site estático aplica o commit'
assert_output 'VERMELHA' 'site estático também avisa a CI'
assert_no_log 'alerta' 'CI do site estático não alerta'
end_case 'site estático também avisa a CI e segue'

begin_case
SCENARIO=success
CI_MODO=vermelha
run_deploy bancario --refresh
assert_eq 0 "$EXIT_CODE" 'refresh termina zero'
assert_no_log 'api.github.com' 'refresh não consulta a CI'
assert_no_log 'gh <api>' 'refresh não chama o gh'
end_case 'refresh não consulta a CI'

begin_case
SCENARIO=success
CI_MODO=vermelha
REMOTE_SHA=$OLD_SHA
run_deploy bancario
assert_no_log 'api.github.com' 'sem commit novo não consulta a CI'
end_case 'sem commit novo não consulta a CI'

begin_case
SCENARIO=health_failure
CI_MODO=verde
run_deploy bancario
[ "$EXIT_CODE" -ne 0 ] || fail 'a CI verde não esconde a falha de saúde'
assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/head")" 'o rollback continua valendo'
end_case 'CI verde não muda o rollback quando a saúde falha'

printf '1..%d\n' "$TOTAL"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d de %d testes falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf '# %d testes passaram\n' "$TOTAL"
