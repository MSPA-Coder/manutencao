#!/usr/bin/env bash
# Testa a descoberta de atualizações, o backup anterior e a sequência de deploys.

set -u

# shellcheck disable=SC1007
TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPT="$TESTS_DIR/../atualizar-stacks.sh"
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
    grep -Fq -- "$1" "$CALL_LOG" || fail "$2 (ausente: $1)"
}

assert_no_log() {
    if grep -Fq -- "$1" "$CALL_LOG"; then fail "$2 (encontrado: $1)"; fi
}

begin_case() {
    TOTAL=$((TOTAL + 1))
    CASE_FAILED=0
    CASE_TMP="$SUITE_TMP/case-$TOTAL"
    CALL_LOG="$CASE_TMP/calls.log"
    UPDATE_PROJECT=
    BACKUP_FAIL=0
    DEPLOY_FAIL=
    mkdir -p "$CASE_TMP/bin" "$CASE_TMP/apps" "$CASE_TMP/state"
    : >"$CALL_LOG"
    for dir in mega-sena conforto-termico controle-bancario controle-renda-variavel wealthfolio-teste; do
        mkdir -p "$CASE_TMP/apps/$dir/.git"
    done

    cat >"$CASE_TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'git' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
dir=${2##*/}
case " ${*:3} " in
    *' rev-parse HEAD '*)
        printf '%s\n' "$OLD_SHA" ;;
    *' ls-remote --exit-code origin refs/heads/main '*)
        if [ "${UPDATE_PROJECT:-}" = "$dir" ]; then printf '%s\trefs/heads/main\n' "$NEW_SHA"; else printf '%s\trefs/heads/main\n' "$OLD_SHA"; fi ;;
    *) printf 'git fake: comando inesperado: %s\n' "$*" >&2; exit 90 ;;
esac
EOF
    cat >"$CASE_TMP/bin/backup-db.sh" <<'EOF'
#!/usr/bin/env bash
printf 'backup' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
[ "${BACKUP_FAIL:-0}" != 1 ]
EOF
    cat >"$CASE_TMP/bin/deploy.sh" <<'EOF'
#!/usr/bin/env bash
printf 'deploy' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
[ "${DEPLOY_FAIL:-}" != "${1:-}" ]
EOF
    cat >"$CASE_TMP/bin/alerta.sh" <<'EOF'
#!/usr/bin/env bash
printf 'alerta' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
EOF
    cat >"$CASE_TMP/bin/flock" <<'EOF'
#!/usr/bin/env bash
printf 'flock' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
exit 0
EOF
    chmod +x "$CASE_TMP/bin/"*
}

run_script() {
    set +e
    PATH="$CASE_TMP/bin:$PATH" APPS="$CASE_TMP/apps" \
    DEPLOY="$CASE_TMP/bin/deploy.sh" BACKUP="$CASE_TMP/bin/backup-db.sh" \
    ALERTA="$CASE_TMP/bin/alerta.sh" LOCK_FILE="$CASE_TMP/state/lock" \
    CALL_LOG="$CALL_LOG" OLD_SHA=1111111111111111111111111111111111111111 \
    NEW_SHA=2222222222222222222222222222222222222222 \
    UPDATE_PROJECT="${UPDATE_PROJECT:-}" BACKUP_FAIL="${BACKUP_FAIL:-0}" \
    DEPLOY_FAIL="${DEPLOY_FAIL:-}" bash "$SCRIPT" "$@" >"$CASE_TMP/output" 2>&1
    EXIT_CODE=$?
    set -e
}

end_case() {
    if [ "$CASE_FAILED" -eq 0 ]; then
        printf 'ok %d - %s\n' "$TOTAL" "$1"
    else
        printf 'not ok %d - %s\n' "$TOTAL" "$1"
        sed 's/^/    | /' "$CASE_TMP/output" >&2
        FAILED=$((FAILED + 1))
    fi
}

set -e
printf 'TAP version 13\n'

begin_case
run_script
assert_eq 0 "$EXIT_CODE" 'sem alterações deve sair zero'
assert_no_log 'backup' 'sem alterações não deve refazer backup'
assert_no_log 'deploy' 'sem alterações não deve chamar deploy'
end_case 'main sem avanço não faz backup nem deploy'

begin_case
UPDATE_PROJECT=controle-renda-variavel
run_script
assert_eq 0 "$EXIT_CODE" 'commits novos devem ser processados'
assert_eq 1 "$(grep -c '^backup' "$CALL_LOG" || true)" 'deve validar um backup para o lote'
assert_eq 5 "$(grep -c '^deploy' "$CALL_LOG" || true)" 'deve verificar os cinco apps em série'
backup_line=$(grep -n '^backup' "$CALL_LOG" | cut -d: -f1)
first_deploy_line=$(grep -n '^deploy' "$CALL_LOG" | head -1 | cut -d: -f1)
[ "$backup_line" -lt "$first_deploy_line" ] || fail 'backup precisa terminar antes do primeiro deploy'
assert_log 'deploy <megasena>' 'Mega-Sena deve ser o primeiro app'
assert_log 'deploy <wealthfolio>' 'Wealthfolio deve ser o último app'
end_case 'commit novo exige backup e percorre os apps na ordem definida'

begin_case
UPDATE_PROJECT=mega-sena
BACKUP_FAIL=1
run_script
assert_eq 1 "$EXIT_CODE" 'backup inválido deve falhar'
assert_no_log 'deploy' 'backup inválido deve impedir qualquer deploy'
assert_log 'alerta <AUTO-DEPLOY ABORTADO: BACKUP FALHOU>' 'backup inválido deve alertar'
end_case 'backup inválido interrompe antes de tocar os stacks'

begin_case
run_script --refresh
assert_eq 0 "$EXIT_CODE" 'reconstrução semanal deve sair zero'
assert_eq 5 "$(grep -Fc '<--refresh>' "$CALL_LOG" || true)" 'refresh deve chegar a todos os apps'
assert_eq 1 "$(grep -c '^backup' "$CALL_LOG" || true)" 'refresh deve validar um backup'
end_case 'refresh semanal passa pelo backup e reconstrói todos os apps'

begin_case
UPDATE_PROJECT=mega-sena
DEPLOY_FAIL=megasena
run_script
assert_eq 1 "$EXIT_CODE" 'uma falha de deploy deve sair não zero'
assert_eq 5 "$(grep -c '^deploy' "$CALL_LOG" || true)" 'falha de um app não deve pular os demais'
assert_log 'alerta <AUTO-DEPLOY INCOMPLETO>' 'lote incompleto deve alertar'
end_case 'falha de um app é reportada depois de tentar os outros'

printf '1..%d\n' "$TOTAL"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d de %d testes falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf '# %d testes passaram\n' "$TOTAL"
