#!/usr/bin/env bash
# Envia um alerta para o Telegram.
#
#   ./alerta.sh "título" "corpo"          alerta livre
#   ./alerta.sh --unidade NOME.service    modo OnFailure=, anexa o log da unidade
#   ./alerta.sh --teste                   prova de vida do canal
#
# REGRA CENTRAL: este script NUNCA sai com código diferente de zero.
#
# Ele é alvo de `OnFailure=`. Se falhasse, o systemd registraria uma segunda
# falha — a da notificação — e o `OnFailure=` dessa unidade poderia disparar
# de novo. Um alerta que não sai não pode virar o segundo incidente. Quando o
# envio falha, o motivo vai para o journal e o código de saída continua zero.

set -uo pipefail   # sem -e de propósito: nenhuma falha aqui pode abortar

CONFIG=/home/ubuntu/.secrets/telegram.env
ESTADO=/home/ubuntu/.cache/alerta

# Mesma mensagem dentro da janela não é reenviada. Padrão de 15 min serve para
# falha aguda; quem alerta sobre condição que dura horas (disco cheio, backup
# velho) passa uma janela maior por `ALERTA_JANELA`, senão apitaria a cada
# verificação até alguém agir — e canal que apita demais é canal que se
# silencia.
JANELA_REPETICAO=${ALERTA_JANELA:-900}

registrar() { logger -t alerta -- "$*"; }

# --------------------------------------------------------------------------
# Credencial
#
# O token entra no `curl` por `--config -` (stdin), nunca como argumento de
# linha de comando: argumento aparece em `ps` para qualquer processo do host.
# --------------------------------------------------------------------------
if [ ! -r "$CONFIG" ]; then
    registrar "ERRO: $CONFIG ausente ou ilegível — alerta perdido"
    exit 0
fi

TELEGRAM_BOT_TOKEN=""; TELEGRAM_CHAT_ID=""
# shellcheck disable=SC1090
. "$CONFIG"

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    registrar "ERRO: token ou chat id vazio em $CONFIG — alerta perdido"
    exit 0
fi

# --------------------------------------------------------------------------
# Monta a mensagem
# --------------------------------------------------------------------------
HOST=$(hostname -s 2>/dev/null || echo desconhecido)
QUANDO=$(date '+%d/%m %H:%M %Z')

case "${1:-}" in
    --unidade)
        UNIDADE="${2:-desconhecida}"
        TITULO="FALHA: $UNIDADE"
        CORPO=$(systemctl show "$UNIDADE" -p Result --value 2>/dev/null)
        CORPO="resultado: ${CORPO:-?}

últimas linhas do log:
$(journalctl -u "$UNIDADE" -n 15 --no-pager -o cat 2>/dev/null || echo '(log indisponível)')"
        ;;
    --teste)
        TITULO="Teste do canal de alerta"
        CORPO="Se esta mensagem chegou, o caminho falha -> Telegram está de pé."
        ;;
    "")
        registrar "ERRO: chamado sem argumento — alerta perdido"
        exit 0
        ;;
    *)
        TITULO="$1"
        CORPO="${2:-}"
        ;;
esac

MENSAGEM="[$HOST] $TITULO
$QUANDO

$CORPO"

# Telegram recusa mensagem acima de 4096 caracteres. Cortar é melhor que
# perder: o título e o começo do log são a parte que orienta.
MENSAGEM=$(printf '%s' "$MENSAGEM" | cut -c1-3900)

# --------------------------------------------------------------------------
# Antirrepetição
#
# Um contêiner que oscila dispararia o mesmo alerta a cada verificação, e um
# canal que apita demais é um canal que se silencia. Mensagem idêntica dentro
# da janela é registrada no journal e não reenviada.
# --------------------------------------------------------------------------
mkdir -p "$ESTADO" 2>/dev/null
IMPRESSAO=$(printf '%s' "$TITULO" | sha256sum | cut -c1-32)
MARCA="$ESTADO/$IMPRESSAO"

if [ -f "$MARCA" ]; then
    IDADE=$(( $(date +%s) - $(stat -c %Y "$MARCA" 2>/dev/null || echo 0) ))
    if [ "$IDADE" -lt "$JANELA_REPETICAO" ]; then
        registrar "suprimido (repetido há ${IDADE}s): $TITULO"
        exit 0
    fi
fi

# --------------------------------------------------------------------------
# Envio
#
# Sem `parse_mode`: a mensagem carrega linha de log, que pode conter `<`, `&`
# ou `_`. Em HTML ou Markdown o Telegram recusaria a mensagem inteira por erro
# de sintaxe — justamente quando ela mais importa. Texto puro sempre entrega.
# --------------------------------------------------------------------------
RESPOSTA=$(
    curl -sS --max-time 20 --retry 2 --retry-delay 3 \
         --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
         --data-urlencode "text=${MENSAGEM}" \
         --data-urlencode "disable_web_page_preview=true" \
         --config - <<EOF 2>&1
url = "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
EOF
)

if printf '%s' "$RESPOSTA" | grep -q '"ok":true'; then
    touch "$MARCA" 2>/dev/null
    registrar "enviado: $TITULO"
else
    # A resposta pode conter o motivo (chat não encontrado, token revogado).
    # Não contém o token: ele vai no `url`, que o curl não ecoa.
    registrar "ERRO ao enviar: $TITULO — $(printf '%s' "$RESPOSTA" | head -c 300)"
fi

exit 0
