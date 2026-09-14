#!/usr/bin/env bash
# Instala neste servidor a configuração do nginx que está em `vps/nginx/`.
#
#   ./instalar-nginx.sh            usa /home/ubuntu/nginx como origem
#   ./instalar-nginx.sh <diretorio>
#
# POR QUE ESTE SCRIPT EXISTE em vez de um punhado de `cp`: recarregar o nginx
# com configuração inválida derruba de uma vez TODOS os sites da máquina. Aqui
# o `nginx -t` roda antes do reload e, se reprovar, o estado anterior é
# restaurado e o reload NÃO acontece. O pior desfecho possível passa a ser
# "nada mudou" em vez de "tudo caiu".
#
# Precisa de sudo: escreve em /etc/nginx.

set -uo pipefail

ORIGEM="${1:-/home/ubuntu/nginx}"
BACKUP="/home/ubuntu/nginx-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

# Os vhosts são os que existirem em ORIGEM — que o README já define como "um
# diretório controlado pelo operador", ou seja, o lugar onde se declara o que
# ESTA máquina serve.
#
# POR QUE DEIXOU DE SER UMA LISTA (13/09/2026): era `(conforto-termico
# controle-bancario controle-renda-variavel megasena portal)` e o script
# RECUSAVA rodar se faltasse qualquer um dos cinco. Num servidor que serve só o
# portal — o caso do segundo VPS — isso não é conferência de integridade, é uma
# parede: o instalador não roda, e a saída vira configurar o nginx à mão, que é
# exatamente o que este repositório existe para não precisar fazer.
#
# A GUARDA QUE IMPORTA CONTINUA: origem sem nenhum vhost é erro, e as peças
# compartilhadas continuam obrigatórias. O que se perdeu foi "exatamente estes
# cinco"; o que se manteve foi "não instale a partir de uma origem vazia ou
# incompleta", que é a propriedade que evitava o estrago de verdade.
descobrir_vhosts() {
    local arquivo
    for arquivo in "$ORIGEM"/*; do
        [ -f "$arquivo" ] || continue
        case "$arquivo" in
            *.md|*.sh) continue ;;
            */recusa-host-desconhecido) continue ;;
        esac
        basename "$arquivo"
    done
}

mapfile -t VHOSTS < <(descobrir_vhosts)

# --------------------------------------------------------------------------
# Conferências antes de tocar em qualquer coisa
# --------------------------------------------------------------------------
faltando=0
for f in conf.d/00-comum.conf snippets/proxy-app.conf recusa-host-desconhecido; do
    if [ ! -r "$ORIGEM/$f" ]; then
        echo "ERRO: falta $ORIGEM/$f" >&2
        faltando=1
    fi
done

# Instalar "nenhum vhost" e recarregar o nginx com sucesso seria a pior saída
# possível: o servidor pararia de atender os sites e o script diria que deu
# certo.
if [ "${#VHOSTS[@]}" -eq 0 ]; then
    echo "ERRO: nenhum vhost encontrado em $ORIGEM." >&2
    echo "      (esperado: um arquivo por site, sem extensão, ao lado de conf.d/)" >&2
    faltando=1
fi

[ "$faltando" -eq 0 ] || { echo "Nada foi alterado." >&2; exit 1; }

echo "== vhosts encontrados em $ORIGEM =="
printf '  %s\n' "${VHOSTS[@]}"
echo

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
# Os domínios saem dos vhosts que ACABARAM de ser instalados, e não de uma
# lista escrita aqui — mesma decisão que o `tests/nginx_test.sh` já tomava ao
# tirar os domínios das linhas `ssl_certificate`. Antes, esta seção conferia os
# cinco domínios da frota estivesse-se em que servidor estivesse: rodado no
# segundo VPS, ele aprovaria com folga cinco sites que quem respondia era a
# OUTRA máquina, e não teria testado nada do que acabou de instalar.
dominios_instalados() {
    local f
    for f in "${VHOSTS[@]}"; do
        sed -nE 's/^[[:space:]]*server_name[[:space:]]+//p' "$ORIGEM/$f" 2>/dev/null \
            | sed -E 's/;.*$//'
    done | tr ' ' '\n' | sed '/^$/d; /^_$/d' | sort -u
}

echo
echo "== conferindo o resultado =="
mapfile -t DOMINIOS < <(dominios_instalados)
for d in "${DOMINIOS[@]}"; do
    versao=$(curl -sS --max-time 10 -o /dev/null -w '%{http_version}' "https://$d/health" 2>/dev/null || echo '?')
    saude=$(curl -sSL --max-time 10 "https://$d/health" 2>/dev/null | head -c 60)
    printf '  %-30s HTTP/%s  %s\n' "$d" "$versao" "$saude"
done

# O gzip é configuração compartilhada (`conf.d/00-comum.conf`), então qualquer
# domínio desta máquina serve de amostra. Era o megasena fixo aqui, que num VPS
# sem megasena testaria a máquina errada.
if [ "${#DOMINIOS[@]}" -gt 0 ]; then
    amostra="${DOMINIOS[0]}"
    echo
    echo -n "  gzip em CSS/JS ($amostra): "
    curl -sS --max-time 10 -H 'Accept-Encoding: gzip' -o /dev/null \
         -w '%{content_type} -> ' "https://$amostra/static/base.js" 2>/dev/null
    curl -sS --max-time 10 -H 'Accept-Encoding: gzip' -D - -o /dev/null \
         "https://$amostra/static/base.js" 2>/dev/null \
         | grep -i '^content-encoding' || echo '(sem content-encoding — conferir gzip_types)'
fi

# O teste bate em 127.0.0.1 com um `Host`/SNI que não é de ninguém, em vez do
# IP público chumbado (era o `163.176.214.214`, do primeiro VPS). Assim ele
# prova o `default_server` DESTA máquina — do outro jeito, rodado no segundo
# servidor, ele estaria conferindo o nginx do primeiro pela internet.
echo
echo "  Host desconhecido na 443 (deve FALHAR o handshake):"
if curl -sS --max-time 10 -k -o /dev/null \
        --resolve "host-que-nao-existe.invalid:443:127.0.0.1" \
        "https://host-que-nao-existe.invalid/" 2>/dev/null; then
    echo "    ainda responde — o default_server não pegou"
else
    echo "    recusado, como esperado"
fi

echo
echo "Se algo acima estiver errado, o estado anterior está em:"
echo "  $BACKUP"
echo "  sudo tar xzf $BACKUP -C / && sudo nginx -t && sudo systemctl reload nginx"
