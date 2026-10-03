#!/usr/bin/env bash
# Testes herméticos do `cotacoes-diarias.sh`, sem Docker, sem CRV e sem VPS.
#
# O QUE ESTÁ SOB TESTE é a descoberta e os vazios que não são iguais:
#   - máquina sem o CRV (nenhum checkout com o importador) sai com sucesso e não
#     chama `docker exec`;
#   - CRV com `--estrito` e contêiner web em execução: a importação roda no
#     contêiner do projeto certo, e só nele, com `--estrito`;
#   - CRV cujo comando ainda não aceita `--estrito`: falha, sem rodar o comando
#     sem a opção -- rodar assim esconderia o Yahoo fora do ar;
#   - CRV sem contêiner web: falha, porque a série deixaria de ser mantida em
#     silêncio;
#   - importação que reprova dentro do contêiner, e Docker indisponível: falha.
#
# `docker` e `logger` são scripts falsos no PATH, e o script exercitado é o
# mesmo arquivo que roda no servidor.
#
# Uso:
#   docker run --rm -v "${PWD}:/repo:ro" bash:5.2 bash /repo/vps/tests/cotacoes-diarias_test.sh

set -u

# shellcheck disable=SC1007  # `CDPATH=` é prefixo de ambiente para um comando,
# não assinalamento com espaço sobrando. Mesmo motivo escrito em `instalar.sh`.
TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
COTACOES="$TESTS_DIR/../cotacoes-diarias.sh"
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

assert_saida() {
    local padrao=$1 descricao=$2
    grep -Fq -- "$padrao" "$SAIDA" || fail "$descricao (ausente: $padrao)"
}

begin_case() {
    CASE_FAILED=0
    CASE_TMP=$(mktemp -d "$SUITE_TMP/caso.XXXXXX")
    SAIDA="$CASE_TMP/saida.txt"
    CHAMADAS="$CASE_TMP/chamadas.txt"
    mkdir -p "$CASE_TMP/apps" "$CASE_TMP/bin"
    : >"$CASE_TMP/containers"
    : >"$CHAMADAS"
    EXEC_SAIDA=0
    DOCKER_PS_FALHA=0
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

# Um checkout em ~/apps. `crv` traz o importador e um comando que aceita
# `--estrito`; `crv-antigo` traz o importador e um comando sem a opção.
checkout() {
    local nome=$1 tipo=${2:-}
    mkdir -p "$CASE_TMP/apps/$nome"
    case "$tipo" in
        crv|crv-antigo)
            mkdir -p "$CASE_TMP/apps/$nome/app/quotes"
            : >"$CASE_TMP/apps/$nome/app/quotes/history_import.py"
            if [ "$tipo" = crv ]; then
                printf '@click.option(\n    "--estrito",\n    is_flag=True,\n)\n' \
                    >"$CASE_TMP/apps/$nome/app/cli.py"
            else
                printf '@click.command("import-position-history")\n' \
                    >"$CASE_TMP/apps/$nome/app/cli.py"
            fi
            ;;
    esac
}

# Um contêiner em execução para o `docker` falso: nome, projeto e serviço.
em_execucao() {
    printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$CASE_TMP/containers"
}

instalar_falsos() {
    cat >"$CASE_TMP/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CHAMADAS"
case "$1" in
    ps)
        [ "$DOCKER_PS_FALHA" = 1 ] && exit 1
        projeto=""; servico=""
        while [ "$#" -gt 0 ]; do
            case "$2" in
                label=com.docker.compose.project=*) projeto=${2#label=com.docker.compose.project=} ;;
                label=com.docker.compose.service=*) servico=${2#label=com.docker.compose.service=} ;;
            esac
            shift
        done
        while IFS='|' read -r nome proj serv; do
            [ "$proj" = "$projeto" ] && [ "$serv" = "$servico" ] && printf '%s\n' "$nome"
        done <"$CONTAINERS_FILE"
        # O `docker ps` real sai com zero mesmo sem nenhum contêiner casando.
        exit 0
        ;;
    exec)
        printf '1234 daily quotes imported for 9 tickers.\n'
        if [ "$EXEC_SAIDA" != 0 ]; then
            printf 'Error: Ainda detidos ou de referência, sem série: PETR4\n' >&2
        fi
        exit "$EXEC_SAIDA"
        ;;
    *) exit 1 ;;
