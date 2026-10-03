#!/usr/bin/env bash
# Reinicia contêiner que o Docker marcou como `unhealthy`.
#
#   ./autocura.sh            faz o ciclo
#   ./autocura.sh --estado   mostra o que faria, sem tocar em nada
#
# POR QUE ISTO EXISTE: o Compose não age sobre health check. `restart:
# unless-stopped` reage a processo que morre, não a processo vivo e doente. Um
# app cujo banco caiu fica `unhealthy` e de pé, indefinidamente, servindo erro.
#
# POR QUE NÃO O `autoheal` EM CONTÊINER: ele exige montar
# /var/run/docker.sock. Quem fala com esse socket cria contêiner privilegiado,
# monta o disco do host e vira root na máquina. É privilégio grande demais
# para o problema. Aqui é um script como `ubuntu`, que já está no grupo docker.

set -uo pipefail

ALERTA=${ALERTA:-/home/ubuntu/alerta.sh}
ESTADO=${ESTADO:-/home/ubuntu/.cache/autocura}
TETO_TENTATIVAS=3       # depois disso, para de tentar e avisa uma vez
JANELA_TENTATIVAS=3600  # as tentativas contam dentro desta janela

mkdir -p "$ESTADO" 2>/dev/null

registrar() { logger -t autocura -- "$*"; }

alertar() {
    [ -x "$ALERTA" ] || { registrar "alerta.sh ausente: $*"; return 0; }
    ALERTA_JANELA=1800 "$ALERTA" "$1" "${2:-}" || true
}

# `unhealthy` nem sempre é sonda reprovada. Ao pausar um contêiner, o Docker
# desliga a sonda e o marca `unhealthy` sem contar falha nenhuma; despausado,
# ele continua assim até a sonda seguinte, um `interval:` depois (30 s no
# Wealthfolio). O `backup-db.sh` pausa todo dia o contêiner rotulado com
# `mspa.backup.volume` para copiar o SQLite, e reiniciar nessa janela derrubaria
# a cópia ao meio, ou o aplicativo logo depois dela, com alerta à toa. Medido
# no Docker 29.6.2: pausado ou recém-despausado, `FailingStreak` 0; com a
# sonda reprovando de verdade, 3. No VPS1, a primeira cópia (03/10/2026)
# deixou o Wealthfolio `unhealthy` por instantes, com 0 falhas.
#
# Poupa, então, o contêiner pausado (alguém o pausou de propósito, e uma pausa
# que não termina o vigia acusa pelo /health parado) e o que não teve nenhuma
# sonda reprovada. Qualquer outra leitura, inclusive um `inspect` que falhe,
# segue o caminho de sempre. Imprime o motivo de poupar.
poupar() {
    local leitura
    leitura=$(docker inspect -f '{{.State.Paused}} {{.State.Health.FailingStreak}}' "$1" 2>/dev/null) \
        || return 1
    case "$leitura" in
        "true "*) echo "pausado" ;;
        "false 0") echo "nenhuma sonda reprovada (é como o Docker marca o contêiner recém-despausado)" ;;
        *) return 1 ;;
    esac
}

# Contêineres doentes agora. `health=unhealthy` não inclui `starting`, então o
# período de carência declarado em `start_period:` é respeitado de graça.
doentes=$(docker ps --filter health=unhealthy --format '{{.Names}}' 2>/dev/null || true)

if [ "${1:-}" = "--estado" ]; then
    echo "doentes agora: ${doentes:-nenhum}"
    for nome in $doentes; do
        motivo=$(poupar "$nome") && echo "  $nome: não reinicia, $motivo"
    done
    for marca in "$ESTADO"/*; do
        [ -e "$marca" ] || continue
        echo "  $(basename "$marca"): $(cat "$marca" 2>/dev/null) tentativa(s), última $(date -d "@$(stat -c %Y "$marca")" '+%d/%m %H:%M')"
    done
    exit 0
fi

# Saudável de novo esquece o passado: senão um contêiner que teve um problema
# de manhã chegaria ao teto à tarde por causa dele.
for marca in "$ESTADO"/*; do
    [ -e "$marca" ] || continue
    nome=$(basename "$marca")
    estado_atual=$(docker inspect -f '{{.State.Health.Status}}' "$nome" 2>/dev/null || echo ausente)
    if [ "$estado_atual" = healthy ] || [ "$estado_atual" = ausente ]; then
        rm -f "$marca"
        registrar "$nome voltou a $estado_atual — contador zerado"
    fi
done

[ -z "$doentes" ] && exit 0

for nome in $doentes; do
    if motivo=$(poupar "$nome"); then
        registrar "$nome unhealthy, mas não reinicia: $motivo"
        continue
    fi

    marca="$ESTADO/$nome"
    tentativas=0
    if [ -f "$marca" ]; then
        idade=$(( $(date +%s) - $(stat -c %Y "$marca" 2>/dev/null || echo 0) ))
        if [ "$idade" -lt "$JANELA_TENTATIVAS" ]; then
            tentativas=$(cat "$marca" 2>/dev/null || echo 0)
        fi
    fi

    # Teto: reiniciar em laço um contêiner que não se cura mascara a falha e
    # ainda derruba a sessão de quem estiver usando, de novo e de novo.
    if [ "$tentativas" -ge "$TETO_TENTATIVAS" ]; then
        registrar "$nome no teto de $TETO_TENTATIVAS tentativas — não reinicia mais"
        ALERTA_JANELA=21600 "$ALERTA" \
            "DOENTE SEM CURA: $nome" \
            "Reiniciado $tentativas vezes na última hora e continua unhealthy.
A auto-cura desistiu — reiniciar em laço mascara a falha e derruba a sessão
de quem estiver usando. Precisa de olho humano.

$(docker inspect -f '{{range .State.Health.Log}}{{.Output}}{{end}}' "$nome" 2>/dev/null | tail -c 800)" || true
        continue
    fi

    tentativas=$(( tentativas + 1 ))
    printf '%s' "$tentativas" > "$marca"

    registrar "$nome unhealthy — reiniciando (tentativa $tentativas)"
    if docker restart "$nome" >/dev/null 2>&1; then
        alertar "REINICIADO: $nome" \
"O contêiner estava unhealthy e foi reiniciado (tentativa $tentativas de $TETO_TENTATIVAS).

Última saída da sonda antes do reinício:
$(docker inspect -f '{{range .State.Health.Log}}{{.Output}}{{end}}' "$nome" 2>/dev/null | tail -c 600)"
    else
        alertar "FALHA AO REINICIAR: $nome" \
"O contêiner está unhealthy e o \`docker restart\` também falhou."
    fi
done

exit 0
