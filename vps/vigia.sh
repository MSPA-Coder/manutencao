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
NGINX_HABILITADOS=${NGINX_HABILITADOS:-/etc/nginx/sites-enabled}
DISCO_TETO=80          # % de uso a partir do qual alerta
BACKUP_MAX_HORAS=36    # ciclo é diário; 36h já é atraso, não variação
CERT_MIN_DIAS=15       # certbot renova aos 30; 15 significa que falhou 2x
REBOOT_MAX_DIAS=3      # tolera o fim de semana; não deixa acumular semanas

# Os domínios são lidos dos vhosts habilitados NESTE servidor.
#
# POR QUE DEIXOU DE SER UMA LISTA (13/09/2026): a lista fixa dizia "a frota", o
# que era sinônimo de "esta máquina" enquanto havia uma só. Com um segundo VPS
# ela passa a descrever, em parte, a OUTRA máquina — o vigia de um servidor
# alertaria sobre aplicações que não são dele, e a pergunta "de qual máquina
# veio este alerta?" viraria adivinhação. O nginx desta caixa já sabe a
# resposta certa.
#
# É a mesma decisão que o `tests/nginx_test.sh` deste repositório já tinha
# tomado, pelo mesmo motivo, e que está escrita lá: "acrescentar um projeto à
# frota não pode exigir que alguém lembre de editar este teste também".
#
# `grep -R` e NÃO `-r`: `sites-enabled/` é um diretório de LINKS, e o `-r` não
# os segue. Conferido no VPS — com `-r` a saída é VAZIA, e um vigia cego não
# teria como se queixar da própria cegueira.
#
# `server_name _` fica de fora: são o `default` do pacote do Ubuntu e o
# `recusa-host-desconhecido`, que existem justamente para tratar o que não é
# domínio nosso.
descobrir_dominios() {
    grep -RhE '^[[:space:]]*server_name[[:space:]]' "$NGINX_HABILITADOS"/ 2>/dev/null \
        | sed -E 's/^[[:space:]]*server_name[[:space:]]+//; s/;.*$//' \
        | tr ' ' '\n' \
        | sed '/^$/d; /^_$/d' \
        | sort -u
}

mapfile -t DOMINIOS < <(descobrir_dominios)

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
# Vigia que não vigia nada precisa dizer isso em voz alta. Silêncio aqui seria
# lido como "tudo bem" — que é exatamente o modo de falha que este script
# existe para não ter.
if [ "${#DOMINIOS[@]}" -eq 0 ]; then
    [ "$MODO" = "--estado" ] && echo "dominios: NENHUM encontrado em $NGINX_HABILITADOS"
    alertar "VIGIA CEGO: nenhum domínio para verificar" \
"Nenhum \`server_name\` foi encontrado em $NGINX_HABILITADOS.

Ou o nginx desta máquina não serve nenhum vhost, ou o diretório mudou de
lugar. Enquanto isto durar, nenhuma aplicação está sendo verificada aqui.

  ls -l $NGINX_HABILITADOS
  nginx -T | grep server_name"
fi

for dominio in "${DOMINIOS[@]}"; do
    corpo=$(curl -sSL --max-time 15 "https://$dominio/health" 2>&1)
    codigo=$(curl -sSL --max-time 15 -o /dev/null -w '%{http_code}' "https://$dominio/health" 2>/dev/null || echo 000)

    if [ "$MODO" = "--estado" ]; then
        echo "$dominio: HTTP $codigo  $(printf '%s' "$corpo" | head -c 80)"
    fi

    # Regex e não texto literal: o `jsonify` do Flask serializa compacto
    # (`"status":"ok"`) e o `JsonResponse` do Django põe espaço depois dos
    # dois-pontos (`"status": "ok"`). Espaço em JSON não é parte de contrato,
    # portanto o verificador aceita as duas serializações.
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

# --------------------------------------------------------------------------
# Reboot pendente
#
# unattended-upgrades instala patches de segurança mas não reinicia sozinho
# (Automatic-Reboot fica desligado de propósito — reboot dos 4 apps junto é
# decisão de horário, não de script). Sem este aviso, um kernel corrigido
# fica parado sem rodar por tempo indefinido e ninguém percebe.
# --------------------------------------------------------------------------
if [ -f /var/run/reboot-required ]; then
    dias=$(( ( $(date +%s) - $(stat -c %Y /var/run/reboot-required) ) / 86400 ))
    [ "$MODO" = "--estado" ] && echo "reboot pendente: há ${dias} dia(s)"
    if [ "$dias" -ge "$REBOOT_MAX_DIAS" ]; then
        alertar "REBOOT pendente há ${dias} dia(s)" \
"$(cat /var/run/reboot-required.pkgs 2>/dev/null || echo '(lista de pacotes indisponível)')

Containers têm restart automático (unless-stopped). Escolha um horário de
baixo uso, reinicie e confira o menu do bot do Telegram em seguida."
    fi
else
    [ "$MODO" = "--estado" ] && echo "reboot pendente: nao"
fi

if [ "$MODO" != "--estado" ]; then
    registrar "ciclo concluído — $falhas alerta(s)"
fi
exit 0
