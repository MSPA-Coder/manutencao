#!/usr/bin/env bash
# Testes herméticos do instalador. Mesmo desenho do `deploy_test.sh`: os
# destinos vão para um diretório temporário, `git` e `systemctl` são comandos
# falsos no PATH, e nada toca o VPS nem a rede.
#
# O instalador exercitado é `vps/instalar.sh`, o mesmo arquivo que roda no
# servidor -- é para isso que ele lê os destinos do ambiente. Um teste que
# precisasse de uma cópia adaptada não responderia à pergunta que importa.

set -u

TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VPS_DIR=$(CDPATH= cd -- "$TESTS_DIR/.." && pwd)
INSTALAR="$VPS_DIR/instalar.sh"
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

# Quantos artefatos o inventário declara. Lido do próprio script, para o teste
# não precisar ser reeditado quando um artefato novo entrar -- e para reprovar
# se alguém remover o inventário inteiro.
total_do_inventario() {
    awk '/^INVENTARIO=\(/{dentro=1; next} dentro && /^\)/{exit} dentro && /\|/{n++} END{print n+0}' "$INSTALAR"
}

make_fakes() {
    mkdir -p "$CASE_TMP/bin" "$CASE_TMP/scripts" "$CASE_TMP/systemd"
    : >"$CASE_TMP/calls.log"
    printf 'limpo\n' >"$CASE_TMP/git-status"

    cat >"$CASE_TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'git' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
case "${3:-}" in
    status)
        # "sujo" no arquivo de cenário faz o fake reportar uma modificação.
        if [ "$(cat "$FAKE_GIT_STATUS")" = "sujo" ]; then printf ' M vps/deploy.sh\n'; fi
        exit 0 ;;
    rev-parse) printf 'abc1234\n' ;;
esac
exit 0
EOF

    cat >"$CASE_TMP/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
exit 0
EOF

    cat >"$CASE_TMP/bin/mv" <<'EOF'
#!/usr/bin/env bash
printf 'mv' >>"$CALL_LOG"; printf ' <%s>' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
exec /bin/mv "$@"
EOF
    chmod +x "$CASE_TMP/bin/"*
}

