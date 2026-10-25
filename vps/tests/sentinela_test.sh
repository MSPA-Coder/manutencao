#!/usr/bin/env bash
# Testes herméticos do sentinela de 5xx. O único efeito externo -- o envio do
# alerta -- é um script falso no lugar do `alerta.sh`, e todo o estado vive sob
# um diretório temporário.

set -u

# shellcheck disable=SC1007  # `CDPATH=` é prefixo de ambiente para um comando,
# não assinalamento com espaço sobrando. Mesmo motivo escrito em `instalar.sh`.
TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SENTINELA="$TESTS_DIR/../sentinela.sh"
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
    local expected=$1 actual=$2 description=$3
    [ "$actual" = "$expected" ] || fail "$description (esperado '$expected', obtido '$actual')"
}

assert_alerta() {
    local pattern=$1 description=$2
    grep -Fq -- "$pattern" "$ALERTAS" || fail "$description (ausente: $pattern)"
}

assert_sem_alerta() {
    local description=$1
    [ ! -s "$ALERTAS" ] || fail "$description (alertou: $(head -1 "$ALERTAS"))"
}

conta_alertas() { grep -c 'TITULO=' "$ALERTAS" 2>/dev/null || echo 0; }

begin_case() {
    CASE_FAILED=0
    CASE_TMP=$(mktemp -d "$SUITE_TMP/caso.XXXXXX")
    LOG="$CASE_TMP/erro5xx.log"
    ALERTAS="$CASE_TMP/alertas.txt"
    : >"$ALERTAS"
    mkdir -p "$CASE_TMP/bin" "$CASE_TMP/estado"

    # Falso `alerta.sh`: registra título e corpo em vez de falar com o Telegram.
    cat >"$CASE_TMP/bin/alerta.sh" <<'EOF'
#!/usr/bin/env bash
printf 'TITULO=%s\n' "$1" >>"$ALERTAS"
printf 'CORPO=%s\n' "${2:-}" >>"$ALERTAS"
exit 0
EOF
    chmod 755 "$CASE_TMP/bin/alerta.sh"
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
    LOG_5XX="$LOG" \
    ESTADO_DIR="$CASE_TMP/estado" \
    APP_LOCK_DIR="$CASE_TMP/locks" \
    JANELAS_DEPLOY="$CASE_TMP/janelas.log" \
        bash "$SENTINELA" "$@" >"$CASE_TMP/saida.txt" 2>&1
    EXIT_CODE=$?
}

linha() {
    # $1 host, $2 status, $3 rota
    printf '2026-09-08T12:00:00-03:00 host=%s status=%s metodo=GET rota=%s upstream=%s tempo=0.012\n' \
        "$1" "$2" "$3" "$2"
}

# ---------------------------------------------------------------------------

begin_case
roda
assert_eq 0 "$EXIT_CODE" 'log inexistente é o estado normal, não erro'
assert_sem_alerta 'log inexistente não deve alertar'
end_case 'sem log de 5xx, o sentinela cala e sai bem'

begin_case
{ linha app-a.example 500 /rota-um; linha app-a.example 500 /rota-um; } >"$LOG"
roda
assert_eq 0 "$EXIT_CODE" 'drenagem normal sai zero'
assert_eq 1 "$(conta_alertas)" 'duas linhas do mesmo host devem render UM alerta'
assert_alerta 'TITULO=5xx em app-a.example' 'o título identifica o host afetado'
assert_alerta '2 resposta(s) 5xx' 'o corpo traz a contagem'
assert_alerta '/rota-um' 'o corpo traz a rota'
end_case 'agrupa por host e conta as ocorrências'

begin_case
linha app-a.example 500 /rota-um >"$LOG"
roda
: >"$ALERTAS"
roda
assert_sem_alerta 'sem linha nova, não pode alertar de novo'
end_case 'a posição avança: não realerta o que já foi drenado'

