#!/usr/bin/env bash
# Testes herméticos do batimento da cópia fora do servidor no `backup-agent.sh`,
# sem SSH, sem Docker e sem VPS.
#
# POR QUE ESTE ARQUIVO EXISTE. Quem leva os dumps para fora do servidor é o
# BackupRestore, numa máquina Windows, e a tarefa agendada que o dispara foi
# achada desabilitada três vezes (02/09, 05/09 e 15/09/2026) sem que nada
# avisasse: os dumps continuavam nascendo aqui, e o `vigia.sh` só olhava para
# eles. Desde 15/09 o verbo `listar` grava `.ultima_busca`, e o vigia alerta
# quando esse marcador some ou envelhece.
#
# DESDE 02/10/2026, também as cópias de volume (`_volume_<carimbo>.tar.gz`, o
# SQLite do Wealthfolio): `listar` sem argumento continua mostrando só dumps,
# porque o BackupRestore instalado recusa a sincronização inteira diante de uma
# linha que não conhece; quem já sabe ler volumes pede `listar tudo`. E o piso
# de `apagar` é por tipo: uma cópia de volume mais nova não pode liberar a
# remoção do último dump.
#
# O QUE ESTÁ SOB TESTE, e por que cada caso importa:
#   - `listar` grava o marcador, inclusive quando não há dump nenhum: a busca
#     aconteceu, e é ela que se mede;
#   - nenhum outro verbo grava. `enviar` só acontece quando há dump novo, e o
#     `backup-db.sh` só produz dump quando o banco mudou, então medir por ele
#     alertaria justamente o projeto que está parado de propósito;
#   - `listar` continua listando quando não consegue gravar o marcador. Falhar
#     ali derrubaria a sincronização inteira por causa de uma medição.
#
# Uso:
#   docker run --rm -v "${PWD}:/repo:ro" bash:5.2 bash /repo/vps/tests/backup-agent_test.sh

set -u

# shellcheck disable=SC1007  # `CDPATH=` é prefixo de ambiente para um comando,
# não assinalamento com espaço sobrando. Mesmo motivo escrito em `instalar.sh`.
TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
AGENTE="$TESTS_DIR/../backup-agent.sh"
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
    DEST_TMP="$CASE_TMP/backups"
    MARCA="$DEST_TMP/.ultima_busca"
    SAIDA="$CASE_TMP/saida.txt"
    mkdir -p "$DEST_TMP"
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

# Um projeto com um dump no formato exato que o `backup-db.sh` produz.
com_dump() {
    local slug=$1 carimbo=$2
    mkdir -p "$DEST_TMP/$slug"
    printf 'conteudo-%s' "$carimbo" >"$DEST_TMP/$slug/${slug}_banco_${carimbo}.dump"
    printf 'abc123\n' >"$DEST_TMP/$slug/${slug}_banco_${carimbo}.dump.sha256"
}

# Uma cópia de volume no formato exato que o `backup-db.sh` produz.
com_volume() {
    local slug=$1 carimbo=$2
    mkdir -p "$DEST_TMP/$slug"
    printf 'volume-%s' "$carimbo" >"$DEST_TMP/$slug/${slug}_volume_${carimbo}.tar.gz"
    printf 'def456\n' >"$DEST_TMP/$slug/${slug}_volume_${carimbo}.tar.gz.sha256"
}

# Data de modificação, que é o que o agente usa para saber o mais recente.
idade() { touch -d "@$(( $(date +%s) - $2 ))" "$1"; }

# O verbo chega por `SSH_ORIGINAL_COMMAND`, como no servidor.
roda() {
    SSH_ORIGINAL_COMMAND="$*" DEST="$DEST_TMP" \
        bash "$AGENTE" >"$SAIDA" 2>&1
    EXIT_CODE=$?
}

idade_segundos() { echo $(( $(date +%s) - $(stat -c %Y "$1") )); }

# --------------------------------------------------------------------------

