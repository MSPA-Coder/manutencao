#!/usr/bin/env bash
# Testes herméticos do `expurgo-contatos.sh`, sem Docker, sem portal e sem VPS.
#
# O QUE ESTÁ SOB TESTE é a descoberta e os dois sentidos do vazio:
#   - máquina sem portal (nenhum checkout com o comando) sai com sucesso e não
#     chama `docker exec`;
#   - portal presente e contêiner web em execução: o expurgo roda no contêiner
#     do projeto certo, e só nele;
#   - portal presente e SEM contêiner: falha — é o caso em que o prazo de
#     retenção deixaria de ser cumprido em silêncio;
#   - expurgo que falha dentro do contêiner: falha também.
#
# `docker` e `logger` são scripts falsos no PATH, e o script exercitado é o
# mesmo arquivo que roda no servidor.
#
# Uso:
#   docker run --rm -v "${PWD}:/repo:ro" bash:5.2 bash /repo/vps/tests/expurgo-contatos_test.sh

set -u

# shellcheck disable=SC1007  # `CDPATH=` é prefixo de ambiente para um comando,
# não assinalamento com espaço sobrando. Mesmo motivo escrito em `instalar.sh`.
TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
EXPURGO="$TESTS_DIR/../expurgo-contatos.sh"
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

# Um checkout em ~/apps. Com `portal`, ele traz o comando de expurgo.
checkout() {
    local nome=$1 tipo=${2:-}
    mkdir -p "$CASE_TMP/apps/$nome"
    if [ "$tipo" = portal ]; then
        mkdir -p "$CASE_TMP/apps/$nome/contatos/management/commands"
        : >"$CASE_TMP/apps/$nome/contatos/management/commands/expurgar_contatos.py"
    fi
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
        # Sem isto, o status da última comparação falsa do laço vazaria.
        exit 0
        ;;
    exec)
        printf '0 contato(s) apagados pela retencao de 730 dias.\n'
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
        bash "$EXPURGO" >"$SAIDA" 2>&1
    CODIGO=$?
}

execs() {
    grep -c '^exec ' "$CHAMADAS" || true
}

# ---------------------------------------------------------------------------

begin_case
checkout controle-bancario
em_execucao controle-bancario-web-1 controle-bancario web
roda
assert_eq 0 "$CODIGO" 'máquina sem portal sai com sucesso'
assert_eq 0 "$(execs)" 'máquina sem portal não chama docker exec'
assert_saida 'nenhum aplicativo com expurgo' 'máquina sem portal diz que não havia o que fazer'
end_case 'sem portal na máquina: sucesso, sem expurgo'

begin_case
checkout mp-portal portal
checkout controle-bancario
em_execucao mp-portal-web-1 mp-portal web
em_execucao mp-portal-postgres-1 mp-portal postgres
em_execucao controle-bancario-web-1 controle-bancario web
roda
assert_eq 0 "$CODIGO" 'portal com contêiner web sai com sucesso'
assert_eq 1 "$(execs)" 'o expurgo roda uma vez'
grep -Fq 'exec mp-portal-web-1 python manage.py expurgar_contatos' "$CHAMADAS" \
    || fail 'o expurgo roda no contêiner web do portal'
grep -Fq 'exec controle-bancario-web-1' "$CHAMADAS" \
    && fail 'o expurgo não pode rodar em aplicativo sem o comando'
assert_saida 'mp-portal: 0 contato(s) apagados' 'a saída do comando é registrada'
end_case 'portal em execução: expurga no contêiner web do portal'

begin_case
checkout mp-portal portal
em_execucao mp-portal-postgres-1 mp-portal postgres
roda
assert_eq 1 "$CODIGO" 'portal sem contêiner web é falha'
assert_eq 0 "$(execs)" 'sem contêiner, nada é executado'
assert_saida 'nenhum contêiner web em execução' 'a falha diz o motivo'
end_case 'portal presente sem contêiner web: falha alto'

begin_case
checkout mp-portal portal
em_execucao mp-portal-web-1 mp-portal web
EXEC_SAIDA=1
roda
assert_eq 1 "$CODIGO" 'expurgo que falha no contêiner é falha'
assert_saida 'o expurgo falhou' 'a falha do comando é registrada'
end_case 'expurgo que falha dentro do contêiner: falha'

begin_case
checkout mp-portal portal
em_execucao mp-portal-web-1 mp-portal web
DOCKER_PS_FALHA=1
roda
assert_eq 1 "$CODIGO" 'Docker indisponível é falha'
assert_eq 0 "$(execs)" 'sem consultar o Docker, nada é executado'
assert_saida 'não foi possível consultar o Docker' 'a falha diz o motivo'
end_case 'Docker indisponível: falha com o motivo'

printf '\n%d caso(s), %d falha(s)\n' "$TOTAL" "$FAILED"
[ "$FAILED" -eq 0 ]