esac
EOF
    printf '#!/usr/bin/env bash\nexit 0\n' >"$CASE_TMP/bin/logger"
    chmod 755 "$CASE_TMP/bin/docker" "$CASE_TMP/bin/logger"
}

roda() {
    instalar_falsos
    CONTAINERS_FILE="$CASE_TMP/containers" CHAMADAS="$CHAMADAS" EXEC_SAIDA="$EXEC_SAIDA" \
        DOCKER_PS_FALHA="$DOCKER_PS_FALHA" \
        DIR_APPS="$CASE_TMP/apps" PATH="$CASE_TMP/bin:$PATH" \
        bash "$COTACOES" >"$SAIDA" 2>&1
    CODIGO=$?
}

execs() {
    grep -c '^exec ' "$CHAMADAS" || true
}

# ---------------------------------------------------------------------------

begin_case
checkout controle-bancario
checkout mp-portal
em_execucao controle-bancario-web-1 controle-bancario web
roda
assert_eq 0 "$CODIGO" 'máquina sem o CRV sai com sucesso'
assert_eq 0 "$(execs)" 'máquina sem o CRV não chama docker exec'
assert_saida 'nenhum aplicativo com importador de cotações' 'a saída diz que não havia o que fazer'
end_case 'sem CRV na máquina: sucesso, sem importação'

begin_case
checkout controle-renda-variavel crv
checkout controle-bancario
em_execucao controle-renda-variavel-web-1 controle-renda-variavel web
em_execucao controle-renda-variavel-db-1 controle-renda-variavel db
em_execucao controle-bancario-web-1 controle-bancario web
roda
assert_eq 0 "$CODIGO" 'CRV com contêiner web sai com sucesso'
assert_eq 1 "$(execs)" 'a importação roda uma vez'
grep -Fq 'exec controle-renda-variavel-web-1 flask --app app:create_app import-position-history --estrito' "$CHAMADAS" \
    || fail 'a importação roda no contêiner web do CRV, com --estrito'
grep -Fq 'exec controle-bancario-web-1' "$CHAMADAS" \
    && fail 'a importação não pode rodar em aplicativo sem o importador'
assert_saida 'controle-renda-variavel: 1234 daily quotes imported' 'a saída do comando é registrada'
end_case 'CRV em execução: importa no contêiner web, com --estrito'

begin_case
checkout controle-renda-variavel crv-antigo
em_execucao controle-renda-variavel-web-1 controle-renda-variavel web
roda
assert_eq 1 "$CODIGO" 'comando sem --estrito é falha'
assert_eq 0 "$(execs)" 'sem --estrito, o comando não roda de jeito nenhum'
assert_saida 'ainda não aceita --estrito' 'a falha pede o deploy do CRV'
end_case 'CRV sem --estrito: falha sem rodar a versão que esconde o erro'

begin_case
checkout controle-renda-variavel crv
em_execucao controle-renda-variavel-db-1 controle-renda-variavel db
roda
assert_eq 1 "$CODIGO" 'CRV sem contêiner web é falha'
assert_eq 0 "$(execs)" 'sem contêiner, nada é executado'
assert_saida 'nenhum contêiner web em execução' 'a falha diz o motivo'
end_case 'CRV presente sem contêiner web: falha alto'

begin_case
checkout controle-renda-variavel crv
em_execucao controle-renda-variavel-web-1 controle-renda-variavel web
EXEC_SAIDA=1
roda
assert_eq 1 "$CODIGO" 'importação que reprova no contêiner é falha'
assert_saida 'a importação falhou' 'a falha do comando é registrada'
assert_saida 'sem série: PETR4' 'a saída do comando entra no registro, com o ticker que faltou'
end_case 'importação que reprova dentro do contêiner: falha'

begin_case
checkout controle-renda-variavel crv
em_execucao controle-renda-variavel-web-1 controle-renda-variavel web
DOCKER_PS_FALHA=1
roda
assert_eq 1 "$CODIGO" 'Docker indisponível é falha'
assert_eq 0 "$(execs)" 'sem consultar o Docker, nada é executado'
assert_saida 'não foi possível consultar o Docker' 'a falha diz o motivo'
end_case 'Docker indisponível: falha com o motivo'

printf '\n%d caso(s), %d falha(s)\n' "$TOTAL" "$FAILED"
[ "$FAILED" -eq 0 ]
