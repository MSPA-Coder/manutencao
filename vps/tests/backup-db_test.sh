#!/usr/bin/env bash
# Testes herméticos da DESCOBERTA de bancos e da CÓPIA DE VOLUMES do
# `backup-db.sh`, sem Docker, sem Postgres e sem VPS.
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
#   - o critério das imagens `postgres:*` e `mspa-postgres:*` (e não "tem
#     pg_dump dentro", que no VPS real aprova contêineres da aplicação);
#   - a guarda de descoberta vazia, que é a diferença entre "não salvei nada" e
#     "não salvei nada e disse que deu certo" -- o modo de falha que um backup
#     não pode ter;
#   - o aviso de banco desaparecido, que é o único caso que a descoberta
#     sozinha não enxerga (contêiner parado não aparece em `docker ps`).
#
# E, desde 02/10/2026, a cópia do volume rotulado `mspa.backup.volume` (o
# SQLite do Wealthfolio, que nenhum `pg_dump` alcança):
#   - a cópia acontece com o contêiner pausado, e ele SEMPRE volta, inclusive
#     quando a cópia falha ou o script é interrompido no meio: um backup que
#     deixa a aplicação congelada troca um risco por outro;
#   - cópia vazia ou ilegível não vira backup;
#   - cópia idêntica à última não vira arquivo novo, e a retenção poupa o
#     mais recente;
#   - volume que já teve cópia e sumiu é acusado, como os bancos.
#
# E, desde 25/10/2026, os sites que o nginx publica e a configuração do
# servidor:
#   - o site vem do vhost (`root` ou `proxy_pass` para a porta de um contêiner),
#     nunca de lista; a página padrão e o webroot do certbot não são site;
#   - segredos e o que se regenera ficam fora da cópia;
#   - cópia idêntica à última não vira arquivo novo;
#   - site que sai do nginx é aviso, não falha;
#   - a máquina sem banco nenhum é normal; o Docker que não responde é falha.
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
    REGISTRO="$CASE_TMP/docker.log"
    mkdir -p "$DEST_TMP" "$CASE_TMP/bin" "$CASE_TMP/vol" "$CASE_TMP/raiz"
    : >"$CASE_TMP/containers"
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

# Declara um contêiner para o `docker` falso: nome, imagem, projeto do Compose
# e, opcionais, os rótulos `mspa.backup.volume` e `mspa.backup.postgres`, as
# portas publicadas (como o `docker ps` as mostra) e a pasta do Compose.
contêiner() {
    printf '%s|%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "${4:-}" "${5:-}" "${6:-}" "${7:-}" \
        >>"$CASE_TMP/containers"
}

# Um vhost habilitado: `vhost <nome> <conteúdo>`. A raiz `/` da máquina é
# `$CASE_TMP/raiz`.
vhost() {
    mkdir -p "$CASE_TMP/raiz/etc/nginx/sites-enabled"
    printf '%s\n' "$2" >"$CASE_TMP/raiz/etc/nginx/sites-enabled/$1"
}

# Um arquivo sob a raiz da máquina: `arquivo_na_raiz <caminho> <conteúdo>`.
arquivo_na_raiz() {
    mkdir -p "$(dirname "$CASE_TMP/raiz$1")"
    printf '%s' "$2" >"$CASE_TMP/raiz$1"
}

# Os membros de uma cópia, um por linha, sem o `./` do começo.
membros() {
    tar -tzf "$1" | sed 's#^\./##' | sort
}

# Um arquivo dentro do volume que o `docker cp` falso entrega:
# `arquivo_no_volume <contêiner> <caminho no contêiner> <conteúdo>`.
arquivo_no_volume() {
    mkdir -p "$(dirname "$CASE_TMP/vol/$1$2")"
    printf '%s' "$3" >"$CASE_TMP/vol/$1$2"
}