begin_case
linha app-a.example 500 /rota-um >"$LOG"
roda
: >"$ALERTAS"
linha app-a.example 502 /rota-dois >>"$LOG"
roda
assert_eq 1 "$(conta_alertas)" 'linha nova deve alertar'
assert_alerta '/rota-dois' 'o alerta novo traz só o incidente novo'
if grep -Fq '/rota-um' "$ALERTAS"; then
    fail 'o alerta novo não deve repetir a linha já drenada'
fi
end_case 'só o que chegou depois da última execução entra no alerta'

begin_case
{ linha app-a.example 500 /a; linha app-b.example 503 /b; } >"$LOG"
roda
assert_eq 2 "$(conta_alertas)" 'dois hosts afetados devem render dois alertas'
assert_alerta 'TITULO=5xx em app-a.example' 'primeiro host alertado'
assert_alerta 'TITULO=5xx em app-b.example' 'segundo host alertado'
end_case 'um alerta por aplicação afetada'

begin_case
{ linha app-a.example 500 /a; linha app-a.example 500 /a; linha app-a.example 500 /a; } >"$LOG"
roda
: >"$ALERTAS"
# Rotação: o logrotate cria um arquivo NOVO com o mesmo nome. Aqui ele nasce
# MAIOR que a posição guardada -- o caso que só o inode detecta. Comparar
# apenas tamanho faria o sentinela pular estas linhas em silêncio.
rm -f "$LOG"
{ linha app-c.example 500 /depois-da-rotacao
  linha app-c.example 500 /depois-da-rotacao
  linha app-c.example 500 /depois-da-rotacao
  linha app-c.example 500 /depois-da-rotacao; } >"$LOG"
roda
assert_alerta '/depois-da-rotacao' 'após a rotação, as linhas novas têm de ser lidas'
assert_alerta '4 resposta(s) 5xx' 'após a rotação, lê o arquivo desde o começo'
end_case 'rotação com arquivo maior que a posição antiga não perde linha'

begin_case
linha app-a.example 500 /a >"$LOG"
roda
: >"$ALERTAS"
printf '' >"$LOG"
linha app-a.example 500 /b >>"$LOG"
roda
assert_alerta '/b' 'arquivo truncado recomeça do zero'
end_case 'truncamento também é detectado'

begin_case
{ linha app-a.example 500 /a; linha app-a.example 500 /a; } >"$LOG"
roda --estado
assert_eq 0 "$EXIT_CODE" '--estado sai zero'
assert_sem_alerta '--estado não pode alertar'
grep -Fq 'ALERTARIA' "$CASE_TMP/saida.txt" || fail '--estado deve dizer o que faria'
: >"$ALERTAS"
roda
assert_alerta 'TITULO=5xx em app-a.example' '--estado não pode consumir a posição'
end_case '--estado inspeciona sem alertar e sem consumir'

begin_case
linha app-a.example 500 /a >"$LOG"
chmod 000 "$LOG" 2>/dev/null
if [ -r "$LOG" ]; then
    # Root ignora a permissão. Não dá para exercitar o caso aqui, e fingir que
    # deu seria pior que pular: o teste passaria sem ter medido nada.
    printf '    (pulado: este usuário lê arquivo com modo 000 -- provavelmente root)\n'
else
    roda
    [ "$EXIT_CODE" -ne 0 ] || fail 'log ilegível deve sair não zero'
    assert_alerta 'TITULO=SENTINELA CEGO' 'log ilegível tem de alertar a própria cegueira'
fi
chmod 644 "$LOG" 2>/dev/null
end_case 'monitor que não consegue ler alerta em vez de calar'

begin_case
mkdir -p "$CASE_TMP/locks"
exec 8>"$CASE_TMP/locks/bancario.lock"
flock -n 8 || fail 'o teste não conseguiu segurar o lock'
linha bancario.example 502 /health >"$LOG"
roda
assert_sem_alerta 'deploy em andamento: o 502 da troca de contêiner não pode alertar'
: >"$ALERTAS"
flock -u 8
exec 8>&-
linha bancario.example 500 /depois >>"$LOG"
roda
assert_eq 1 "$(conta_alertas)" 'terminada a operação, o erro novo volta a alertar'
assert_alerta '/depois' 'o alerta traz só o que veio depois da operação'
if grep -Fq '/health' "$ALERTAS"; then
    fail 'o 502 da janela de deploy foi descartado e não pode reaparecer'
