#!/usr/bin/env sh
# Teste hermético da configuração do Nginx: `nginx -t` sobre os vhosts
# versionados, sem rede, sem VPS e sem certificado de verdade.
#
# POR QUE EXISTE: os seis vhosts, o `conf.d/00-comum.conf` e o
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
# `deploy.sh` (sonda `/health` pública) e do `vigia.sh`. A exceção é a recusa
# de `/patrimonio/`, que o próprio nginx responde sem precisar da aplicação: o
# andaime sobe e a prova é feita com pedidos de verdade (seção no fim).
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

# ---------------------------------------------------------------------------
# HSTS com uma fonte só (15/09/2026).
#
# `nginx -t` aprova a sintaxe, mas não enxerga que dois cabeçalhos HSTS
# discordantes chegavam ao navegador: o do vhost e o que o Django manda. A
# correção é de estrutura, e é a estrutura que se confere aqui:
#   - o snippet de proxy descarta o HSTS que vem da aplicação;
#   - todo `proxy_pass` de todo vhost passa pelo snippet;
#   - todo vhost que faz proxy emite exatamente um HSTS próprio.
# Vhost sem `proxy_pass` (o `recusa-host-desconhecido`) fica de fora: ele não
# serve conteúdo, só recusa o handshake.
# ---------------------------------------------------------------------------
grep -Eq '^[[:space:]]*proxy_hide_header[[:space:]]+Strict-Transport-Security;' \
        "$FONTE/snippets/proxy-app.conf" \
    || { echo "FALHOU: snippets/proxy-app.conf não descarta o HSTS da aplicação." >&2; exit 1; }

for vhost in "$ANDAIME"/sites/*.conf; do
    nome=$(basename "$vhost" .conf)
    proxies=$(grep -Ec '^[[:space:]]*proxy_pass[[:space:]]' "$vhost" || true)
    [ "$proxies" -gt 0 ] || continue
    incluidos=$(grep -Ec '^[[:space:]]*include[[:space:]]+snippets/proxy-app\.conf;' "$vhost" || true)
    if [ "$proxies" -ne "$incluidos" ]; then
        echo "FALHOU: $nome tem $proxies proxy_pass e $incluidos include do snippet de proxy." >&2
        exit 1
    fi
    hsts=$(grep -Ec '^[[:space:]]*add_header[[:space:]]+Strict-Transport-Security[[:space:]]' "$vhost" || true)
    if [ "$hsts" -ne 1 ]; then
        echo "FALHOU: $nome tem $hsts add_header de HSTS; esperado exatamente 1." >&2
        exit 1
    fi
done
echo "# HSTS: um por vhost, e o da aplicação é descartado no proxy"

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

# ---------------------------------------------------------------------------
# Patrimônio fora da borda (02/10/2026).
#
# O CB e o CRV publicam `/patrimonio/v1` a `v4`, contrato máquina a máquina com
# Bearer. O único consumidor, o Wealthfolio, lê pela rede Docker interna; na
# internet essas rotas só serviriam a quem tivesse um token vazado. A recusa é
# do nginx, antes do proxy, então a prova não precisa de aplicação: o andaime
# sobe e responde a pedidos de verdade.
#
# Os dois vhosts são nomeados porque a regra é dos dois aplicativos que
# publicam o contrato, não da frota. A outra metade da prova é que o resto do
# site continua indo para a aplicação: sem nada escutando na porta dela, a
# resposta é 502, e não 404. Um `location` largo demais apareceria aí.
#
# Os caminhos com `//` e `..` estão aqui de propósito: o nginx normaliza o URI
# antes de escolher o `location`, e é isso que impede contornar a recusa
# escrevendo o mesmo caminho de outro jeito.
# ---------------------------------------------------------------------------
PUBLICADORES="controle-bancario controle-renda-variavel"

nginx -p "$ANDAIME" -c nginx.conf
trap 'nginx -p "$ANDAIME" -c nginx.conf -s stop 2>/dev/null; rm -rf "$ANDAIME"' EXIT

# Código HTTP da resposta a `GET <caminho>` no vhost de <domínio>, por TLS em
# 127.0.0.1. `openssl s_client` porque é o que a imagem já traz.
codigo() {
    printf 'GET %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n' "$2" "$1" \
        | timeout 10 openssl s_client -quiet -connect 127.0.0.1:443 -servername "$1" 2>/dev/null \
        | sed -n '1s#^HTTP/1\.1 \([0-9][0-9][0-9]\).*#\1#p'
}

# O nginx registra no stderr um `connect() failed` para cada 502 abaixo: é a
# prova esperada, e não um defeito do teste.
for publicador in $PUBLICADORES; do
    vhost="$ANDAIME/sites/$publicador.conf"
    [ -f "$vhost" ] || { echo "FALHOU: vhost $publicador não está na origem." >&2; exit 1; }
    dominio=$(sed -n 's/^[[:space:]]*server_name[[:space:]]\{1,\}\([^;[:space:]]*\).*/\1/p' "$vhost" | head -n 1)
    for caminho in /patrimonio/ /patrimonio/v1/resumo /patrimonio/v4/snapshot \
                   //patrimonio/v4/snapshot /static/../patrimonio/v4/metadata; do
        obtido=$(codigo "$dominio" "$caminho")
        if [ "$obtido" != 404 ]; then
            echo "FALHOU: $dominio$caminho respondeu ${obtido:-nada}; esperado 404 do próprio nginx." >&2
            exit 1
        fi
    done
    obtido=$(codigo "$dominio" /health)
    if [ "$obtido" != 502 ]; then
        echo "FALHOU: $dominio/health respondeu ${obtido:-nada}; esperado 502 (proxy sem aplicação)." >&2
        exit 1
    fi
done
echo "# /patrimonio/ recusado na borda do CB e do CRV; o resto segue para a aplicação"
