#!/usr/bin/env bash
# Guarda dos timers systemd: nenhum timer monotônico pode declarar `Persistent=true`.
#
# `Persistent=` só vale para `OnCalendar`. Num timer com `OnBootSec` ou `OnUnitActiveSec`
# ele não recupera nada e, sob o systemd 259 (Ubuntu 26.04, VPS2), deixou o `vigia.timer`
# em `elapsed` sem próxima execução depois de um reinício: cinco dias sem vigia, com o
# timer "ativo" para o `systemctl is-active`. A checagem é sobre o TEXTO dos arquivos que o
# instalador entrega, e é isso que a torna hermética: não depende de systemd nem de VPS.

set -u

# shellcheck disable=SC1007  # `CDPATH=` é prefixo de ambiente para um comando.
TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1007
VPS_DIR=$(CDPATH= cd -- "$TESTS_DIR/.." && pwd)
TOTAL=0
FAILED=0

fail() {
    printf '    FALHA: %s\n' "$1" >&2
    FAILED=$((FAILED + 1))
}

# Diretivas ativas: ignora linhas de comentário e espaços.
diretivas() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

eh_monotonico() { diretivas "$1" | grep -qE '^(OnBootSec|OnStartupSec|OnUnitActiveSec|OnUnitInactiveSec)='; }
declara_persistent() { diretivas "$1" | grep -qE '^Persistent=true'; }

# Sem piso, um glob que não casa nada passaria vazio.
timers=("$VPS_DIR"/*.timer)
TOTAL=$((TOTAL + 1))
if [ "${#timers[@]}" -lt 5 ] || [ ! -f "${timers[0]}" ]; then
    fail "esperava ao menos 5 timers em vps/, achei ${#timers[@]}"
fi

monotonicos=0
for t in "${timers[@]}"; do
    nome=$(basename -- "$t")
    if eh_monotonico "$t"; then
        monotonicos=$((monotonicos + 1))
        TOTAL=$((TOTAL + 1))
        if declara_persistent "$t"; then
            fail "$nome é monotônico e declara Persistent=true (só vale para OnCalendar; deixou o vigia parado no VPS2)"
        fi
    fi
done

# Sem monotônicos a varredura acima seria vácua.
TOTAL=$((TOTAL + 1))
[ "$monotonicos" -ge 3 ] || fail "esperava ao menos 3 timers monotônicos, achei $monotonicos"

# O vigia é o caso que motivou a guarda: precisa continuar sendo monotônico e agendável.
TOTAL=$((TOTAL + 1))
eh_monotonico "$VPS_DIR/vigia.timer" || fail "vigia.timer deixou de ter OnBootSec/OnUnitActiveSec"

# Timer com OnCalendar continua livre para usar Persistent=true (backup e expurgo dependem disso).
TOTAL=$((TOTAL + 1))
declara_persistent "$VPS_DIR/backup-db.timer" || fail "backup-db.timer perdeu Persistent=true (é OnCalendar; precisa recuperar a execução perdida)"

if [ "$FAILED" -ne 0 ]; then
    printf '%s de %s verificações falharam\n' "$FAILED" "$TOTAL" >&2
    exit 1
fi
printf 'OK: %s verificações\n' "$TOTAL"
