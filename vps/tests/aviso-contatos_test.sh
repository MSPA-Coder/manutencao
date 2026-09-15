#!/usr/bin/env bash
# Testes herméticos do `aviso-contatos.sh`, sem Docker, sem portal, sem
# Telegram e sem VPS.
#
# O QUE ESTÁ SOB TESTE:
#   - a descoberta e os sentidos do vazio, como no expurgo: máquina sem portal
#     sai com sucesso; portal sem contêiner web é falha;
#   - o estado: a primeira execução só inicializa, sem avisar sobre o que já
#     estava na lista; as seguintes passam o instante de volta como `--desde`;
#   - o aviso: sai com contagem maior que zero, com título que diferencia um de
#     vários, e com `ALERTA_JANELA=0` -- senão dois pedidos avulsos em menos de
#     15 minutos teriam o mesmo título e o segundo seria engolido;
#   - a falha não anda o estado: o que chegou enquanto o comando falhava é
#     contado no primeiro ciclo que der certo;
#   - só a saída padrão do comando é lida.
#
# `docker`, `logger` e o `alerta.sh` são scripts falsos, e o script exercitado
# é o mesmo arquivo que roda no servidor.
#
# Uso:
#   docker run --rm -v "${PWD}:/repo:ro" bash:5.2 bash /repo/vps/tests/aviso-contatos_test.sh

set -u

# shellcheck disable=SC1007  # `CDPATH=` é prefixo de ambiente para um comando,
# não assinalamento com espaço sobrando. Mesmo motivo escrito em `instalar.sh`.
TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
AVISO="$TESTS_DIR/../aviso-contatos.sh"
TOTAL=0
FAILED=0
CASE_FAILED=0
SUITE_TMP=$(mktemp -d)
trap 'rm -rf -- "$SUITE_TMP"' EXIT HUP INT TERM

ANTES="2026-09-15T12:00:00+00:00"
DEPOIS="2026-09-15T12:14:10.123456+00:00"

fail() {
    printf '    FALHA: %s\n' "$1" >&2
    CASE_FAILED=1
}

assert_eq() {
    local esperado=$1 obtido=$2 descricao=$3
    [ "$obtido" = "$esperado" ] || fail "$descricao (esperado '$esperado', obtido '$obtido')"
}

assert_arquivo() {
    local arquivo=$1 padrao=$2 descricao=$3
    grep -Fq -- "$padrao" "$arquivo" || fail "$descricao (ausente: $padrao)"
}

begin_case() {
    CASE_FAILED=0
    CASE_TMP=$(mktemp -d "$SUITE_TMP/caso.XXXXXX")
    SAIDA="$CASE_TMP/saida.txt"
    CHAMADAS="$CASE_TMP/chamadas.txt"
    ALERTAS="$CASE_TMP/alertas.txt"
    ESTADO="$CASE_TMP/estado"
    mkdir -p "$CASE_TMP/apps" "$CASE_TMP/bin" "$ESTADO"
    : >"$CASE_TMP/containers"
    : >"$CHAMADAS"
    : >"$ALERTAS"
    printf 'novos=0\nate=%s\n' "$DEPOIS" >"$CASE_TMP/resposta"
    EXEC_SAIDA=0
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

# Um checkout em ~/apps. Com `portal`, ele traz o comando do aviso.
checkout() {
    local nome=$1 tipo=${2:-}
    mkdir -p "$CASE_TMP/apps/$nome"
    if [ "$tipo" = portal ]; then
        mkdir -p "$CASE_TMP/apps/$nome/contatos/management/commands"
        : >"$CASE_TMP/apps/$nome/contatos/management/commands/contatos_novos.py"
    fi
}

em_execucao() {
    printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$CASE_TMP/containers"
}

responde() {
    printf '%s\n' "$@" >"$CASE_TMP/resposta"
}

instalar_falsos() {
    cat >"$CASE_TMP/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CHAMADAS"
case "$1" in
    ps)
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
        exit 0
        ;;
    exec)
        # Uma chave falsa na saída de erro: o script não pode lê-la.
        printf 'novos=99\n' >&2
        cat "$RESPOSTA_FILE"
        exit "$EXEC_SAIDA"
        ;;
    *) exit 1 ;;
esac
EOF
    cat >"$CASE_TMP/bin/alerta.sh" <<'EOF'
#!/usr/bin/env bash
printf 'TITULO=%s\n' "$1" >>"$ALERTAS"
printf 'JANELA=%s\n' "${ALERTA_JANELA:-padrao}" >>"$ALERTAS"
printf 'CORPO=%s\n' "${2:-}" >>"$ALERTAS"
exit 0
EOF
    printf '#!/usr/bin/env bash\nexit 0\n' >"$CASE_TMP/bin/logger"
    chmod 755 "$CASE_TMP/bin/docker" "$CASE_TMP/bin/alerta.sh" "$CASE_TMP/bin/logger"
}

roda() {
    instalar_falsos
    CONTAINERS_FILE="$CASE_TMP/containers" RESPOSTA_FILE="$CASE_TMP/resposta" \
        CHAMADAS="$CHAMADAS" ALERTAS="$ALERTAS" EXEC_SAIDA="$EXEC_SAIDA" \
        DIR_APPS="$CASE_TMP/apps" ESTADO_DIR="$ESTADO" \
        ALERTA="$CASE_TMP/bin/alerta.sh" PATH="$CASE_TMP/bin:$PATH" \
        bash "$AVISO" >"$SAIDA" 2>&1
    CODIGO=$?
}

