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

printf '1..%d\n' "$TOTAL"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d de %d testes falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf '# %d testes passaram\n' "$TOTAL"