# `docker` falso. Cobre só os subcomandos que o script usa; o `exec` devolve
# valores plausíveis para que o ciclo chegue até o fim sem Postgres. `pause`,
# `unpause` e `cp` ficam registrados em $REGISTRO, e o `cp` anota se o
# contêiner estava pausado na hora: é isso que os casos de volume conferem.
instalar_docker_falso() {
    cat >"$CASE_TMP/bin/docker" <<'EOF'
#!/usr/bin/env bash
LISTA="$CASE_DIR/containers"
REGISTRO="$CASE_DIR/docker.log"

[ -e "$CASE_DIR/docker-fora" ] && exit 1

case "$1" in
    ps)
        case "$*" in
            *Ports*) awk -F'|' '{print $1 "\t" $6}' "$LISTA" ;;
            *Image*) awk -F'|' '{print "  " $1 "  " $2}' "$LISTA" ;;
            *)       cut -d'|' -f1 "$LISTA" ;;
        esac
        ;;
    inspect)
        # `-f <formato> <nome>`
        formato="$2"; [ "$formato" = "-f" ] && { formato="$3"; nome="$4"; } || nome="$3"
        linha=$(grep "^${nome}|" "$LISTA") || exit 1
        case "$formato" in
            *working_dir*)    printf '%s\n' "$(printf '%s' "$linha" | cut -d'|' -f7)" ;;
            *Config.Image*)   printf '%s\n' "$(printf '%s' "$linha" | cut -d'|' -f2)" ;;
            *compose.project*) printf '%s\n' "$(printf '%s' "$linha" | cut -d'|' -f3)" ;;
            *mspa.backup.volume*) printf '%s\n' "$(printf '%s' "$linha" | cut -d'|' -f4)" ;;
            *mspa.backup.postgres*) printf '%s\n' "$(printf '%s' "$linha" | cut -d'|' -f5)" ;;
            *State.Running*)  printf 'true\n' ;;
            *) printf '\n' ;;
        esac
        ;;
    exec)
        # Basta ser estável e não vazio: o LSN só é comparado consigo mesmo.
        printf '0/1A2B3C4\n'
        ;;
    pause)
        # Como o real: pausar o que já está pausado é erro.
        [ -e "$CASE_DIR/falha-pause" ] && exit 1
        [ -e "$CASE_DIR/pausado.$2" ] && exit 1
        : >"$CASE_DIR/pausado.$2"
        printf 'pause %s\n' "$2" >>"$REGISTRO"
        ;;
    unpause)
        [ -e "$CASE_DIR/falha-unpause" ] && exit 1
        rm -f "$CASE_DIR/pausado.$2"
        printf 'unpause %s\n' "$2" >>"$REGISTRO"
        ;;
    cp)
        # `cp <nome>:<caminho> -`: um tar com o diretório na raiz, como o real.
        nome="${2%%:*}"; caminho="${2#*:}"
        if [ -e "$CASE_DIR/pausado.$nome" ]; then estado=pausado; else estado=rodando; fi
        printf 'cp %s %s\n' "$2" "$estado" >>"$REGISTRO"
        [ -e "$CASE_DIR/cp-lento" ] && sleep 30
        [ -e "$CASE_DIR/falha-cp" ] && exit 1
        if [ -e "$CASE_DIR/cp-truncado" ]; then
            # Cabeçalhos inteiros e o conteúdo cortado: o `tar -t` ainda lista
            # o arquivo antes de reclamar do fim inesperado.
            tar -C "$CASE_DIR/vol/$nome$(dirname "$caminho")" -cf - "$(basename "$caminho")" \
                | head -c 1100
            exit 0
        fi
        tar -C "$CASE_DIR/vol/$nome$(dirname "$caminho")" -cf - "$(basename "$caminho")"
        ;;
    *) exit 1 ;;
esac
EOF
    chmod 755 "$CASE_TMP/bin/docker"
}

roda() {
    instalar_docker_falso
    CASE_DIR="$CASE_TMP" \
    DEST="$DEST_TMP" \
    CONFIG_RAIZ="$CASE_TMP/raiz" LEITOR='' \
    APP_LOCK_DIR="$CASE_TMP/app-locks" APP_LOCK_TIMEOUT_SEGUNDOS="${APP_LOCK_TIMEOUT_SEGUNDOS:-300}" \
    PATH="$CASE_TMP/bin:$PATH" \
        bash "$BACKUP_DB" "$@" >"$SAIDA" 2>&1
    EXIT_CODE=$?
}

