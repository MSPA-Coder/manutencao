#!/usr/bin/env bash
# Testes herméticos da verificação de BUSCA do `vigia.sh`, sem rede, sem
# Telegram e sem VPS.
#
# POR QUE ESTE ARQUIVO EXISTE: ver o cabeçalho de `backup-agent_test.sh`. O
# agente grava `.ultima_busca` a cada `listar`; aqui se prova que o vigia lê
# esse marcador, alerta quando ele some ou passa do limite, e não alerta em
# máquina que não produz backup.
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

printf '1..%d\n' "$TOTAL"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d de %d testes falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf '# %d testes passaram\n' "$TOTAL"
