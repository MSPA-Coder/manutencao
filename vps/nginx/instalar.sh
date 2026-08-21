#!/usr/bin/env bash
# Instala neste servidor a configuração do nginx que está em `vps/nginx/`.
#
#   ./instalar-nginx.sh            usa /home/ubuntu/nginx como origem
#   ./instalar-nginx.sh <diretorio>
#
# POR QUE ESTE SCRIPT EXISTE em vez de um punhado de `cp`: recarregar o nginx
# com configuração inválida derruba os QUATRO sites de uma vez. Aqui o
# `nginx -t` roda antes do reload e, se reprovar, o estado anterior é
# restaurado e o reload NÃO acontece. O pior desfecho possível passa a ser
# "nada mudou" em vez de "tudo caiu".
#
# Precisa de sudo: escreve em /etc/nginx.

set -uo pipefail

ORIGEM="${1:-/home/ubuntu/nginx}"
BACKUP="/home/ubuntu/nginx-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

VHOSTS=(conforto-termico controle-bancario controle-renda-variavel megasena)

# --------------------------------------------------------------------------
# Conferências antes de tocar em qualquer coisa
# --------------------------------------------------------------------------
faltando=0
for f in conf.d/00-comum.conf snippets/proxy-app.conf recusa-host-desconhecido "${VHOSTS[@]}"; do
    if [ ! -r "$ORIGEM/$f" ]; then
        echo "ERRO: falta $ORIGEM/$f" >&2
        faltando=1
    fi
done
[ "$faltando" -eq 0 ] || { echo "Nada foi alterado." >&2; exit 1; }

echo "== estado atual salvo em $BACKUP =="
sudo tar czf "$BACKUP" \
    /etc/nginx/sites-available /etc/nginx/sites-enabled \
    /etc/nginx/conf.d /etc/nginx/snippets 2>/dev/null
sudo chown ubuntu:ubuntu "$BACKUP"

echo "== instalando =="
sudo install -m 644 "$ORIGEM/conf.d/00-comum.conf"     /etc/nginx/conf.d/00-comum.conf
sudo install -m 644 "$ORIGEM/snippets/proxy-app.conf"  /etc/nginx/snippets/proxy-app.conf
sudo install -m 644 "$ORIGEM/recusa-host-desconhecido" /etc/nginx/sites-available/recusa-host-desconhecido
for f in "${VHOSTS[@]}"; do
    sudo install -m 644 "$ORIGEM/$f" "/etc/nginx/sites-available/$f"
    echo "  $f"
done
sudo ln -sf /etc/nginx/sites-available/recusa-host-desconhecido \
            /etc/nginx/sites-enabled/recusa-host-desconhecido
echo "  recusa-host-desconhecido (habilitado)"

echo
echo "== nginx -t =="
if ! sudo nginx -t; then
    echo >&2
    echo "REPROVOU — restaurando o estado anterior e NÃO recarregando." >&2
    sudo rm -f /etc/nginx/sites-enabled/recusa-host-desconhecido
    sudo tar xzf "$BACKUP" -C /
    if sudo nginx -t >/dev/null 2>&1; then
        echo "Estado anterior restaurado e válido. Os sites seguem no ar." >&2
    else
        echo "ATENÇÃO: a restauração também não validou. NÃO recarregue." >&2
        echo "Backup íntegro em $BACKUP" >&2
    fi
    exit 1
fi

echo
echo "== recarregando =="
sudo systemctl reload nginx
sleep 2
echo "nginx: $(systemctl is-active nginx)"

# --------------------------------------------------------------------------
# Prova de que o que se queria mudar mudou
#
# `nginx -t` diz que a sintaxe está boa; não diz que HTTP/2 ligou nem que a
# compressão passou a valer. Sem esta parte, "instalado" e "funcionando"
# viram a mesma palavra -- e não são.
# --------------------------------------------------------------------------
echo
echo "== conferindo o resultado =="
for d in conforto-mspa.duckdns.org megasena-mspa.duckdns.org \
         bancario-mspa.duckdns.org renda-mspa.duckdns.org; do
    versao=$(curl -sS --max-time 10 -o /dev/null -w '%{http_version}' "https://$d/health" 2>/dev/null || echo '?')
    saude=$(curl -sSL --max-time 10 "https://$d/health" 2>/dev/null | head -c 60)
    printf '  %-30s HTTP/%s  %s\n' "$d" "$versao" "$saude"
done

echo
echo -n "  gzip em CSS/JS: "
curl -sS --max-time 10 -H 'Accept-Encoding: gzip' -o /dev/null \
     -w '%{content_type} -> ' https://megasena-mspa.duckdns.org/static/base.js 2>/dev/null
curl -sS --max-time 10 -H 'Accept-Encoding: gzip' -D - -o /dev/null \
     https://megasena-mspa.duckdns.org/static/base.js 2>/dev/null \
     | grep -i '^content-encoding' || echo '(sem content-encoding — conferir gzip_types)'

echo
echo "  Host desconhecido na 443 (deve FALHAR o handshake):"
if curl -sS --max-time 10 -k -o /dev/null "https://163.176.214.214/" 2>/dev/null; then
    echo "    ainda responde — o default_server não pegou"
else
    echo "    recusado, como esperado"
fi

echo
echo "Se algo acima estiver errado, o estado anterior está em:"
echo "  $BACKUP"
echo "  sudo tar xzf $BACKUP -C / && sudo nginx -t && sudo systemctl reload nginx"