run_instalar() {
    set +e
    PATH="$CASE_TMP/bin:$PATH" \
    DESTINO_SCRIPTS="$CASE_TMP/scripts" DESTINO_SYSTEMD="$CASE_TMP/systemd" \
    SYSTEMCTL=systemctl SUDO= \
    CALL_LOG="$CASE_TMP/calls.log" FAKE_GIT_STATUS="$CASE_TMP/git-status" \
        bash "$1" ${2:-} >"$CASE_TMP/output" 2>&1
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

set -e
printf 'TAP version 13\n'
ESPERADOS=$(total_do_inventario)

# --------------------------------------------------------------------------
begin_case
run_instalar "$INSTALAR"
assert_eq 0 "$EXIT_CODE" 'instalação em destino vazio deve sair zero'
instalados=$(find "$CASE_TMP/scripts" "$CASE_TMP/systemd" -type f | wc -l | tr -d ' ')
assert_eq "$ESPERADOS" "$instalados" 'deve instalar todos os artefatos do inventário'
assert_eq 755 "$(stat -c '%a' "$CASE_TMP/scripts/deploy.sh")" 'script deve ficar 755'
assert_eq 644 "$(stat -c '%a' "$CASE_TMP/systemd/vigia.timer")" 'unidade deve ficar 644'
[ -f "$CASE_TMP/scripts/instalar-nginx.sh" ] || fail 'nginx/instalar.sh deve virar instalar-nginx.sh'
[ -f "$CASE_TMP/systemd/certbot.service.d/alerta.conf" ] || fail 'drop-in do certbot deve entrar em subdiretório'
assert_log 'systemctl <daemon-reload>' 'unidade nova deve recarregar o systemd'
assert_log 'systemctl <restart> <vigia.timer>' 'deve reiniciar o timer da unidade mudada'
assert_log_count 'systemctl <restart>' 4 'deve reiniciar os quatro timers, uma vez cada'
assert_log 'mv <-f> <-->' 'publicação deve terminar por rename atômico'
[ -z "$(find "$CASE_TMP/scripts" "$CASE_TMP/systemd" -name '.instalar.*' -print)" ] || fail 'rename atômico não deve deixar temporário'
grep -q '^OK: ' "$CASE_TMP/output" || fail 'deve confirmar a conferência final'
end_case 'instalação limpa entrega tudo, com modo e systemd recarregado'

# --------------------------------------------------------------------------
begin_case
run_instalar "$INSTALAR"
cp -R "$CASE_TMP/scripts/." "$SUITE_TMP/ja-instalado-scripts" 2>/dev/null || true
: >"$CALL_LOG"
run_instalar "$INSTALAR"
assert_eq 0 "$EXIT_CODE" 'segunda execução deve sair zero'
grep -q 'Nada a fazer' "$CASE_TMP/output" || fail 'segunda execução não deve ter o que instalar'
assert_no_log 'mv <-f> <-->' 'idempotente: não deve reescrever nada'
assert_no_log 'systemctl <daemon-reload>' 'idempotente: não deve recarregar o systemd'
end_case 'rodar de novo não reescreve nem recarrega nada'

# --------------------------------------------------------------------------
begin_case
run_instalar "$INSTALAR"
rm -f "$CASE_TMP/scripts/deploy.sh"
: >"$CALL_LOG"
run_instalar "$INSTALAR" --check
[ "$EXIT_CODE" -ne 0 ] || fail '--check com deriva deve sair não zero'
[ ! -f "$CASE_TMP/scripts/deploy.sh" ] || fail '--check não pode instalar nada'
assert_no_log 'mv <-f> <-->' '--check não deve escrever'
grep -q 'DIFERENTE' "$CASE_TMP/output" || fail '--check deve nomear o que está diferente'
end_case '--check acusa deriva sem escrever e sai não zero'

# --------------------------------------------------------------------------
begin_case
run_instalar "$INSTALAR"
: >"$CALL_LOG"
run_instalar "$INSTALAR" --check
assert_eq 0 "$EXIT_CODE" '--check em dia deve sair zero'
end_case '--check em dia sai zero'

# --------------------------------------------------------------------------
begin_case
printf 'sujo\n' >"$CASE_TMP/git-status"
run_instalar "$INSTALAR"
[ "$EXIT_CODE" -ne 0 ] || fail 'checkout sujo deve recusar a instalação'
assert_eq 0 "$(find "$CASE_TMP/scripts" -type f | wc -l | tr -d ' ')" 'checkout sujo não pode instalar nada'
grep -q 'não commitada' "$CASE_TMP/output" || fail 'deve explicar por que recusou'
end_case 'checkout sujo recusa instalar'

# --------------------------------------------------------------------------
begin_case
printf 'sujo\n' >"$CASE_TMP/git-status"
run_instalar "$INSTALAR" --check
[ "$EXIT_CODE" -ne 0 ] || fail '--check com deriva deve sair não zero mesmo com checkout sujo'
grep -q 'DIFERENTE' "$CASE_TMP/output" || fail '--check deve funcionar com checkout sujo'
grep -q 'não commitada' "$CASE_TMP/output" && fail '--check não deve exigir checkout limpo'
end_case '--check responde mesmo com checkout sujo'

# --------------------------------------------------------------------------
begin_case
run_instalar "$INSTALAR"
# Só um script volta a divergir: o systemd não pode ser mexido por causa disso.
printf 'diferente\n' >>"$CASE_TMP/scripts/alerta.sh"
: >"$CALL_LOG"
run_instalar "$INSTALAR"
assert_eq 0 "$EXIT_CODE" 'reinstalar um script deve sair zero'
assert_log_count 'mv <-f> <-->' 1 'deve reescrever somente o artefato divergente'
assert_no_log 'systemctl <daemon-reload>' 'mudança só em script não deve tocar o systemd'
end_case 'mudança em script não recarrega o systemd'

# --------------------------------------------------------------------------
# O guarda de CR precisa de um fonte corrompido, e o checkout é somente leitura
# na execução documentada. A cópia abaixo é byte a byte a mesma do repositório
# -- o que muda é o arquivo de dados que ela lê.
begin_case
COPIA="$CASE_TMP/vps"
mkdir -p "$COPIA"
cp -R "$VPS_DIR/." "$COPIA/"
printf 'x\r\n' >>"$COPIA/alerta.sh"
run_instalar "$COPIA/instalar.sh"
[ "$EXIT_CODE" -ne 0 ] || fail 'fonte com CR deve recusar'
grep -q 'contém CR' "$CASE_TMP/output" || fail 'deve dizer que o problema é CR'
end_case 'fonte com CR é recusado em vez de instalar shebang quebrado'

printf '1..%d\n' "$TOTAL"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d de %d testes falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf '# %d testes passaram\n' "$TOTAL"