execs() { grep -c '^exec ' "$CHAMADAS" || true; }
alertas() { grep -c '^TITULO=' "$ALERTAS" || true; }
estado_de() { cat "$ESTADO/$1.desde" 2>/dev/null || printf '(sem estado)'; }

portal_no_ar() {
    checkout mp-portal portal
    checkout controle-bancario
    em_execucao mp-portal-web-1 mp-portal web
    em_execucao mp-portal-postgres-1 mp-portal postgres
    em_execucao controle-bancario-web-1 controle-bancario web
}

# ---------------------------------------------------------------------------

begin_case
checkout controle-bancario
em_execucao controle-bancario-web-1 controle-bancario web
roda
assert_eq 0 "$CODIGO" 'máquina sem portal sai com sucesso'
assert_eq 0 "$(execs)" 'máquina sem portal não chama docker exec'
assert_eq 0 "$(alertas)" 'máquina sem portal não avisa'
assert_arquivo "$SAIDA" 'nenhum aplicativo com aviso de chegada' 'diz que não havia o que fazer'
end_case 'sem portal na máquina: sucesso, sem aviso'

begin_case
portal_no_ar
responde "novos=0" "ate=$DEPOIS"
roda
assert_eq 0 "$CODIGO" 'a primeira execução sai com sucesso'
assert_arquivo "$CHAMADAS" 'exec mp-portal-web-1 python manage.py contatos_novos' 'roda no contêiner web do portal'
grep -Fq -- '--desde' "$CHAMADAS" && fail 'sem estado, a chamada não pode levar --desde'
grep -Fq 'exec controle-bancario-web-1' "$CHAMADAS" && fail 'não roda em aplicativo sem o comando'
assert_eq 0 "$(alertas)" 'a primeira execução não avisa'
assert_eq "$DEPOIS" "$(estado_de mp-portal)" 'a primeira execução grava o instante'
end_case 'primeira execução: inicializa o estado sem avisar'

begin_case
portal_no_ar
printf '%s\n' "$ANTES" >"$ESTADO/mp-portal.desde"
responde "novos=0" "ate=$ANTES"
roda
assert_eq 0 "$CODIGO" 'sem pedido novo sai com sucesso'
assert_arquivo "$CHAMADAS" "contatos_novos --desde $ANTES" 'o estado volta como --desde'
assert_eq 0 "$(alertas)" 'sem pedido novo, sem aviso (a saída de erro dizia novos=99)'
assert_eq "$ANTES" "$(estado_de mp-portal)" 'sem pedido novo, o estado fica'
end_case 'sem pedido novo: não avisa, e só a saída padrão conta'

begin_case
portal_no_ar
printf '%s\n' "$ANTES" >"$ESTADO/mp-portal.desde"
responde "novos=2" "ate=$DEPOIS"
roda
assert_eq 0 "$CODIGO" 'com pedido novo sai com sucesso'
assert_eq 1 "$(alertas)" 'um aviso por ciclo'
assert_arquivo "$ALERTAS" 'TITULO=PORTAL: 2 solicitações novas' 'o título diz quantos'
assert_arquivo "$ALERTAS" 'JANELA=0' 'o antirrepetição do alerta.sh fica desligado'
assert_arquivo "$ALERTAS" '/painel/atendimento/' 'o corpo diz onde atender'
assert_eq "$DEPOIS" "$(estado_de mp-portal)" 'o estado anda para o pedido mais recente'
end_case 'dois pedidos novos: avisa e anda o estado'

begin_case
portal_no_ar
printf '%s\n' "$ANTES" >"$ESTADO/mp-portal.desde"
responde "novos=1" "ate=$DEPOIS"
roda
assert_arquivo "$ALERTAS" 'TITULO=PORTAL: 1 solicitação nova' 'singular para um pedido'
end_case 'um pedido novo: título no singular'

begin_case
checkout mp-portal portal
em_execucao mp-portal-postgres-1 mp-portal postgres
printf '%s\n' "$ANTES" >"$ESTADO/mp-portal.desde"
roda
assert_eq 1 "$CODIGO" 'portal sem contêiner web é falha'
assert_eq 0 "$(execs)" 'sem contêiner, nada é executado'
assert_arquivo "$SAIDA" 'nenhum contêiner web em execução' 'a falha diz o motivo'
assert_eq "$ANTES" "$(estado_de mp-portal)" 'sem contêiner, o estado não anda'
end_case 'portal sem contêiner web: falha alto'

begin_case
portal_no_ar
printf '%s\n' "$ANTES" >"$ESTADO/mp-portal.desde"
responde "novos=3" "ate=$DEPOIS"
EXEC_SAIDA=1
roda
assert_eq 1 "$CODIGO" 'comando que falha é falha'
assert_eq 0 "$(alertas)" 'comando que falha não avisa'
assert_arquivo "$SAIDA" 'contatos_novos falhou' 'a falha é registrada'
assert_eq "$ANTES" "$(estado_de mp-portal)" 'comando que falha não anda o estado'
end_case 'comando que falha: falha, sem andar o estado'

begin_case
portal_no_ar
printf '%s\n' "$ANTES" >"$ESTADO/mp-portal.desde"
responde "Traceback (most recent call last):" "algo inesperado"
roda
assert_eq 1 "$CODIGO" 'saída sem as chaves é falha'
assert_eq 0 "$(alertas)" 'saída ilegível não avisa'
assert_arquivo "$SAIDA" 'ilegível' 'a falha diz o motivo'
assert_eq "$ANTES" "$(estado_de mp-portal)" 'saída ilegível não anda o estado'
end_case 'saída ilegível: falha, sem andar o estado'

printf '1..%d\n' "$TOTAL"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d de %d testes falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf '# %d testes passaram\n' "$TOTAL"
