#!/usr/bin/env bash
# Testes herméticos das verificações de BUSCA e de FRESCOR DOS DADOS do
# `vigia.sh`, sem rede, sem Telegram e sem VPS.
#
# POR QUE ESTE ARQUIVO EXISTE: ver o cabeçalho de `backup-agent_test.sh`. O
# agente grava `.ultima_busca` a cada `listar`; aqui se prova que o vigia lê
# esse marcador, alerta quando ele some ou passa do limite, e não alerta em
# máquina que não produz backup.
#
# O frescor dos dados (cotações do CRV, sincronização e importação do
# Wealthfolio) fala com o Docker. O andaime põe um `docker` falso no lugar, que
# responde pelo que cada caso deixa em `$FAKE`: se o contêiner existe, o que o
# `psql` do CRV devolve (e com que código de saída) e o que o log do Wealthfolio
# traz nas últimas 8h e na última hora.
#
# O RESTO DO VIGIA FICA DE FORA, DE PROPÓSITO: disco, endereços públicos e
# certificado dependem de rede e do servidor, e são conferidos pelo `--estado`
# depois da instalação. O andaime aponta o vigia para um diretório de vhosts
# vazio, então em todo caso ele alerta a própria cegueira; as asserções abaixo
# procuram títulos específicos e ignoram esse.
#
# O `alerta.sh` é um script falso que registra título e corpo.
#
# Uso:
#   docker run --rm -v "${PWD}:/repo:ro" bash:5.2 bash /repo/vps/tests/vigia_test.sh

set -u

# shellcheck disable=SC1007  # `CDPATH=` é prefixo de ambiente para um comando,
# não assinalamento com espaço sobrando. Mesmo motivo escrito em `instalar.sh`.
TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VIGIA="$TESTS_DIR/../vigia.sh"
TOTAL=0
FAILED=0
CASE_FAILED=0
SUITE_TMP=$(mktemp -d)
trap 'rm -rf -- "$SUITE_TMP"' EXIT HUP INT TERM

fail() {
    printf '    FALHA: %s\n' "$1" >&2
    CASE_FAILED=1
}

assert_alerta() {
    local padrao=$1 descricao=$2
    grep -Fq -- "$padrao" "$ALERTAS" || fail "$descricao (ausente: $padrao)"
}

assert_sem_alerta() {
    local padrao=$1 descricao=$2
    grep -Fq -- "$padrao" "$ALERTAS" && fail "$descricao (presente: $padrao)"
    return 0
}

assert_saida() {
    local padrao=$1 descricao=$2
    grep -Fq -- "$padrao" "$SAIDA" || fail "$descricao (ausente: $padrao)"
}

begin_case() {
    CASE_FAILED=0
    CASE_TMP=$(mktemp -d "$SUITE_TMP/caso.XXXXXX")
    BACKUPS_TMP="$CASE_TMP/backups"
    MARCA="$BACKUPS_TMP/.ultima_busca"
    ALERTAS="$CASE_TMP/alertas.txt"
    SAIDA="$CASE_TMP/saida.txt"
    mkdir -p "$BACKUPS_TMP" "$CASE_TMP/vhosts" "$CASE_TMP/bin"
    : >"$ALERTAS"

    # Falso `alerta.sh`: registra título e corpo em vez de falar com o Telegram.
    cat >"$CASE_TMP/bin/alerta.sh" <<'EOF'
#!/usr/bin/env bash
printf 'TITULO=%s\n' "$1" >>"$ALERTAS"
printf 'CORPO=%s\n' "${2:-}" >>"$ALERTAS"
exit 0
EOF
    chmod 755 "$CASE_TMP/bin/alerta.sh"

    # Falso `docker`: responde pelo que o caso deixou em $FAKE. Sem nada ali, não
    # há contêiner nenhum, e as verificações de frescor ficam caladas.
    FAKE="$CASE_TMP/fake"
    mkdir -p "$FAKE"
    cat >"$CASE_TMP/bin/docker" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    ps)
        case "$*" in
            *project=controle-renda-variavel*) [ -e "$FAKE/crv_ps" ] && echo crvdb ;;
            *project=wealthfolio-teste*) [ -e "$FAKE/wf_ps" ] && echo wfc ;;
        esac
        exit 0 ;;
    exec)
        cat >/dev/null
        [ -e "$FAKE/crv_saida" ] && cat "$FAKE/crv_saida"
        exit "$(cat "$FAKE/crv_rc" 2>/dev/null || echo 0)" ;;
    inspect)
        case "$*" in
            *StartedAt*) cat "$FAKE/wf_inicio" 2>/dev/null ;;
            *Config.Env*) cat "$FAKE/wf_env" 2>/dev/null ;;
        esac
        exit 0 ;;
    logs)
        case "$*" in
            *"--since 1h"*) cat "$FAKE/wf_log_1h" 2>/dev/null ;;
            *"--since "[0-9]*m*) cat "$FAKE/wf_log_bat" 2>/dev/null ;;
            *) cat "$FAKE/wf_log_8h" 2>/dev/null ;;
        esac
        exit 0 ;;
