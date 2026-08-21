#!/usr/bin/env bash
# Vigia horário: disco, endereços públicos, certificado e frescor do backup.
#
#   ./vigia.sh            faz o ciclo e alerta
#   ./vigia.sh --estado   mostra tudo, sem alertar
#
# Cada verificação aqui cobre uma falha que hoje não tem quem a perceba.
#
# A de frescor do backup fecha um buraco do `OnFailure=`: ele só dispara se o
# serviço RODAR e falhar. Timer desabilitado por engano, systemd que não
# disparou, máquina desligada na hora — em nenhum desses casos existe falha
# para notificar, e o backup simplesmente para em silêncio. Só a idade do
# último backup detecta isso.

set -uo pipefail

ALERTA=/home/ubuntu/alerta.sh
BACKUPS=/home/ubuntu/backups
DISCO_TETO=80          # % de uso a partir do qual alerta
BACKUP_MAX_HORAS=36    # ciclo é diário; 36h já é atraso, não variação
CERT_MIN_DIAS=15       # certbot renova aos 30; 15 significa que falhou 2x

DOMINIOS=(
    conforto-mspa.duckdns.org
    megasena-mspa.duckdns.org
    bancario-mspa.duckdns.org
    renda-mspa.duckdns.org
)

MODO="${1:-alertar}"
falhas=0

registrar() { logger -t vigia -- "$*"; }

# Janela larga: estas condições duram horas. Com a janela padrão de 15 min o
# vigia apitaria a cada execução até alguém agir.
alertar() {
    if [ "$MODO" = "--estado" ]; then
        echo "  ALERTARIA: $1"
        return 0
    fi
    ALERTA_JANELA=21600 "$ALERTA" "$1" "${2:-}" || true
    falhas=$(( falhas + 1 ))
}

# --------------------------------------------------------------------------
# Disco
# --------------------------------------------------------------------------
uso=$(df --output=pcent / 2>/dev/null | tail -1 | tr -dc '0-9')
[ "$MODO" = "--estado" ] && echo "disco: ${uso}% usado (teto ${DISCO_TETO}%)"
if [ -n "$uso" ] && [ "$uso" -ge "$DISCO_TETO" ]; then
    alertar "DISCO em ${uso}%" \
"Uso da raiz passou de ${DISCO_TETO}%.

$(df -h / | tail -1)

Maiores consumidores do Docker:
$(docker system df 2>/dev/null || echo '(docker indisponível)')

Cache de build costuma ser o culpado — o deploy constrói no servidor.
Para recuperar:  docker builder prune -f"
fi

# --------------------------------------------------------------------------
# Endereços públicos
#
# Bate no /health pela URL pública de propósito: assim o teste atravessa DNS,
# TLS, nginx, aplicação e banco. Uma sonda em 127.0.0.1 aprovaria um site que
# o mundo não alcança.
#
# `-L` porque os quatro não concordam sobre a barra final: os três Flask
# servem `/health`, o ControleBancario serve `/health/` e o `APPEND_SLASH` do
# Django responde 301 ao caminho sem barra. Seguir o redirecionamento não
# afrouxa a verificação — o critério de aprovação é o corpo conter
# `"status":"ok"`, que uma tela de login redirecionada não produziria.
# --------------------------------------------------------------------------
for dominio in "${DOMINIOS[@]}"; do
    corpo=$(curl -sSL --max-time 15 "https://$dominio/health" 2>&1)
    codigo=$(curl -sSL --max-time 15 -o /dev/null -w '%{http_code}' "https://$dominio/health" 2>/dev/null || echo 000)

    if [ "$MODO" = "--estado" ]; then
        echo "$dominio: HTTP $codigo  $(printf '%s' "$corpo" | head -c 80)"
    fi

    # Regex e não texto literal: o `jsonify` do Flask serializa compacto
    # (`"status":"ok"`) e o `JsonResponse` do Django põe espaço depois dos
    # dois-pontos (`"status": "ok"`). Espaço em JSON não é parte de contrato
    # nenhum — quem tem de ser tolerante é o verificador. A primeira versão
    # deste script comparava literal e reprovava o ControleBancario mesmo
    # depois de ele estar correto.
    if ! printf '%s' "$corpo" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"'; then
        alertar "FORA DO AR: $dominio" \
"GET https://$dominio/health devolveu HTTP $codigo.

Resposta:
$(printf '%s' "$corpo" | head -c 500)

A rota consulta o banco. 503 aqui significa aplicação de pé e banco
inalcançável; erro de conexão significa nginx ou o contêiner fora."
    fi

    # Certificado
    fim=$(echo | openssl s_client -servername "$dominio" -connect "$dominio:443" 2>/dev/null \
          | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -n "$fim" ]; then
        dias=$(( ( $(date -d "$fim" +%s) - $(date +%s) ) / 86400 ))
        [ "$MODO" = "--estado" ] && echo "    certificado: $dias dia(s)"
        if [ "$dias" -lt "$CERT_MIN_DIAS" ]; then
            alertar "CERTIFICADO vencendo: $dominio" \
"Faltam $dias dia(s) — vence em $fim.

O certbot renova aos 30 dias restantes. Chegar a $dias significa que a
renovação já falhou mais de uma vez.

Conferir:  sudo certbot renew --dry-run"
        fi
    fi
done

# --------------------------------------------------------------------------
# Frescor do backup — o que o OnFailure= não cobre
# --------------------------------------------------------------------------
for dir in "$BACKUPS"/*/; do
    [ -d "$dir" ] || continue
    slug=$(basename "$dir")
    marca="$dir/.ultima_conferencia"

    if [ ! -r "$marca" ]; then
        [ "$MODO" = "--estado" ] && echo "backup $slug: SEM MARCADOR"
        alertar "BACKUP sem marcador: $slug" \
"Não existe .ultima_conferencia em $dir — o ciclo nunca terminou aqui."
        continue
    fi

    horas=$(( ( $(date +%s) - $(stat -c %Y "$marca") ) / 3600 ))
    [ "$MODO" = "--estado" ] && echo "backup $slug: conferido há ${horas}h"

    if [ "$horas" -ge "$BACKUP_MAX_HORAS" ]; then
        alertar "BACKUP parado: $slug" \
"Última conferência há ${horas}h — o ciclo é diário.

Nenhuma falha foi notificada, então o serviço provavelmente não chegou a
rodar. Conferir o timer, não o script:

  systemctl status backup-db.timer
  systemctl list-timers backup-db.timer"
    fi
done

if [ "$MODO" != "--estado" ]; then
    registrar "ciclo concluído — $falhas alerta(s)"
fi
exit 0
