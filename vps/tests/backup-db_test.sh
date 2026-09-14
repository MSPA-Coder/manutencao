#!/usr/bin/env bash
# Testes herméticos da DESCOBERTA de bancos do `backup-db.sh`, sem Docker, sem
# Postgres e sem VPS.
#
# POR QUE ESTE ARQUIVO EXISTE. Até 13/09/2026 os bancos eram um vetor escrito à
# mão dentro do script, e o `backup-agent.sh` tinha um segundo vetor com a mesma
# intenção. O do agente ficou sem o `mp_portal` quando o portal entrou em
# produção: o dump era feito todo dia e nenhum deles podia ser baixado, por três
# dias, sem nada acusar. A correção foi parar de declarar a lista e passar a
# descobri-la do Docker — o que troca um erro de digitação por um erro de
# lógica, e erro de lógica é o que teste pega.
#
# O QUE ESTÁ SOB TESTE, e por que cada caso importa:
#   - o critério da imagem `postgres:*` (e não "tem pg_dump dentro", que no VPS
#     real aprova dois contêineres do ConfortoTermico que não são banco);
#   - a guarda de descoberta vazia, que é a diferença entre "não salvei nada" e
#     "não salvei nada e disse que deu certo" -- o modo de falha que um backup
#     não pode ter;
#   - o aviso de banco desaparecido, que é o único caso que a descoberta
#     sozinha não enxerga (contêiner parado não aparece em `docker ps`).
#
# O `docker` é um script falso no PATH, não um parâmetro do script sob teste:
# assim o `backup-db.sh` exercitado aqui é literalmente o que roda no servidor,
# chamando `docker` pelo nome, como lá.
#
# Uso:
#   docker run --rm -v "${PWD}:/repo:ro" bash:5.2 bash /repo/vps/tests/backup-db_test.sh

set -u

# shellcheck disable=SC1007  # `CDPATH=` é prefixo de ambiente para um comando,
# não assinalamento com espaço sobrando. Mesmo motivo escrito em `instalar.sh`.
TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BACKUP_DB="$TESTS_DIR/../backup-db.sh"
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

assert_sem_saida() {
    local padrao=$1 descricao=$2
    grep -Fq -- "$padrao" "$SAIDA" && fail "$descricao (presente: $padrao)"
    return 0
}

begin_case() {
    CASE_FAILED=0
    CASE_TMP=$(mktemp -d "$SUITE_TMP/caso.XXXXXX")
    DEST_TMP="$CASE_TMP/backups"
    SAIDA="$CASE_TMP/saida.txt"
    mkdir -p "$DEST_TMP" "$CASE_TMP/bin"
    : >"$CASE_TMP/containers"
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

# Declara um contêiner para o `docker` falso: nome, imagem e projeto do Compose.
contêiner() {
    printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$CASE_TMP/containers"
}

# `docker` falso. Cobre só os três subcomandos que o script usa, e o `exec`
# devolve valores plausíveis para que o ciclo chegue até o fim sem Postgres.
instalar_docker_falso() {
    cat >"$CASE_TMP/bin/docker" <<'EOF'
#!/usr/bin/env bash
LISTA="$CONTAINERS_FILE"

case "$1" in
    ps)
        cut -d'|' -f1 "$LISTA"
        ;;
    inspect)
        # `-f <formato> <nome>`
        formato="$2"; [ "$formato" = "-f" ] && { formato="$3"; nome="$4"; } || nome="$3"
        linha=$(grep "^${nome}|" "$LISTA") || exit 1
        case "$formato" in
            *Config.Image*)   printf '%s\n' "$(printf '%s' "$linha" | cut -d'|' -f2)" ;;
            *compose.project*) printf '%s\n' "$(printf '%s' "$linha" | cut -d'|' -f3)" ;;
            *State.Running*)  printf 'true\n' ;;
            *) printf '\n' ;;
        esac
        ;;
    exec)
        # Basta ser estável e não vazio: o LSN só é comparado consigo mesmo.
        printf '0/1A2B3C4\n'
        ;;
    *) exit 1 ;;
esac
EOF
    chmod 755 "$CASE_TMP/bin/docker"
}