esac
exit 0
EOF
    chmod 755 "$CASE_TMP/bin/docker"

    # Falso `curl` para o /health: só age quando o caso deixou `$FAKE/health_corpo`;
    # sem isso, delega ao curl de verdade e nada muda nos outros casos.
    cat >"$CASE_TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
if [ -e "$FAKE/health_corpo" ]; then
    case "$*" in
        *"%{http_code}"*) echo 200 ;;
        *) cat "$FAKE/health_corpo" ;;
    esac
    exit 0
fi
exec "$CURL_REAL" "$@"
EOF
    chmod 755 "$CASE_TMP/bin/curl"
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

roda() {
    ALERTAS="$ALERTAS" \
    ALERTA="$CASE_TMP/bin/alerta.sh" \
    DOCKER="$CASE_TMP/bin/docker" \
    FAKE="$FAKE" \
    CURL_REAL="$(command -v curl)" \
    PATH="$CASE_TMP/bin:$PATH" \
    BACKUPS="$BACKUPS_TMP" \
    NGINX_HABILITADOS="$CASE_TMP/vhosts" \
        bash "$VIGIA" "$@" >"$SAIDA" 2>&1
    EXIT_CODE=$?
}

# Uma pasta de projeto com a conferência do backup recém-feita, para que o
# frescor do dump não entre no caminho do que se quer medir.
projeto_em_dia() {
    mkdir -p "$BACKUPS_TMP/$1"
    : >"$BACKUPS_TMP/$1/.ultima_conferencia"
}

busca_ha_horas() {
    : >"$MARCA"
    touch -d "@$(( $(date +%s) - $1 * 3600 ))" "$MARCA"
}

# --------------------------------------------------------------------------

begin_case
projeto_em_dia mega_sena
busca_ha_horas 2
roda
assert_sem_alerta 'TITULO=BACKUP não buscado' 'busca de 2h não é atraso'
assert_sem_alerta 'TITULO=BACKUP nunca buscado' 'o marcador existe'
end_case 'busca recente não alerta'

begin_case
projeto_em_dia mega_sena
busca_ha_horas 80
roda
assert_alerta 'TITULO=BACKUP não buscado' 'busca de 80h passou do limite de 72h'
assert_alerta 'há 80h' 'o corpo diz há quanto tempo'
end_case 'busca além do limite alerta'

begin_case
projeto_em_dia mega_sena
busca_ha_horas 71
roda
assert_sem_alerta 'TITULO=BACKUP não buscado' '71h ainda está dentro do limite'
end_case 'limite de 72h tolera um fim de semana'

begin_case
projeto_em_dia mega_sena
roda
assert_alerta 'TITULO=BACKUP nunca buscado' 'sem marcador, nenhuma cópia saiu daqui'
end_case 'marcador ausente alerta'

begin_case
busca_ha_horas 500
roda
assert_sem_alerta 'TITULO=BACKUP não buscado' 'máquina sem projeto não produz backup'
assert_sem_alerta 'TITULO=BACKUP nunca buscado' 'máquina sem projeto não produz backup'
end_case 'máquina sem projeto de backup não alerta busca'

begin_case
projeto_em_dia mega_sena
busca_ha_horas 80
roda --estado
[ "$EXIT_CODE" -eq 0 ] || fail "--estado deve sair zero (obtido $EXIT_CODE)"
[ -s "$ALERTAS" ] && fail "--estado não pode alertar (alertou: $(head -1 "$ALERTAS"))"
assert_saida 'busca dos backups: há 80h' '--estado mostra a idade da busca'
assert_saida 'ALERTARIA: BACKUP não buscado' '--estado diz o que faria'
end_case '--estado mostra a busca sem alertar'