assert_registro() {
    local esperado=$1 descricao=$2
    assert_eq "$esperado" "$(cat "$REGISTRO")" "$descricao"
}

# As cópias gravadas de um projeto, uma por linha, em ordem de nome. Glob e não
# `find -printf`, que o busybox da imagem `bash:5.2` não tem.
copias() {
    local f
    for f in "$DEST_TMP/$1"/*.tar.gz; do
        [ -e "$f" ] && basename "$f"
    done | sort
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
# A imagem padrão da frota tem prefixo `mspa-`; era aceita pelo Compose, mas
# rejeitada pela descoberta do backup no VPS.
contêiner controle-renda-variavel-db-1 mspa-postgres:17-alpine controle-renda-variavel
contêiner controle-renda-variavel-web-1 controle-renda-variavel:local controle-renda-variavel
roda
assert_eq 0 "$EXIT_CODE" 'imagem Postgres compartilhada é aceita'
assert_eq 1 "$(grep -c '== controle_renda_variavel' "$SAIDA")" 'o banco é salvo uma vez'
end_case 'descobre bancos da imagem compartilhada mspa-postgres'

for imagem in "ghcr.io/mspa-coder/app-postgres@sha256:$(printf '%064d' 0)" "sha256:$(printf '%064d' 1)"; do
    begin_case
    contêiner app-db-1 "$imagem" app "" true
    contêiner app-web-1 ghcr.io/mspa-coder/app:run-1-1 app
    contêiner app-provision-1 "$imagem" app
    roda
    assert_eq 0 "$EXIT_CODE" 'banco rotulado continua coberto'
    assert_eq 1 "$(grep -c '== app' "$SAIDA")" 'só o servidor, não web/provision, vira dump'
    end_case "descobre banco rotulado por digest/ID: $imagem"
done

for rotulo in "" false True postgres; do
    begin_case
    contêiner app-web-1 ghcr.io/mspa-coder/app:run-1-1 app "" "$rotulo"
    roda
    assert_eq 0 "$(grep -c ' == app$' "$SAIDA")" 'sem opt-in exato não pode inferir banco'
    assert_saida 'nenhum contêiner postgres nesta máquina' 'imagem desconhecida sem true é recusada'
    end_case "não inventa servidor a partir do rótulo: '$rotulo'"
done

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

# Até 25/10/2026 a descoberta vazia era sempre erro. O VPS2 só serve sites e
# nunca teve banco: ali o vazio é o normal, e o que não pode passar calado é o
# Docker fora do ar (o banco que existia e sumiu é acusado à parte, pelo
# histórico em disco).
begin_case
roda
assert_eq 0 "$EXIT_CODE" 'máquina sem banco nenhum é operação normal'
assert_saida 'nenhum contêiner postgres nesta máquina' 'o vazio é dito no log'
end_case 'máquina sem banco nenhum não é falha'

begin_case
: >"$CASE_TMP/docker-fora"
roda
[ "$EXIT_CODE" -ne 0 ] || fail 'docker fora do ar deve sair não zero'
assert_saida 'o docker não responde' 'o docker parado precisa ser dito em voz alta'
assert_sem_saida 'ciclo concluído sem falhas' 'não pode declarar sucesso sem ter salvo nada'
end_case 'docker fora do ar é erro barulhento, nunca sucesso silencioso'

begin_case
contêiner mp-portal-postgres-1 postgres:17-alpine mp-portal
dump_antigo conforto_termico
roda
[ "$EXIT_CODE" -ne 0 ] || fail 'banco desaparecido deve sair não zero'
assert_saida 'conforto_termico tem backup anterior' 'banco com histórico e sem contêiner precisa alertar'
end_case 'banco que tinha backup e sumiu conta como falha'

begin_case
# 10/10/2026: um dump manual em `~/backups/manual/` fez o ciclo sair com falha
# ("manual tem backup anterior") e disparar o OnFailure= do serviço.
contêiner mp-portal-postgres-1 postgres:17-alpine mp-portal
mkdir -p "$DEST_TMP/manual"
printf 'x' >"$DEST_TMP/manual/crv_antes_excluir_simulada_20261009_165006.dump"
roda
assert_eq 0 "$EXIT_CODE" 'pasta com dump manual não é banco desaparecido'
assert_sem_saida 'manual tem backup anterior' 'dump manual não vira histórico de projeto'
assert_saida 'ciclo concluído sem falhas' 'o ciclo termina limpo'
end_case 'dump manual em pasta própria não é banco desaparecido'

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

# ---------------------------------------------------------------------------
# Volumes rotulados

WF=wealthfolio-teste-wealthfolio-1

# Um VPS com um banco e o Wealthfolio rotulado, com um SQLite e o `-wal`.
com_wealthfolio() {
    contêiner mega-sena-postgres-1 postgres:17-alpine mega-sena
    contêiner "$WF" wealthfolio-teste:3.9.1-local wealthfolio-teste /data
    arquivo_no_volume "$WF" /data/wealthfolio.db 'banco'
    arquivo_no_volume "$WF" /data/wealthfolio.db-wal 'wal'
}

begin_case
com_wealthfolio
roda
assert_eq 0 "$EXIT_CODE" 'ciclo com volume sai bem'
assert_registro "pause $WF
cp $WF:/data pausado
unpause $WF" 'a cópia acontece com o contêiner pausado, e ele volta depois'
copia=$(copias wealthfolio_teste)
[[ "$copia" =~ ^wealthfolio_teste_volume_[0-9]{8}_[0-9]{6}\.tar\.gz$ ]] \
    || fail "nome da cópia fora do formato que o agente aceita: '$copia'"
final="$DEST_TMP/wealthfolio_teste/$copia"
assert_eq "$(sha256sum "$final" | cut -d' ' -f1)" "$(cat "$final.sha256" 2>/dev/null)" \
    'o .sha256 ao lado confere com a cópia'
assert_eq "data/wealthfolio.db-wal" "$(tar -tzf "$final" 2>/dev/null | grep -- '-wal$')" \
    'o -wal vai junto: sem ele, o que está só no WAL se perde'
[ -f "$DEST_TMP/wealthfolio_teste/.ultima_conferencia" ] \
    || fail 'o vigia mede o frescor pelo .ultima_conferencia'
end_case 'copia o volume rotulado com o contêiner pausado e despausa ao fim'

begin_case
contêiner mega-sena-postgres-1 postgres:17-alpine mega-sena
contêiner mega-sena-web-1      mega-sena:local    mega-sena
roda
assert_eq 0 "$EXIT_CODE" 'sem rótulo, o ciclo é só o dos bancos'
assert_registro '' 'contêiner sem rótulo nunca é pausado'
end_case 'contêiner sem o rótulo não é pausado nem copiado'

begin_case
com_wealthfolio
contêiner outro-app-1 outro:local outro-app /srv/estado
arquivo_no_volume outro-app-1 /srv/estado/dados.json '{}'
roda
assert_eq 0 "$EXIT_CODE" 'dois volumes, ciclo bom'
assert_registro "pause outro-app-1
cp outro-app-1:/srv/estado pausado
unpause outro-app-1
pause $WF
cp $WF:/data pausado
unpause $WF" 'cada contêiner volta antes de o próximo ser pausado'
assert_eq 1 "$(copias outro_app | wc -l)" 'o segundo volume tem a própria pasta'
end_case 'dois volumes rotulados: um de cada vez, cada um na sua pasta'

begin_case
com_wealthfolio
: >"$CASE_TMP/falha-cp"
roda
[ "$EXIT_CODE" -ne 0 ] || fail 'cópia que falha precisa sair não zero'
assert_registro "pause $WF
cp $WF:/data pausado
unpause $WF" 'o contêiner volta mesmo quando a cópia falha'
assert_eq '' "$(copias wealthfolio_teste)" 'cópia falha não deixa arquivo final'
assert_eq '' "$(find "$DEST_TMP" -name '*.tmp')" 'nem o .tmp'
end_case 'cópia que falha despausa o contêiner e não grava nada'

begin_case
com_wealthfolio
: >"$CASE_TMP/falha-unpause"
roda
[ "$EXIT_CODE" -ne 0 ] || fail 'falha de despausa precisa sair não zero'
[ -e "$CASE_TMP/pausado.$WF" ] || fail 'simulador deveria manter contêiner pausado'
assert_eq '' "$(copias wealthfolio_teste)" 'não publica cópia quando a despausa falha'
grep -q 'não foi possível despausar' "$SAIDA" || fail 'deve informar a falha de despausa'
end_case 'falha ao despausar é informada e não publica cópia'

begin_case
com_wealthfolio
: >"$CASE_TMP/falha-pause"
roda
[ "$EXIT_CODE" -ne 0 ] || fail 'sem pausa, o ciclo precisa sair não zero'
assert_registro '' 'sem pausa não há cópia (nem despausa de quem não pausamos)'
assert_eq '' "$(copias wealthfolio_teste)" 'nada gravado'
end_case 'sem conseguir pausar, não copia com a aplicação escrevendo'

begin_case
com_wealthfolio
arquivo_no_volume "$WF" /data/wealthfolio.db "$(head -c 4000 /dev/zero | tr '\0' 'x')"
: >"$CASE_TMP/cp-truncado"
roda
[ "$EXIT_CODE" -ne 0 ] || fail 'cópia truncada precisa sair não zero'
assert_eq '' "$(copias wealthfolio_teste)" 'cópia truncada não vira backup'
end_case 'cópia que o tar não consegue ler até o fim é reprovada'

begin_case
contêiner "$WF" wealthfolio-teste:3.9.1-local wealthfolio-teste /data
mkdir -p "$CASE_TMP/vol/$WF/data/vazio"
roda
[ "$EXIT_CODE" -ne 0 ] || fail 'volume vazio precisa sair não zero'
assert_saida 'volume vazio' 'o motivo da recusa precisa aparecer'
assert_eq '' "$(copias wealthfolio_teste)" 'cópia vazia não vira backup'
end_case 'volume sem nenhum arquivo é reprovado'

begin_case
com_wealthfolio
roda
primeira=$(copias wealthfolio_teste)
touch -d '@1' "$DEST_TMP/wealthfolio_teste/.ultima_conferencia"
sleep 1
roda
assert_eq 0 "$EXIT_CODE" 'volume sem mudança é sucesso'
assert_eq "$primeira" "$(copias wealthfolio_teste)" 'cópia idêntica não vira um segundo arquivo'
[ "$(stat -c %Y "$DEST_TMP/wealthfolio_teste/.ultima_conferencia")" -gt 1 ] \
    || fail 'a conferência sem mudança também é registrada'
sleep 1
arquivo_no_volume "$WF" /data/wealthfolio.db-wal 'wal com um snapshot novo'
roda
assert_eq 2 "$(copias wealthfolio_teste | wc -l)" 'volume alterado ganha cópia nova'
sleep 1
roda --forcar
assert_eq 3 "$(copias wealthfolio_teste | wc -l)" '--forcar grava mesmo sem mudança'
end_case 'só grava cópia nova quando o volume mudou (ou com --forcar)'

begin_case
com_wealthfolio
roda
velha=$(copias wealthfolio_teste)
touch -d "@$(( $(date +%s) - 20 * 86400 ))" "$DEST_TMP/wealthfolio_teste/$velha"
sleep 1
roda
nova=$(copias wealthfolio_teste)
assert_eq 1 "$(printf '%s\n' "$nova" | wc -l)" 'a cópia de 20 dias sai quando há substituta'
[ "$nova" != "$velha" ] || fail 'quem ficou precisa ser a nova'
[ -e "$DEST_TMP/wealthfolio_teste/$velha.sha256" ] && fail 'o .sha256 da removida sai junto'
assert_saida 'teto de 7 dias' 'cópia velha força uma nova mesmo sem mudança'
end_case 'retenção remove a cópia antiga depois de gravar a substituta'

begin_case
contêiner mega-sena-postgres-1 postgres:17-alpine mega-sena
mkdir -p "$DEST_TMP/wealthfolio_teste"
printf 'x' >"$DEST_TMP/wealthfolio_teste/wealthfolio_teste_volume_20260101_000000.tar.gz"
roda
[ "$EXIT_CODE" -ne 0 ] || fail 'volume desaparecido deve sair não zero'
assert_saida 'wealthfolio_teste tem cópia de volume anterior' 'volume com histórico e sem contêiner precisa alertar'
end_case 'volume que tinha cópia e sumiu conta como falha'

begin_case
contêiner "$WF" wealthfolio-teste:3.9.1-local wealthfolio-teste /data
arquivo_no_volume "$WF" /data/wealthfolio.db 'banco'
roda
assert_eq 0 "$EXIT_CODE" 'sem nenhum postgres, o ciclo do volume sai bem'
assert_saida 'nenhum contêiner postgres nesta máquina' 'a guarda dos bancos continua falando'
assert_eq 1 "$(copias wealthfolio_teste | wc -l)" 'e o volume é copiado'
end_case 'falta de banco não impede a cópia do volume'

begin_case
contêiner mega-sena-postgres-1 postgres:17-alpine mega-sena
contêiner "$WF" wealthfolio-teste:3.9.1-local wealthfolio-teste '/data/../etc'
roda
[ "$EXIT_CODE" -ne 0 ] || fail 'rótulo inválido deve sair não zero'
assert_registro '' 'rótulo inválido não chega a pausar'
end_case 'rótulo com caminho relativo ou com .. é recusado'

begin_case
com_wealthfolio
roda --estado
assert_saida 'wealthfolio_teste' 'o volume recém-rotulado aparece antes da primeira cópia'
assert_registro '' '--estado não pausa nada'
end_case 'estado mostra o volume rotulado mesmo sem cópia ainda'

begin_case
com_wealthfolio
mkdir -p "$CASE_TMP/app-locks"
(
    exec 9>"$CASE_TMP/app-locks/wealthfolio_teste.lock"
    flock -n 9
    sleep 3
) &
lock_pid=$!
sleep 0.1
APP_LOCK_TIMEOUT_SEGUNDOS=0 roda
wait "$lock_pid"
[ "$EXIT_CODE" -ne 0 ] || fail 'backup com lock do Wealthfolio ocupado deve falhar'
assert_saida 'wealthfolio_teste está em outra operação' 'a contenção deve identificar o volume protegido'
assert_registro '' 'backup bloqueado não pode pausar nem copiar o contêiner'
end_case 'backup do volume não concorre com deploy do Wealthfolio'

# O systemd encerra o serviço mandando TERM para o grupo inteiro (o script, o
# `docker cp` e o `gzip`). O contêiner não pode ficar congelado por isso.
begin_case
com_wealthfolio
: >"$CASE_TMP/cp-lento"
instalar_docker_falso
CASE_DIR="$CASE_TMP" DEST="$DEST_TMP" PATH="$CASE_TMP/bin:$PATH" \
    CONFIG_RAIZ="$CASE_TMP/raiz" LEITOR='' APP_LOCK_DIR="$CASE_TMP/app-locks" \
    setsid bash "$BACKUP_DB" >"$SAIDA" 2>&1 &
pid=$!
for _ in $(seq 1 100); do
    grep -q '^cp ' "$REGISTRO" && break
    sleep 0.1
done
kill -TERM -- "-$pid" 2>/dev/null
wait "$pid"
[ -e "$CASE_TMP/pausado.$WF" ] && fail 'o contêiner ficou pausado depois do TERM'
assert_eq "unpause $WF" "$(tail -1 "$REGISTRO")" 'o trap despausou'
end_case 'TERM no meio da cópia ainda devolve o contêiner'

# ---------------------------------------------------------------------------
# Sites publicados pelo nginx e configuração do servidor

# Um site estático com um pouco de tudo: página, imagem, e o que NÃO pode ir
# para a cópia (segredo, Git, dependências).
com_site_estatico() {
    SITE="$CASE_TMP/raiz/var/www/villa-rica"
    vhost villa-rica "server {
    server_name villa-rica.duckdns.org;
    root $SITE;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
}"
    vhost default 'server { server_name _; root /var/www/html; }'
    arquivo_na_raiz /var/www/villa-rica/index.html '<h1>oi</h1>'
    arquivo_na_raiz /var/www/villa-rica/assets/brasao.jpg 'jpg'
    arquivo_na_raiz /var/www/villa-rica/.env 'SENHA=1'
    arquivo_na_raiz /var/www/villa-rica/chave.key 'segredo'
    arquivo_na_raiz /var/www/villa-rica/.secrets/token 'segredo'
    arquivo_na_raiz /var/www/villa-rica/.git/HEAD 'ref'
    arquivo_na_raiz /var/www/villa-rica/node_modules/x/index.js 'js'
}

begin_case
com_site_estatico
roda
assert_eq 0 "$EXIT_CODE" 'ciclo com site sai bem'
copia=$(copias site_villa_rica)
[[ "$copia" =~ ^site_villa_rica_volume_[0-9]{8}_[0-9]{6}\.tar\.gz$ ]] \
    || fail "nome da cópia fora do formato que o agente aceita: '$copia'"
final="$DEST_TMP/site_villa_rica/$copia"
assert_eq "assets/brasao.jpg
index.html" "$(membros "$final")" 'só os arquivos do site, sem segredo, Git nem dependências'
assert_eq "$(sha256sum "$final" | cut -d' ' -f1)" "$(cat "$final.sha256" 2>/dev/null)" \
    'o .sha256 é o do arquivo gravado'
assert_eq 0 "$(find "$DEST_TMP" -maxdepth 1 -name 'site_html' | wc -l)" 'a página padrão não é site'
[ -e "$DEST_TMP/site_certbot" ] && fail 'o webroot do certbot não é site'
assert_saida 'villa-rica.duckdns.org' 'o log diz o domínio do site'
end_case 'site estático é descoberto pelo vhost e copiado sem segredos'

begin_case
com_site_estatico
roda
roda
assert_eq 1 "$(copias site_villa_rica | wc -l)" 'a segunda rodada sem mudança não grava'
assert_saida 'sem alterações desde a última cópia' 'e diz por quê'
arquivo_na_raiz /var/www/villa-rica/index.html '<h1>mudou</h1>'
sleep 1
roda
assert_eq 2 "$(copias site_villa_rica | wc -l)" 'o site alterado ganha cópia nova'
end_case 'site só ganha cópia nova quando muda'

begin_case
# Aplicação atrás de proxy: o vhost só diz a porta; a pasta vem do Compose do
# contêiner que a publica.
APP="$CASE_TMP/raiz/home/ubuntu/apps/viva-passo"
contêiner viva-passo-web-1 viva-passo:local viva-passo "" "" "127.0.0.1:5701->80/tcp" "$APP"
vhost viva-passo 'server {
    server_name viva-mspa.duckdns.org;
    location / { proxy_pass http://127.0.0.1:5701; }
}'
arquivo_na_raiz /home/ubuntu/apps/viva-passo/compose.yaml 'services: {}'
arquivo_na_raiz /home/ubuntu/apps/viva-passo/app.js 'x'
roda
assert_eq 0 "$EXIT_CODE" 'ciclo com aplicação sai bem'
assert_eq 1 "$(copias site_viva_passo | wc -l)" 'a pasta do Compose vira cópia'
assert_eq "app.js
compose.yaml" "$(membros "$DEST_TMP/site_viva_passo/$(copias site_viva_passo)")" \
    'com os arquivos da aplicação'
end_case 'proxy_pass leva à pasta do Compose do contêiner da porta'

begin_case
vhost orfao 'server { server_name x.duckdns.org; location / { proxy_pass http://127.0.0.1:9999; } }'
roda
assert_eq 0 "$EXIT_CODE" 'porta sem contêiner não derruba o ciclo'
[ -e "$DEST_TMP/site_orfao" ] && fail 'porta sem contêiner não inventa site'
end_case 'proxy_pass para porta sem contêiner é ignorado'

begin_case
com_site_estatico
roda
rm -f "$CASE_TMP/raiz/etc/nginx/sites-enabled/villa-rica"
printf '2000-01-01T00:00:00Z\n' >"$DEST_TMP/site_villa_rica/.ultima_conferencia"
roda
assert_eq 0 "$EXIT_CODE" 'site retirado do nginx não é falha'
assert_saida 'não está mais no nginx' 'mas é avisado'
assert_eq 1 "$(copias site_villa_rica | wc -l)" 'a cópia antiga fica'
[ "$(cat "$DEST_TMP/site_villa_rica/.ultima_conferencia")" = '2000-01-01T00:00:00Z' ] \
    && fail 'a conferência precisa andar, ou o vigia alerta todo dia'
end_case 'site que sai do nginx é aviso, com a cópia antiga preservada'

begin_case
com_site_estatico
arquivo_na_raiz /etc/nginx/sites-available/villa-rica 'server { }'
arquivo_na_raiz /etc/systemd/system/backup-db.timer '[Timer]'
arquivo_na_raiz /etc/letsencrypt/renewal/villa-rica.duckdns.org.conf 'renova'
arquivo_na_raiz /etc/letsencrypt/live/villa-rica.duckdns.org/privkey.pem 'CHAVE'
arquivo_na_raiz /etc/hostname 'vps-teste'
arquivo_na_raiz /etc/nginx/segredos/viva-passo.htpasswd 'usuario:hash-bcrypt'
roda
assert_eq 0 "$EXIT_CODE" 'ciclo com configuração sai bem'
copia=$(copias configuracao_servidor)
[[ "$copia" =~ ^configuracao_servidor_volume_[0-9]{8}_[0-9]{6}\.tar\.gz$ ]] \
    || fail "nome da cópia fora do formato que o agente aceita: '$copia'"
conteudo=$(membros "$DEST_TMP/configuracao_servidor/$copia")
for esperado in INVENTARIO.txt etc/nginx/sites-available/villa-rica \
                etc/systemd/system/backup-db.timer \
                etc/letsencrypt/renewal/villa-rica.duckdns.org.conf etc/hostname; do
    grep -qx "$esperado" <<<"$conteudo" || fail "a configuração não trouxe $esperado"
done
grep -q 'privkey' <<<"$conteudo" && fail 'chave privada do certificado não entra'
grep -q 'htpasswd' <<<"$conteudo" && fail 'arquivo de senhas do nginx não entra'
inventario=$(tar -xzOf "$DEST_TMP/configuracao_servidor/$copia" ./INVENTARIO.txt)
grep -q 'site_villa_rica' <<<"$inventario" || fail 'o inventário lista o site'
grep -q 'villa-rica.duckdns.org' <<<"$inventario" || fail 'com o domínio'
grep -q 'vps-teste' <<<"$inventario" || fail 'e o nome da máquina'
grep -q '/etc/nginx/segredos/viva-passo.htpasswd' <<<"$inventario" \
    || fail 'o inventário diz qual segredo ficou de fora'
grep -Fq 'segredos fora da cópia (do cofre): .env .secrets/token chave.key' <<<"$inventario" \
    || fail 'e quais segredos de cada site ficaram fora da cópia'
sleep 1
roda
assert_eq 1 "$(copias configuracao_servidor | wc -l)" 'configuração igual não gera cópia nova'
end_case 'configuração do servidor: vhosts, unidades e inventário, sem chave privada'

printf '1..%d\n' "$TOTAL"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d de %d testes falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf '# %d testes passaram\n' "$TOTAL"
