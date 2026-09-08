#!/usr/bin/env sh
# Teste hermético da configuração do Nginx: `nginx -t` sobre os vhosts
# versionados, sem rede, sem VPS e sem certificado de verdade.
#
# POR QUE EXISTE: os cinco vhosts, o `conf.d/00-comum.conf` e o
# `snippets/proxy-app.conf` são instalados no servidor por `nginx/instalar.sh`
# e só então testados -- ou seja, o primeiro a descobrir um erro de sintaxe, um
# `include` com caminho errado ou um `limit_req zone=` apontando para uma zona
# inexistente era o servidor de produção. `nginx -t` responde isso em segundos,
# antes do push.
#
# O QUE O ANDAIME SUBSTITUI, E POR QUÊ ISSO NÃO ENFRAQUECE O TESTE: os vhosts
# referenciam certificados do Let's Encrypt e dois arquivos que o certbot
# escreve. Nada disso existe fora do servidor, e nada disso é o que se quer
# testar aqui. O andaime cria certificados autoassinados e versões mínimas
# desses dois arquivos, e o `nginx -t` continua conferindo exatamente o que
# está versionado neste repositório: diretivas, aninhamento, includes
# resolvíveis e referência de zona.
#
# O QUE ELE NÃO COBRE, DELIBERADAMENTE: validade de certificado, alcance dos
# `proxy_pass` e comportamento em tempo de execução. Isso é trabalho do
# `deploy.sh` (sonda `/health` pública) e do `vigia.sh`.
#
# A IMAGEM É `nginx:1.24` E ISSO NÃO É DETALHE: é a versão que o Ubuntu 24.04
# do VPS entrega, e é a mesma compatibilidade que os vhosts declaram ao usar
# `listen ... ssl http2` em vez de `http2 on;`. Numa imagem mais nova o teste
# aprova a mesma configuração, mas passa a avisar sobre uma diretiva que o
# servidor real ainda exige -- ou seja, testaria outro servidor. Quando o VPS
# subir de versão, esta linha sobe junto, deliberadamente.
#
# Uso:
#   docker run --rm -v "${PWD}:/repo:ro" nginx:1.24 sh /repo/vps/tests/nginx_test.sh

set -eu

REPO=${REPO:-/repo}
FONTE="$REPO/vps/nginx"
ANDAIME=$(mktemp -d)
# `trap` em vez de remoção no fim: o diretório sai mesmo quando o `nginx -t`
# reprova e o `set -e` encerra o script antes da última linha.
trap 'rm -rf "$ANDAIME"' EXIT

# ---------------------------------------------------------------------------
# Peças que o certbot escreve no servidor e que não vivem neste repositório.
# ---------------------------------------------------------------------------
mkdir -p /etc/letsencrypt

# Versão mínima do arquivo do certbot: só o suficiente para o `include` do
# vhost resolver. As opções reais de TLS são responsabilidade do certbot no
# servidor, não deste repositório -- testá-las aqui seria testar o certbot.
cat >/etc/letsencrypt/options-ssl-nginx.conf <<'EOF'
ssl_session_cache shared:le_nginx_SSL:10m;
ssl_session_timeout 1440m;
ssl_session_tickets off;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
EOF

# `-dsaparam` gera em milissegundos o que a forma normal levaria minutos. O
# arquivo só precisa ser um PEM de parâmetros DH válido para o `nginx -t`
# aceitá-lo; ele nunca protege conexão nenhuma.
openssl dhparam -dsaparam -out /etc/letsencrypt/ssl-dhparams.pem 2048 2>/dev/null

# ---------------------------------------------------------------------------
# Um certificado autoassinado por domínio.
#
# Os domínios saem das próprias linhas `ssl_certificate` dos vhosts, e não de
# uma lista escrita aqui: acrescentar um projeto à frota não pode exigir que
# alguém lembre de editar este teste também.
# ---------------------------------------------------------------------------
DOMINIOS=$(grep -rh '^\s*ssl_certificate\s' "$FONTE" \
           | sed -n 's#.*/etc/letsencrypt/live/\([^/]*\)/.*#\1#p' \
           | sort -u)

[ -n "$DOMINIOS" ] || { echo "FALHOU: nenhum domínio encontrado nos vhosts." >&2; exit 1; }

for dominio in $DOMINIOS; do
    mkdir -p "/etc/letsencrypt/live/$dominio"
    openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
        -subj "/CN=$dominio" \
        -keyout "/etc/letsencrypt/live/$dominio/privkey.pem" \
        -out "/etc/letsencrypt/live/$dominio/fullchain.pem" 2>/dev/null
done

# ---------------------------------------------------------------------------
# O andaime propriamente dito.
#
# `include` relativo (`snippets/proxy-app.conf`) é resolvido pelo nginx contra
# o prefixo, então `-p` precisa apontar para a raiz onde `snippets/` está.
# ---------------------------------------------------------------------------
mkdir -p "$ANDAIME/conf.d" "$ANDAIME/sites" "$ANDAIME/snippets" "$ANDAIME/logs"
cp "$FONTE"/conf.d/*.conf "$ANDAIME/conf.d/"
cp "$FONTE"/snippets/*.conf "$ANDAIME/snippets/"

# Os vhosts não têm extensão (`megasena`, `conforto-termico`, ...), então
# nenhuma regra por extensão os alcança -- mesma armadilha que o `.gitattributes`
# deste repositório já teve de cobrir por caminho.
for vhost in "$FONTE"/*; do
    [ -f "$vhost" ] || continue
    case "$vhost" in
        *.md|*.sh) continue ;;
    esac
    cp "$vhost" "$ANDAIME/sites/$(basename "$vhost").conf"
done

VHOSTS=$(find "$ANDAIME/sites" -name '*.conf' | wc -l)
[ "$VHOSTS" -gt 0 ] || { echo "FALHOU: nenhum vhost copiado para o andaime." >&2; exit 1; }

# `gzip on;` vem do nginx.conf do pacote do Ubuntu, não deste repositório; sem
# ele o `gzip_vary`/`gzip_types` do 00-comum.conf continua válido para o `-t`,
# mas declarar aqui reproduz o ambiente real de leitura.
cat >"$ANDAIME/nginx.conf" <<'EOF'
worker_processes 1;
error_log /dev/stderr warn;
pid nginx.pid;

events { worker_connections 1024; }

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log off;
    client_body_temp_path client_body_temp;
    proxy_temp_path proxy_temp;
    fastcgi_temp_path fastcgi_temp;
    uwsgi_temp_path uwsgi_temp;
    scgi_temp_path scgi_temp;
    gzip on;

    include conf.d/*.conf;
    include sites/*.conf;
}
EOF

echo "Conferindo $VHOSTS vhost(s) e $(find "$ANDAIME/conf.d" -name '*.conf' | wc -l) arquivo(s) de conf.d..."
nginx -t -p "$ANDAIME" -c nginx.conf
echo "# nginx -t aprovou a configuração versionada"
