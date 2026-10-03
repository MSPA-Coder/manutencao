#!/usr/bin/env bash
# Testes herméticos do `autocura.sh`, sem Docker e sem VPS.
#
# O QUE ESTÁ SOB TESTE é o critério de reinício. `unhealthy` nem sempre é
# sonda reprovada: o Docker marca assim, sem contar falha nenhuma, o contêiner
# pausado e o recém-despausado, até a sonda seguinte. O `backup-db.sh` pausa o
# Wealthfolio todo dia para copiar o SQLite, e reiniciar nessa janela derruba a
# cópia ao meio ou o aplicativo logo depois dela. Os casos:
#   - sonda reprovada de verdade: reinicia, avisa e conta a tentativa;
#   - pausado, ou recém-despausado antes da próxima sonda: não reinicia nem
#     avisa;
#   - pausado com a sonda já reprovando: não reinicia enquanto estiver pausado;
#   - um poupado não impede o reinício do doente de verdade ao lado.
#
# `docker`, `logger` e `alerta.sh` são scripts falsos, e o script exercitado é
# o mesmo arquivo que roda no servidor. As leituras do `docker` falso são as
# que o Docker 29.6.2 deu num contêiner de verdade: pausado ou recém-despausado,
# `unhealthy` com `FailingStreak` 0; com a sonda reprovando, `FailingStreak` 3.
#
# Uso:
#   docker run --rm -v "${PWD}:/repo:ro" bash:5.2 bash /repo/vps/tests/autocura_test.sh

set -u

# shellcheck disable=SC1007  # `CDPATH=` é prefixo de ambiente para um comando,
# não assinalamento com espaço sobrando. Mesmo motivo escrito em `instalar.sh`.
TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
AUTOCURA="$TESTS_DIR/../autocura.sh"
TOTAL=0
FAILED=0
CASE_FAILED=0
SUITE_TMP=$(mktemp -d)
trap 'rm -rf -- "$SUITE_TMP"' EXIT HUP INT TERM

fail() {
    printf '    FALHA: %s\n' "$1" >&2
    CASE_FAILED=1
}

assert_eq() {
    local esperado=$1 obtido=$2 descricao=$3
    [ "$obtido" = "$esperado" ] || fail "$descricao (esperado '$esperado', obtido '$obtido')"
}

begin_case() {
    CASE_FAILED=0
    CASE_TMP=$(mktemp -d "$SUITE_TMP/caso.XXXXXX")
    CHAMADAS="$CASE_TMP/chamadas.txt"
    ALERTAS="$CASE_TMP/alertas.txt"
    REGISTRO="$CASE_TMP/registro.txt"
    mkdir -p "$CASE_TMP/bin" "$CASE_TMP/estado"
    : >"$CASE_TMP/containers"
    : >"$CHAMADAS"
    : >"$ALERTAS"
    : >"$REGISTRO"
}

end_case() {
    TOTAL=$((TOTAL + 1))
    if [ "$CASE_FAILED" -ne 0 ]; then
        FAILED=$((FAILED + 1))
        printf 'not ok %d - %s\n' "$TOTAL" "$1"
    else
        printf 'ok %d - %s\n' "$TOTAL" "$1"
    fi
}

# Um contêiner em execução para o `docker` falso: nome, saúde, se está
# pausado e quantas sondas seguidas reprovaram.
conteiner() {
    printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >>"$CASE_TMP/containers"
}

instalar_falsos() {
    cat >"$CASE_TMP/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CHAMADAS"
case "$1" in
    ps)
        # Só a forma que o autocura usa: `--filter health=unhealthy`.
        while IFS='|' read -r nome saude _pausado _sequencia; do
            [ "$saude" = unhealthy ] && printf '%s\n' "$nome"
        done <"$CONTAINERS_FILE"
        exit 0
        ;;
    inspect)
        formato=$3 alvo=$4
        while IFS='|' read -r nome saude pausado sequencia; do
            [ "$nome" = "$alvo" ] || continue
            case "$formato" in
                *Paused*) printf '%s %s\n' "$pausado" "$sequencia" ;;
                *Health.Status*) printf '%s\n' "$saude" ;;
                *Health.Log*) printf 'saída da sonda\n' ;;
                *) exit 1 ;;
            esac
            exit 0
        done <"$CONTAINERS_FILE"
        echo "Error: No such object: $alvo" >&2
        exit 1
        ;;
    restart) exit 0 ;;
    *) exit 1 ;;