# --------------------------------------------------------------------------
# Frescor dos dados -- CRV
# --------------------------------------------------------------------------

crv_responde() { # $1 = saída do psql ("dias|horas"), $2 = código de saída
    : >"$FAKE/crv_ps"
    printf '%s\n' "$1" >"$FAKE/crv_saida"
    printf '%s\n' "${2:-0}" >"$FAKE/crv_rc"
}

begin_case
crv_responde '1|3'
roda
assert_sem_alerta 'TITULO=COTAÇÕES diárias paradas' 'série de 1 dia está em dia'
assert_sem_alerta 'TITULO=COTAÇÃO ao vivo parada' 'cotação de 3h está em dia'
assert_sem_alerta 'TITULO=FRESCOR do CRV' 'o contrato foi lido'
end_case 'CRV em dia não alerta'

begin_case
crv_responde '6|3'
roda
assert_alerta 'TITULO=COTAÇÕES diárias paradas (CRV)' 'série de 6 dias passou do limite de 5'
assert_alerta 'registrado: 6' 'o corpo diz há quantos dias'
assert_sem_alerta 'TITULO=COTAÇÃO ao vivo parada' 'só a diária parou'
end_case 'série diária parada alerta'

begin_case
crv_responde '1|130'
roda
assert_alerta 'TITULO=COTAÇÃO ao vivo parada (CRV)' 'cotação de 130h passou do limite de 120h'
assert_alerta 'tem 130h' 'o corpo diz há quantas horas'
assert_sem_alerta 'TITULO=COTAÇÕES diárias paradas' 'só a ao vivo parou'
end_case 'cotação ao vivo parada alerta'

begin_case
crv_responde '4|119'
roda
assert_sem_alerta 'TITULO=COTAÇÕES diárias paradas' '4 dias ainda tolera fim de semana e feriado'
assert_sem_alerta 'TITULO=COTAÇÃO ao vivo parada' '119h ainda está dentro do limite'
end_case 'limites do frescor toleram fim de semana e feriado longo'

begin_case
crv_responde '-1|-1'
roda
assert_alerta 'TITULO=COTAÇÕES diárias paradas (CRV)' 'sem nenhuma cotação diária registrada'
assert_alerta 'TITULO=COTAÇÃO ao vivo parada (CRV)' 'sem nenhuma cotação ao vivo registrada'
end_case 'tabela vazia de cotações alerta'

begin_case
crv_responde 'ERROR:  schema "leitura" does not exist' 1
roda
assert_alerta 'TITULO=FRESCOR do CRV sem o contrato leitura' 'sem o esquema o vigia não sabe de nada'
assert_alerta 'schema "leitura" does not exist' 'o corpo traz a resposta do banco'
assert_sem_alerta 'TITULO=COTAÇÕES diárias paradas' 'não inventa idade quando não leu'
end_case 'contrato leitura ausente alerta a própria cegueira'

begin_case
roda
assert_sem_alerta 'TITULO=COTAÇ' 'sem o CRV nesta máquina não há o que medir'
assert_sem_alerta 'TITULO=FRESCOR do CRV' 'sem o CRV nesta máquina não há o que medir'
end_case 'máquina sem o CRV não alerta frescor'

begin_case
crv_responde '6|130'
roda --estado
[ "$EXIT_CODE" -eq 0 ] || fail "--estado deve sair zero (obtido $EXIT_CODE)"
[ -s "$ALERTAS" ] && fail "--estado não pode alertar (alertou: $(head -1 "$ALERTAS"))"
assert_saida 'frescor do CRV: série diária há 6 dia(s)' '--estado mostra a idade da série'
assert_saida 'cotação ao vivo há 130h' '--estado mostra a idade da cotação ao vivo'
assert_saida 'ALERTARIA: COTAÇÕES diárias paradas (CRV)' '--estado diz o que faria'
end_case '--estado mostra o frescor do CRV sem alertar'

# --------------------------------------------------------------------------
# Frescor dos dados -- Wealthfolio
# --------------------------------------------------------------------------