begin_case
com_dump mega_sena 20260913_064041
roda listar
assert_eq 0 "$EXIT_CODE" 'listar sai zero'
grep -Fq 'mega_sena/mega_sena_banco_20260913_064041.dump' "$SAIDA" \
    || fail 'listar deve mostrar o dump'
[ -f "$MARCA" ] || fail 'listar deve gravar .ultima_busca'
end_case 'listar lista os dumps e registra a busca'

begin_case
roda listar
assert_eq 0 "$EXIT_CODE" 'listar sem projeto sai zero'
[ -s "$SAIDA" ] && fail "sem projeto, a saída deve ser vazia (obtido: $(head -1 "$SAIDA"))"
[ -f "$MARCA" ] || fail 'a busca aconteceu mesmo sem dump, e precisa ficar registrada'
end_case 'listar sem nenhum dump também registra a busca'

begin_case
com_dump mega_sena 20260913_064041
: >"$MARCA"
touch -d "@$(( $(date +%s) - 80 * 3600 ))" "$MARCA"
[ "$(idade_segundos "$MARCA")" -ge 3600 ] || fail 'andaime: o marcador não envelheceu'
roda listar
[ "$(idade_segundos "$MARCA")" -lt 60 ] || fail 'listar deve renovar um marcador antigo'
end_case 'listar renova o marcador antigo'

begin_case
com_dump mega_sena 20260913_064041
roda enviar mega_sena/mega_sena_banco_20260913_064041.dump
assert_eq 0 "$EXIT_CODE" 'enviar sai zero'
assert_eq 'conteudo-20260913_064041' "$(cat "$SAIDA")" 'enviar despeja o dump'
[ -e "$MARCA" ] && fail 'enviar não pode registrar a busca'
end_case 'enviar não conta como busca'

begin_case
com_dump mega_sena 20260913_064041
roda estado
[ -e "$MARCA" ] && fail 'estado não pode registrar a busca'
roda verbo-que-nao-existe
[ "$EXIT_CODE" -ne 0 ] || fail 'verbo desconhecido deve sair não zero'
[ -e "$MARCA" ] && fail 'verbo desconhecido não pode registrar a busca'
end_case 'estado e verbo desconhecido não contam como busca'

begin_case
com_dump mega_sena 20260913_064041
chmod 555 "$DEST_TMP"
if [ -w "$DEST_TMP" ]; then
    # Root ignora a permissão. Não dá para exercitar o caso aqui, e fingir que
    # deu seria pior que pular: o teste passaria sem ter medido nada.
    printf '    (pulado: este usuário grava em diretório com modo 555 -- provavelmente root)\n'
else
    roda listar
    assert_eq 0 "$EXIT_CODE" 'marcador que não grava não pode derrubar a listagem'
    grep -Fq 'mega_sena_banco_20260913_064041.dump' "$SAIDA" \
        || fail 'a listagem precisa sair mesmo sem o marcador'
fi
chmod 755 "$DEST_TMP"
end_case 'listar não depende de conseguir gravar o marcador'

# --------------------------------------------------------------------------
# Cópias de volume

begin_case
com_dump mega_sena 20260913_064041
com_volume wealthfolio_teste 20261002_060000
roda listar
assert_eq 'mega_sena/mega_sena_banco_20260913_064041.dump 24 abc123' "$(cat "$SAIDA")" \
    'sem argumento, só os dumps: o BackupRestore antigo recusa linha desconhecida'
roda listar tudo
assert_eq 0 "$EXIT_CODE" 'listar tudo sai zero'
assert_eq 'mega_sena/mega_sena_banco_20260913_064041.dump 24 abc123
wealthfolio_teste/wealthfolio_teste_volume_20261002_060000.tar.gz 22 def456' "$(sort "$SAIDA")" \
    'listar tudo inclui as cópias de volume, no mesmo formato'
end_case 'listar só mostra volume para quem pede listar tudo'

