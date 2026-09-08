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

printf '1..%d\n' "$TOTAL"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d de %d testes falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf '# %d testes passaram\n' "$TOTAL"