roda() {
    instalar_docker_falso
    CONTAINERS_FILE="$CASE_TMP/containers" \
    DEST="$DEST_TMP" \
    PATH="$CASE_TMP/bin:$PATH" \
        bash "$BACKUP_DB" "$@" >"$SAIDA" 2>&1
    EXIT_CODE=$?
}

# Cria um dump antigo já existente, para simular histórico em disco.
dump_antigo() {
    local slug=$1
    mkdir -p "$DEST_TMP/$slug"
    printf 'dump falso' >"$DEST_TMP/$slug/${slug}_banco_20260101_000000.dump"
}

# ---------------------------------------------------------------------------

# O ciclo é onde o filtro de imagem se paga, e é por isso que estes dois casos
# rodam o ciclo e contam o cabeçalho `== <slug>` em vez de olhar o `--estado`:
# o `--estado` deduplica por slug, então um contêiner de aplicação tratado como
# banco não apareceria lá. Descoberto por mutação: com estes casos escritos
# sobre o `--estado`, remover o filtro inteiro não derrubava nenhum deles.
begin_case
contêiner mp-portal-postgres-1 postgres:17-alpine mp-portal
contêiner mp-portal-web-1      mp-portal:local    mp-portal
roda
assert_eq 0 "$EXIT_CODE" 'ciclo sai bem'
assert_eq 1 "$(grep -c '== mp_portal' "$SAIDA")" 'o contêiner da aplicação não vira banco'
end_case 'descobre o banco pela imagem e ignora o contêiner da aplicação'

begin_case
# O caso real do VPS: os aplicativos trazem o cliente do Postgres, então um
# critério do tipo "tem pg_dump dentro" aprovaria estes dois.
contêiner conforto-termico-postgres-1 postgres:17-alpine conforto-termico
contêiner conforto-termico-ict-1      conforto-termico:local conforto-termico
contêiner conforto-termico-coletor-1  conforto-termico:local conforto-termico
roda
assert_eq 1 "$(grep -c '== conforto_termico' "$SAIDA")" 'um banco, não três'
end_case 'três contêineres do mesmo projeto dão um banco só'

begin_case
# Nome de contêiner não serve de critério: a frota usa `-postgres-1` em quatro
# projetos e `-db-1` no ControleRendaVariavel.
contêiner controle-renda-variavel-db-1 postgres:17-alpine controle-renda-variavel
roda --estado
assert_saida 'controle_renda_variavel' 'o sufixo -db-1 é descoberto igual ao -postgres-1'
end_case 'o slug vem do projeto do Compose, não do nome do contêiner'

begin_case
roda
[ "$EXIT_CODE" -ne 0 ] || fail 'ciclo sem nenhum banco deve sair não zero'
assert_saida 'nenhum contêiner postgres rodando' 'a descoberta vazia precisa ser dita em voz alta'
assert_sem_saida 'ciclo concluído sem falhas' 'não pode declarar sucesso sem ter salvo nada'
end_case 'descoberta vazia é erro barulhento, nunca sucesso silencioso'

begin_case
contêiner mp-portal-postgres-1 postgres:17-alpine mp-portal
dump_antigo conforto_termico
roda
[ "$EXIT_CODE" -ne 0 ] || fail 'banco desaparecido deve sair não zero'
assert_saida 'conforto_termico tem backup anterior' 'banco com histórico e sem contêiner precisa alertar'
end_case 'banco que tinha backup e sumiu conta como falha'

begin_case
contêiner mp-portal-postgres-1 postgres:17-alpine mp-portal
roda
assert_eq 0 "$EXIT_CODE" 'VPS novo com um banco só é operação normal'
assert_saida 'ciclo concluído sem falhas' 'um único banco basta para o ciclo dar certo'
end_case 'servidor com um app só não é erro'

begin_case
contêiner mp-portal-postgres-1 postgres:17-alpine mp-portal
dump_antigo mp_portal
roda --estado
assert_saida 'mp_portal' 'projeto com histórico aparece'
assert_eq 0 "$EXIT_CODE" '--estado com histórico sai bem'
end_case 'estado mostra o projeto que tem dump em disco'

printf '1..%d\n' "$TOTAL"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d de %d testes falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf '# %d testes passaram\n' "$TOTAL"