begin_case
com_dump mega_sena 20260913_064041
roda listar qualquer
[ "$EXIT_CODE" -ne 0 ] || fail 'argumento desconhecido deve sair não zero'
[ -e "$MARCA" ] && fail 'listagem recusada não é busca'
end_case 'listar com argumento desconhecido é recusado'

begin_case
com_volume wealthfolio_teste 20261002_060000
roda enviar wealthfolio_teste/wealthfolio_teste_volume_20261002_060000.tar.gz
assert_eq 0 "$EXIT_CODE" 'enviar cópia de volume sai zero'
assert_eq 'volume-20261002_060000' "$(cat "$SAIDA")" 'enviar despeja a cópia'
# Os nomes recusados EXISTEM no disco: quem recusa é o formato, não a ausência
# do arquivo. O `.tmp` é a cópia em andamento do `backup-db.sh`.
for invalido in \
    wealthfolio_teste_volume_20261002_060000.tar \
    wealthfolio_teste_volume_20261002.tar.gz \
    wealthfolio_teste_banco_20261002_060000.tar.gz \
    .wealthfolio_teste_volume_20261002_070000.tar.gz.tmp; do
    printf 'x' >"$DEST_TMP/wealthfolio_teste/$invalido"
    roda enviar "wealthfolio_teste/$invalido"
    [ "$EXIT_CODE" -ne 0 ] || fail "nome fora do formato foi aceito: $invalido"
done
end_case 'enviar aceita a cópia de volume e recusa nome fora do formato'

begin_case
# O último dump de 2 dias e uma cópia de volume de agora, na mesma pasta. O
# piso é por tipo: nenhum dos dois pode sair.
com_dump mega_sena 20260930_030000
com_volume mega_sena 20261002_030000
idade "$DEST_TMP/mega_sena/mega_sena_banco_20260930_030000.dump" 172800
roda apagar mega_sena/mega_sena_banco_20260930_030000.dump
[ "$EXIT_CODE" -ne 0 ] || fail 'o último dump saiu porque havia volume mais novo'
grep -Fq 'é o dump mais recente' "$SAIDA" \
    || fail 'a recusa do dump precisa da frase que o BackupRestore reconhece'
[ -e "$DEST_TMP/mega_sena/mega_sena_banco_20260930_030000.dump" ] || fail 'o dump sumiu'
roda apagar mega_sena/mega_sena_volume_20261002_030000.tar.gz
[ "$EXIT_CODE" -ne 0 ] || fail 'a última cópia de volume não pode sair'
[ -e "$DEST_TMP/mega_sena/mega_sena_volume_20261002_030000.tar.gz" ] || fail 'a cópia sumiu'
end_case 'apagar recusa o mais recente de cada tipo, independente do outro'

begin_case
com_volume wealthfolio_teste 20261001_060000
com_volume wealthfolio_teste 20261002_060000
idade "$DEST_TMP/wealthfolio_teste/wealthfolio_teste_volume_20261001_060000.tar.gz" 86400
roda apagar wealthfolio_teste/wealthfolio_teste_volume_20261001_060000.tar.gz
assert_eq 0 "$EXIT_CODE" 'cópia antiga com substituta pode sair'
[ -e "$DEST_TMP/wealthfolio_teste/wealthfolio_teste_volume_20261001_060000.tar.gz" ] \
    && fail 'a cópia antiga continua lá'
[ -e "$DEST_TMP/wealthfolio_teste/wealthfolio_teste_volume_20261001_060000.tar.gz.sha256" ] \
    && fail 'o .sha256 da cópia antiga continua lá'
[ -e "$DEST_TMP/wealthfolio_teste/wealthfolio_teste_volume_20261002_060000.tar.gz" ] \
    || fail 'a cópia nova não podia sair'
end_case 'apagar remove a cópia de volume que já tem substituta'

printf '1..%d\n' "$TOTAL"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d de %d testes falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf '# %d testes passaram\n' "$TOTAL"