wf_com_log() { # $1 = log das últimas 8h, $2 = log da última hora
    : >"$FAKE/wf_ps"
    printf '%s' "$1" >"$FAKE/wf_log_8h"
    printf '%s' "$2" >"$FAKE/wf_log_1h"
}

MERCADO_OK='2026-10-03T10:14:03Z  INFO wealthfolio_core::quotes::scheduler: 28: Periodic market data sync completed: 13 synced, 18 skipped, 0 failed
'
FALHA_CRV='2026-10-03T12:00:00Z  WARN wealthfolio_server::api::patrimonio_sync: 983: Patrimonio sync failed for source crv
'

begin_case
wf_com_log "$MERCADO_OK" ''
roda
assert_sem_alerta 'TITULO=WEALTHFOLIO' 'sincronização recente, sem falha, não alerta'
end_case 'Wealthfolio em dia não alerta'

begin_case
wf_com_log '' ''
roda
assert_alerta 'TITULO=WEALTHFOLIO sem sincronizar cotações' 'nenhuma sincronização nas últimas 8h'
end_case 'Wealthfolio sem batimento alerta'

begin_case
wf_com_log '2026-10-03T10:14:03Z  INFO wealthfolio_core::quotes::scheduler: 28: Periodic market data sync completed: 11 synced, 18 skipped, 2 failed
' ''
roda
assert_alerta 'TITULO=WEALTHFOLIO falha ao sincronizar cotações' 'a última sincronização falhou em 2 ativos'
assert_alerta '2 falha(s)' 'o corpo traz quantas'
assert_sem_alerta 'TITULO=WEALTHFOLIO sem sincronizar cotações' 'o batimento existe'
end_case 'Wealthfolio com cotações falhando alerta'

begin_case
wf_com_log "$MERCADO_OK" "$FALHA_CRV$FALHA_CRV$FALHA_CRV"
roda
assert_alerta 'TITULO=WEALTHFOLIO importação do CB/CRV falhando' '3 falhas na última hora'
assert_alerta 'fontes:' 'o corpo diz de qual fonte'
assert_alerta '3 crv' 'o corpo conta por fonte'
end_case 'importação falhando em série alerta'

begin_case
wf_com_log "$MERCADO_OK" "$FALHA_CRV$FALHA_CRV"
roda
assert_sem_alerta 'TITULO=WEALTHFOLIO importação' '2 falhas é um soluço, e não uma série'
end_case 'duas falhas de importação não alertam'

begin_case
# O contêiner colore o log. Com o ESC dentro da contagem de falhas, sem a limpeza
# o "2" fica colado ao "m" da sequência e a falha passaria despercebida.
VERMELHO=$(printf '\033[31m')
FIM=$(printf '\033[0m')
wf_com_log "2026-10-03T10:14:03Z  INFO wealthfolio_core::quotes::scheduler: 28: Periodic market data sync completed: 11 synced, 18 skipped, ${VERMELHO}2 failed${FIM}
" ''
roda
assert_alerta 'TITULO=WEALTHFOLIO falha ao sincronizar cotações' 'a contagem colorida de falhas é lida'
assert_alerta '2 falha(s)' 'o corpo traz a contagem limpa'
end_case 'log com cores ANSI é lido'

begin_case
roda
assert_sem_alerta 'TITULO=WEALTHFOLIO' 'sem o Wealthfolio nesta máquina não há o que medir'
end_case 'máquina sem o Wealthfolio não alerta frescor'

begin_case
wf_com_log '' "$FALHA_CRV$FALHA_CRV$FALHA_CRV"
roda --estado
[ "$EXIT_CODE" -eq 0 ] || fail "--estado deve sair zero (obtido $EXIT_CODE)"
[ -s "$ALERTAS" ] && fail "--estado não pode alertar (alertou: $(head -1 "$ALERTAS"))"
assert_saida 'frescor do Wealthfolio: sincronização de cotações 0x' '--estado mostra o batimento'
assert_saida 'ALERTARIA: WEALTHFOLIO sem sincronizar cotações' '--estado diz o que faria'
end_case '--estado mostra o frescor do Wealthfolio sem alertar'

# --------------------------------------------------------------------------
# Batimento da importação CB/CRV (a linha "run finished" que o patch 0008 grava)
# --------------------------------------------------------------------------

BATIDA='2026-10-08T15:45:00Z  INFO wealthfolio_server::api::patrimonio_sync: 912: Patrimonio sync run finished: cb=ready crv=ready
'