fi
end_case 'durante a operação de um app o 5xx é descartado; depois dela, volta a alertar'

begin_case
mkdir -p "$CASE_TMP/locks"
: >"$CASE_TMP/locks/bancario.lock"
linha bancario.example 500 /a >"$LOG"
roda
assert_eq 1 "$(conta_alertas)" 'lock existente mas livre não é operação em curso'
end_case 'arquivo de lock sem ninguém segurando não silencia o sentinela'

# ---------------------------------------------------------------------------
# Janelas de deploy (25/10/2026): o 502 da troca de contêiner não é incidente.

# O instante das linhas de `linha()`: 2026-09-08T12:00:00-03:00.
T0=$(date -u -d '2026-09-08 15:00:00' +%s)

# `linha_em <segundos depois de T0> <host> <status>`, com o fuso UTC do VPS.
linha_em() {
    printf '%s host=%s status=%s metodo=GET rota=/api/collector/configuration upstream=%s tempo=0.001\n' \
        "$(date -u -d "@$(( T0 + $1 ))" '+%Y-%m-%dT%H:%M:%S+00:00')" "$2" "$3" "$3"
}

janela() {  # `janela <domínio> <início> [fim]`, em segundos depois de T0
    printf 'inicio %s %s\n' "$1" "$(( T0 + $2 ))" >>"$CASE_TMP/janelas.log"
    [ -z "${3:-}" ] || printf 'fim %s %s\n' "$1" "$(( T0 + $3 ))" >>"$CASE_TMP/janelas.log"
}

begin_case
janela renda.example 0 60
{ linha renda.example 502 /a; linha_em 50 renda.example 502; } >"$LOG"
roda
assert_eq 0 "$EXIT_CODE" 'drenagem sai zero'
assert_sem_alerta '502 do domínio no meio do próprio deploy não alerta'
end_case 'a troca de contêiner de um deploy não vira alerta'

begin_case
janela renda.example 0 60
{ linha_em 30 renda.example 502; linha_em 30 bancario.example 502; } >"$LOG"
roda
assert_eq 1 "$(conta_alertas)" 'só o domínio sem deploy alerta'
assert_alerta 'TITULO=5xx em bancario.example' 'o outro domínio, no mesmo minuto, continua alertando'
end_case 'o deploy de um aplicativo não cala os outros'

begin_case
janela renda.example 0 60
linha_em 400 renda.example 502 >"$LOG"
roda
assert_alerta 'TITULO=5xx em renda.example' '502 minutos depois do fim do deploy é incidente'
end_case 'fora da janela (e da margem) o 5xx alerta normalmente'

begin_case
janela renda.example 0
{ linha_em 1000 renda.example 502; linha_em 2500 renda.example 502; } >"$LOG"
roda
assert_eq 1 "$(conta_alertas)" 'deploy sem fim cala por no máximo 30 min'
assert_alerta '1 resposta(s) 5xx' 'só a linha depois do teto alerta'
end_case 'deploy que morreu sem registrar o fim não cala o domínio para sempre'

begin_case
janela renda.example 0 60
printf 'lixo\nfim renda.example nao-e-numero\n' >>"$CASE_TMP/janelas.log"
linha_em 30 renda.example 502 >"$LOG"
roda
assert_eq 0 "$EXIT_CODE" 'linha estragada no registro não derruba o sentinela'
assert_sem_alerta 'e a janela válida continua valendo'
end_case 'registro de janelas com lixo é tolerado'

printf '1..%d\n' "$TOTAL"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d de %d testes falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf '# %d testes passaram\n' "$TOTAL"
