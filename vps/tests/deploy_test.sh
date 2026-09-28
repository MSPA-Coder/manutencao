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
        "$CASE_TMP/state"
    : >"$CASE_TMP/calls.log"
    printf '%s\n' "$OLD_SHA" >"$CASE_TMP/head"

    cat >"$CASE_TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'git' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
case "${1:-}" in
    status) exit 0 ;;
    fetch) exit 0 ;;
    rev-parse)
        if [ "${2:-}" = "--short" ]; then cut -c1-7 "$FAKE_HEAD"
        elif [ "${2:-}" = "origin/main" ]; then printf '%s\n' "$NEW_SHA"
        else cat "$FAKE_HEAD"
        fi ;;
    log) printf '2222222 mudança de teste\n' ;;
    diff) printf ' arquivo | 1 +\n' ;;
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
case " $* " in
    *' up -d --build '*)
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

    cat >"$CASE_TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
head=$(cat "$FAKE_HEAD")
if [ "$SCENARIO" = health_failure ] && [ "$head" = "$NEW_SHA" ]; then
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
    PATH="$CASE_TMP/bin:$PATH" \
    APPS="$CASE_TMP/apps" ALERTA="$CASE_TMP/alerta.sh" ESTADO_DIR="$CASE_TMP/state" \
    CALL_LOG="$CASE_TMP/calls.log" FAKE_HEAD="$CASE_TMP/head" UP_COUNT="$CASE_TMP/up-count" \
    SCENARIO="$SCENARIO" OLD_SHA="$OLD_SHA" NEW_SHA="$NEW_SHA" \
        bash "$DEPLOY" "$projeto" >"$CASE_TMP/output" 2>&1
    EXIT_CODE=$?
    set -e
}

begin_case() {
    TOTAL=$((TOTAL + 1))
    CASE_FAILED=0
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
end_case 'sucesso registra SHA novo atomicamente'

begin_case
SCENARIO=ff_failure
run_deploy
[ "$EXIT_CODE" -ne 0 ] || fail 'falha de fast-forward deve sair não zero'
assert_eq "$OLD_SHA" "$(read_file "$CASE_TMP/head")" 'HEAD deve permanecer no commit antigo'
assert_no_log 'git <reset>' 'falha de fast-forward não deve executar reset'
assert_no_log 'docker <compose>' 'falha de fast-forward não deve chamar Compose'
end_case 'falha de fast-forward não tenta rollback'

begin_case
SCENARIO=compose_failure
add_patrimonio_override controle-bancario
run_deploy
[ "$EXIT_CODE" -ne 0 ] || fail 'deploy revertido deve continuar saindo não zero'
assert_log "git <reset> <--hard> <$OLD_SHA>" 'rollback deve restaurar exatamente o SHA antigo'
assert_log 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <up> <-d> <--build>' 'rollback deve subir a imagem antiga com as duas definições Compose'
assert_log_count 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <up> <-d> <--build>' 2 'deploy e rollback devem usar as duas definições Compose'
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
assert_log 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <up> <-d> <--build>' 'rollback deve recalcular os Compose após restaurar checkout sem override'
assert_log_count 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <-f> <compose.patrimonio-internal.yaml> <up> <-d> <--build>' 1 'override só deve ser usada no deploy novo'
assert_log_count 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <up> <-d> <--build>' 1 'rollback deve usar somente compose.yaml após a remoção da override'
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
assert_log_count 'docker <compose> <--env-file> <.env.vps> <-f> <compose.yaml> <up> <-d> <--build>' 2 'deve tentar subir tanto o novo quanto o antigo'
assert_log 'alerta <DEPLOY QUEBRADO E REVERSÃO FALHOU: controle-bancario>' 'falha da reversão deve emitir alerta grave'
[ ! -e "$CASE_TMP/state/controle-bancario.commit" ] || fail 'falha da reversão não deve registrar SHA'
assert_no_log "mv <-f> <-->" 'falha da reversão não deve publicar arquivo de estado'
end_case 'falha também durante rollback alerta grave e não registra SHA novo'

printf '1..%d\n' "$TOTAL"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d de %d testes falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf '# %d testes passaram\n' "$TOTAL"