wf_importador() { # $1 = início do contêiner, $2 = intervalo (vazio = variável ausente), $3 = log do batimento
    wf_com_log "$MERCADO_OK" ''
    printf '%s\n' "$1" >"$FAKE/wf_inicio"
    if [ -n "$2" ]; then printf 'PATH=/usr/bin\nWF_PATRIMONIO_SYNC_INTERVAL_SECS=%s\n' "$2" >"$FAKE/wf_env"; else printf 'PATH=/usr/bin\n' >"$FAKE/wf_env"; fi
    printf '%s' "$3" >"$FAKE/wf_log_bat"
}

begin_case
wf_importador '2026-09-01T00:00:00Z' 900 "$BATIDA"
roda
assert_sem_alerta 'TITULO=WEALTHFOLIO importação do CB/CRV parada' 'há uma execução recente'
end_case 'importação com batimento recente não alerta'

begin_case
wf_importador '2026-09-01T00:00:00Z' 900 ''
roda
assert_alerta 'TITULO=WEALTHFOLIO importação do CB/CRV parada' 'sem nenhuma execução nos últimos 47 min'
assert_alerta '47 min' 'o corpo diz a janela'
assert_alerta 'patch 0008' 'o corpo avisa do contêiner antigo'
end_case 'importação sem batimento alerta'

begin_case
wf_importador "$(date -u +%Y-%m-%dT%H:%M:%SZ)" 900 ''
roda
assert_sem_alerta 'TITULO=WEALTHFOLIO importação do CB/CRV parada' 'contêiner recém-criado ainda não fechou um ciclo'
end_case 'contêiner novo demais não alerta o batimento'

begin_case
wf_importador '2026-09-01T00:00:00Z' 0 ''
roda
assert_sem_alerta 'TITULO=WEALTHFOLIO importação do CB/CRV parada' 'agendador desligado de propósito'
end_case 'agendador desligado (0) não alerta o batimento'

begin_case
wf_importador '2026-09-01T00:00:00Z' '' ''
roda
assert_sem_alerta 'TITULO=WEALTHFOLIO importação do CB/CRV parada' 'sem o intervalo no ambiente não dá para afirmar que devia rodar'
end_case 'sem o intervalo no ambiente não alerta o batimento'

begin_case
wf_importador '2026-09-01T00:00:00Z' 900 ''
roda --estado
[ "$EXIT_CODE" -eq 0 ] || fail "--estado deve sair zero (obtido $EXIT_CODE)"
[ -s "$ALERTAS" ] && fail "--estado não pode alertar (alertou: $(head -1 "$ALERTAS"))"
assert_saida 'batimento da importação CB/CRV: 0 execução(ões) nos últimos 47 min' '--estado mostra a contagem'
assert_saida 'ALERTARIA: WEALTHFOLIO importação do CB/CRV parada' '--estado diz o que faria'
end_case '--estado mostra o batimento da importação sem alertar'

# --------------------------------------------------------------------------
# Batimento da importação com o agendador por cron (patch 0007)
# --------------------------------------------------------------------------
# O cron tem precedência sobre o intervalo: o silêncio normal vai até o próximo
# disparo, então o vigia mede a partir do último disparo (America/Sao_Paulo).
# VIGIA_AGORA fixa o relógio. 2026-10-10 é sábado; o último disparo de
# `0 8,14 * * 1-5` foi na sexta, 14:00 em Brasília = 17:00Z.

CRON_PADRAO='0 8,14 * * 1-5'

wf_cron() { # $1 = início do contêiner, $2 = cron, $3 = log do batimento, $4 = agora (UTC)
    wf_com_log "$MERCADO_OK" ''
    printf '%s\n' "$1" >"$FAKE/wf_inicio"
    printf 'PATH=/usr/bin\nWF_PATRIMONIO_SYNC_CRON=%s\nWF_PATRIMONIO_SYNC_INTERVAL_SECS=900\n' "$2" >"$FAKE/wf_env"
    printf '%s' "$3" >"$FAKE/wf_log_bat"
    export VIGIA_AGORA
    VIGIA_AGORA=$(date -u -d "$4" +%s)
}