esac
EOF
    cat >"$CASE_TMP/bin/logger" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$REGISTRO"
EOF
    # Guarda só o título: é ele que diz qual aviso saiu.
    cat >"$CASE_TMP/bin/alerta.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$ALERTAS"
EOF
    chmod 755 "$CASE_TMP/bin/docker" "$CASE_TMP/bin/logger" "$CASE_TMP/bin/alerta.sh"
}

roda() {
    instalar_falsos
    CONTAINERS_FILE="$CASE_TMP/containers" CHAMADAS="$CHAMADAS" REGISTRO="$REGISTRO" \
        ALERTAS="$ALERTAS" ALERTA="$CASE_TMP/bin/alerta.sh" ESTADO="$CASE_TMP/estado" \
        PATH="$CASE_TMP/bin:$PATH" \
        bash "$AUTOCURA" >"$CASE_TMP/saida.txt" 2>&1
    CODIGO=$?
}

reinicios() {
    grep -c '^restart ' "$CHAMADAS" || true
}

alertas() {
    grep -c . "$ALERTAS" || true
}

# ---------------------------------------------------------------------------

begin_case
conteiner controle-bancario-web-1 unhealthy false 3
roda
assert_eq 0 "$CODIGO" 'o ciclo sai com sucesso'
assert_eq 1 "$(reinicios)" 'o doente de verdade é reiniciado uma vez'
grep -Fxq 'restart controle-bancario-web-1' "$CHAMADAS" \
    || fail 'o reinício vai para o contêiner doente'
grep -Fxq 'REINICIADO: controle-bancario-web-1' "$ALERTAS" \
    || fail 'o reinício é avisado'
assert_eq 1 "$(cat "$CASE_TMP/estado/controle-bancario-web-1" 2>/dev/null)" \
    'a tentativa é contada para o teto'
end_case 'sonda reprovada de verdade: reinicia, avisa e conta a tentativa'

begin_case
conteiner wealthfolio-teste-wealthfolio-1 unhealthy true 0
roda
assert_eq 0 "$CODIGO" 'o ciclo sai com sucesso'
assert_eq 0 "$(reinicios)" 'o contêiner pausado não é reiniciado'
assert_eq 0 "$(alertas)" 'nada é avisado'
grep -Fq 'wealthfolio-teste-wealthfolio-1 unhealthy, mas não reinicia: pausado' "$REGISTRO" \
    || fail 'o motivo de poupar fica no journal'
end_case 'pausado para o backup: não reinicia nem avisa'

begin_case
conteiner wealthfolio-teste-wealthfolio-1 unhealthy false 0
roda
assert_eq 0 "$(reinicios)" 'o recém-despausado não é reiniciado'
assert_eq 0 "$(alertas)" 'nada é avisado'
[ -e "$CASE_TMP/estado/wealthfolio-teste-wealthfolio-1" ] \
    && fail 'nenhuma tentativa é contada para o teto'
end_case 'recém-despausado, antes da próxima sonda: não reinicia nem avisa'

begin_case
conteiner wealthfolio-teste-wealthfolio-1 unhealthy true 3
roda
assert_eq 0 "$(reinicios)" 'contêiner pausado não é reiniciado nem com a sonda reprovando'
assert_eq 0 "$(alertas)" 'nada é avisado enquanto ele está pausado'
end_case 'pausado com a sonda já reprovando: não reinicia enquanto pausado'

begin_case
conteiner wealthfolio-teste-wealthfolio-1 unhealthy false 0
conteiner controle-renda-variavel-web-1 unhealthy false 3
conteiner controle-bancario-web-1 healthy false 0
roda
assert_eq 1 "$(reinicios)" 'só um contêiner é reiniciado'
grep -Fxq 'restart controle-renda-variavel-web-1' "$CHAMADAS" \
    || fail 'o reiniciado é o doente de verdade'
end_case 'um poupado não impede o reinício do doente de verdade ao lado'

printf '\n%d caso(s), %d falha(s)\n' "$TOTAL" "$FAILED"
[ "$FAILED" -eq 0 ]