begin_case
wf_cron '2026-10-09T23:40:00Z' "$CRON_PADRAO" '' '2026-10-10T12:00:00Z'
roda
assert_sem_alerta 'TITULO=WEALTHFOLIO importação' 'sábado, contêiner subiu depois do último disparo: nada devia ter rodado'
end_case 'cron: contêiner posterior ao último disparo não alerta'

begin_case
wf_cron '2026-09-01T00:00:00Z' "$CRON_PADRAO" '' '2026-10-10T12:00:00Z'
roda
assert_alerta 'TITULO=WEALTHFOLIO importação do CB/CRV parada' 'o disparo de sexta 14:00 não deixou linha'
assert_alerta "cron '$CRON_PADRAO'" 'o corpo diz qual cron'
end_case 'cron: disparo sem linha alerta'

begin_case
wf_cron '2026-09-01T00:00:00Z' "$CRON_PADRAO" "$BATIDA" '2026-10-10T12:00:00Z'
roda
assert_sem_alerta 'TITULO=WEALTHFOLIO importação' 'o disparo deixou a linha'
end_case 'cron: disparo com linha não alerta'

begin_case
wf_cron '2026-09-01T00:00:00Z' "$CRON_PADRAO" '' '2026-10-06T11:10:00Z'
roda
assert_sem_alerta 'TITULO=WEALTHFOLIO importação' '10 min depois do disparo das 08:00 ainda está dentro da tolerância'
end_case 'cron: disparo recente demais não alerta'

begin_case
wf_cron '2026-09-01T00:00:00Z' "$CRON_PADRAO" '' '2026-10-06T12:00:00Z'
roda
assert_alerta 'TITULO=WEALTHFOLIO importação do CB/CRV parada' '60 min depois do disparo das 08:00, sem linha'
end_case 'cron: terça depois do disparo sem linha alerta'

begin_case
wf_cron '2026-09-01T00:00:00Z' 'não é cron' '' '2026-10-10T12:00:00Z'
roda
assert_sem_alerta 'TITULO=WEALTHFOLIO importação' 'cron ilegível: não dá para afirmar que devia rodar'
end_case 'cron ilegível não alerta o batimento'

begin_case
wf_cron '2026-09-01T00:00:00Z' '0 */3 * * *' '' '2026-10-10T16:00:00Z'
roda --estado
assert_saida "cron '0 */3 * * *' (há 62 min)" '--estado: último disparo 12:00 em Brasília (15:00Z), passo de 3 h'
end_case 'cron: passo */3 acha o disparo das 12:00'

begin_case
wf_cron '2026-09-01T00:00:00Z' '30 9 * * 7' '' '2026-10-10T12:00:00Z'
roda --estado
assert_saida "(há " 'domingo como 7 acha o disparo de domingo 09:30 em Brasília (12:30Z)'
assert_saida 'ALERTARIA: WEALTHFOLIO importação do CB/CRV parada' 'sem linha desde domingo'
end_case 'cron: domingo escrito como 7'

unset VIGIA_AGORA

dominio_com_health() {
    printf 'server {\n    server_name %s;\n}\n' "$1" >"$CASE_TMP/vhosts/$1"
    printf '%s' "$2" >"$FAKE/health_corpo"
}

begin_case
dominio_com_health wf.exemplo.test 'ok'
roda
assert_sem_alerta 'FORA DO AR' 'o Wealthfolio responde o texto ok e está no ar'
end_case '/health em texto puro "ok" (Wealthfolio) não é "fora do ar"'

begin_case
dominio_com_health app.exemplo.test '{"status":"ok"}'
roda
assert_sem_alerta 'FORA DO AR' 'o JSON compacto do Flask continua valendo'
end_case '/health em JSON "status":"ok" continua aceito'

begin_case
dominio_com_health app.exemplo.test '{"status":"degradado"}'
roda
assert_alerta 'TITULO=FORA DO AR: app.exemplo.test' 'um corpo sem ok alerta'
end_case '/health sem ok alerta fora do ar'

begin_case
dominio_com_health wf.exemplo.test 'ok, mas com banco fora'
roda
assert_alerta 'TITULO=FORA DO AR: wf.exemplo.test' 'só o corpo inteiro igual a ok vale; prefixo não'
end_case '/health que apenas começa com "ok" ainda alerta'

printf '1..%d\n' "$TOTAL"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d de %d testes falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf '# %d testes passaram\n' "$TOTAL"
