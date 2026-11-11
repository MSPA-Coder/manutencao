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
# A IMAGEM É `nginx:1.28` E ISSO NÃO É DETALHE: é a imagem oficial do
# Docker Hub, na mesma série que o Ubuntu 26.04
# dos VPS entrega, e os vhosts usam `http2 on;`, que só existe a partir do
# 1.25.1. Numa imagem diferente o teste testaria outro servidor. Quando os VPS
# subirem de versão, esta linha sobe junto, deliberadamente.
#
# Uso:
#   docker compose -f .github/docker-compose.yml run --rm --no-deps nginx-test

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
mkdir -p /etc/nginx/segredos
# O arquivo real contém o hash de credenciais e vive só no VPS. Para testar o
# contrato do vhost, basta existir um arquivo legível; nenhuma credencial entra
# neste repositório ou nesta suíte.
: >/etc/nginx/segredos/viva-passo.htpasswd
: >/etc/nginx/segredos/villa-rica.htpasswd

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

# `/fechamento/status` (contrato crv-fechamento/1) é só do CRV e o CB o lê pela
# rede interna: a borda do CRV recusa. O bloco é só do CRV (o CB tem as telas
# dele em `/banking/closing/`, que não podem ser tocadas); o `/health` acima
# prova que o resto do CRV segue para a aplicação.
dominio_crv=$(sed -n 's/^[[:space:]]*server_name[[:space:]]\{1,\}\([^;[:space:]]*\).*/\1/p' "$ANDAIME/sites/controle-renda-variavel.conf" | head -n 1)
for caminho in /fechamento/status /fechamento/ //fechamento/status /static/../fechamento/status; do
    obtido=$(codigo "$dominio_crv" "$caminho")
    if [ "$obtido" != 404 ]; then
        echo "FALHOU: $dominio_crv$caminho respondeu ${obtido:-nada}; esperado 404 do próprio nginx." >&2
        exit 1
    fi
done
dominio_cb=$(sed -n 's/^[[:space:]]*server_name[[:space:]]\{1,\}\([^;[:space:]]*\).*/\1/p' "$ANDAIME/sites/controle-bancario.conf" | head -n 1)
obtido=$(codigo "$dominio_cb" /banking/closing/)
if [ "$obtido" != 502 ]; then
    echo "FALHOU: $dominio_cb/banking/closing/ respondeu ${obtido:-nada}; esperado 502 (a tela do CB segue para a aplicação)." >&2
    exit 1
fi
echo "# /fechamento/ recusado na borda do CRV; no CB segue para a aplicação"

# O Viva Passo é estático: a sonda não depende de processo de aplicação e a
# rota de saúde deve continuar disponível sem revelar os arquivos do site.
viva="$ANDAIME/sites/viva-passo.conf"
[ -f "$viva" ] || { echo "FALHOU: vhost viva-passo ausente." >&2; exit 1; }
grep -Eq '^[[:space:]]*root[[:space:]]+/home/ubuntu/apps/viva-passo;' "$viva" \
    || { echo "FALHOU: viva-passo não aponta para o checkout declarado." >&2; exit 1; }
dominio_viva=$(sed -n 's/^[[:space:]]*server_name[[:space:]]\{1,\}\([^;[:space:]]*\).*/\1/p' "$viva" | head -n 1)
obtido=$(codigo "$dominio_viva" /health)
if [ "$obtido" != 200 ]; then
    echo "FALHOU: $dominio_viva/health respondeu ${obtido:-nada}; esperado 200." >&2
    exit 1
fi
obtido=$(codigo "$dominio_viva" /)
if [ "$obtido" != 401 ]; then
    echo "FALHOU: $dominio_viva/ respondeu ${obtido:-nada}; esperado 401 sem credencial." >&2
    exit 1
fi
echo "# Viva Passo: /health estático responde 200 e o conteúdo pede credencial"

# O Villa Rica segue o mesmo contrato de isolamento do conteúdo: a sonda é
# pública para a operação, mas as páginas financeiras exigem credencial.
villa_rica="$ANDAIME/sites/villa-rica.conf"
[ -f "$villa_rica" ] || { echo "FALHOU: vhost villa-rica ausente." >&2; exit 1; }
grep -Eq '^[[:space:]]*root[[:space:]]+/home/ubuntu/apps/villa-rica;' "$villa_rica" \
    || { echo "FALHOU: villa-rica não aponta para o checkout declarado." >&2; exit 1; }
dominio_villa_rica=$(sed -n 's/^[[:space:]]*server_name[[:space:]]\{1,\}\([^;[:space:]]*\).*/\1/p' "$villa_rica" | head -n 1)
obtido=$(codigo "$dominio_villa_rica" /health)
if [ "$obtido" != 200 ]; then
    echo "FALHOU: $dominio_villa_rica/health respondeu ${obtido:-nada}; esperado 200." >&2
    exit 1
fi
obtido=$(codigo "$dominio_villa_rica" /)
if [ "$obtido" != 401 ]; then
    echo "FALHOU: $dominio_villa_rica/ respondeu ${obtido:-nada}; esperado 401 sem credencial." >&2
    exit 1
fi
echo "# Villa Rica: /health estático responde 200 e o conteúdo pede credencial"

# ---------------------------------------------------------------------------
# Sites estáticos: lista de permissão, cabeçalhos e limite de tentativas
# (SEG-2, SEG-3 e SEG-4 da auditoria de 10/11/2026).
#
# O checkout inteiro estava na raiz do vhost: quem tinha a senha lia também
# `AGENTS.md`, planos e `Dockerfile`. Agora só o que o site carrega passa pela
# autenticação (401 sem credencial); o resto responde 404 ANTES dela, e é por
# isso que o 404 sem credencial prova o bloqueio (se fosse só pela senha, daria
# 401). A segunda metade da prova é a mesma lista no sentido contrário: cada
# arquivo que o site usa continua pedindo credencial, e não 404.
# ---------------------------------------------------------------------------
# Os arquivos precisam EXISTIR nas raízes: sem eles tudo daria 404 e a prova do
# bloqueio não provaria nada (o contêiner do teste é descartável).
for raiz in /home/ubuntu/apps/viva-passo /home/ubuntu/apps/villa-rica; do
    mkdir -p "$raiz/assets" "$raiz/tests/browser" "$raiz/conferencia" "$raiz/.git"
    for arq in AGENTS.md README.md PLANO_DE_READAPTACAO.md PLANO_SAUDE_CONDICIONAMENTO_8_SEMANAS.md \
               Dockerfile Dockerfile.browser compose.yaml .gitignore tests/browser/state.cjs \
               conferencia/README.md .git/config index.html app.js styles.css anatomy.css \
               tracking.css builder.css contas-villa-rica-2026.html \
               sugestoes-convencao-regulamento-villa-rica.html assets/bicicleta-anatomia.png \
               assets/brasao-villa-rica.jpg; do
        echo x >"$raiz/$arq"
    done
done

esperar() { # <domínio> <código esperado> <caminho>...
    dom=$1; esp=$2; shift 2
    for cam in "$@"; do
        obtido=$(codigo "$dom" "$cam")
        if [ "$obtido" != "$esp" ]; then
            echo "FALHOU: $dom$cam respondeu ${obtido:-nada}; esperado $esp." >&2
            exit 1
        fi
    done
}

esperar "$dominio_viva" 404 /AGENTS.md /README.md /PLANO_DE_READAPTACAO.md \
    /PLANO_SAUDE_CONDICIONAMENTO_8_SEMANAS.md /Dockerfile /Dockerfile.browser /compose.yaml \
    /tests/browser/state.cjs /.git/config //AGENTS.md /assets/ /static/../AGENTS.md
esperar "$dominio_viva" 401 / /index.html /app.js /styles.css /anatomy.css /tracking.css \
    /builder.css /assets/bicicleta-anatomia.png
echo "# Viva Passo: só os arquivos do site pedem credencial; o resto do checkout dá 404"

esperar "$dominio_villa_rica" 404 /AGENTS.md /README.md /.gitignore /conferencia/README.md \
    /conferencia/ //AGENTS.md /assets/
esperar "$dominio_villa_rica" 401 / /contas-villa-rica-2026.html \
    /sugestoes-convencao-regulamento-villa-rica.html /assets/brasao-villa-rica.jpg
echo "# Villa Rica: só as duas páginas e assets/ pedem credencial; o resto dá 404"

# Cabeçalhos de segurança: no `/health` (200) e no 401, que é o que a internet
# vê. O `s_client -quiet` entrega a resposta inteira; só o cabeçalho
# interessa.
cabecalhos() {
    printf 'GET %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n' "$2" "$1" \
        | timeout 10 openssl s_client -quiet -connect 127.0.0.1:443 -servername "$1" 2>/dev/null \
        | tr -d '\r' | sed '/^$/q'
}
for par in "$dominio_viva" "$dominio_villa_rica"; do
    for caminho in /health /; do
        resposta=$(cabecalhos "$par" "$caminho")
        for cab in 'X-Content-Type-Options: nosniff' 'Referrer-Policy: no-referrer' \
                   'X-Frame-Options: DENY' 'Permissions-Policy:' \
                   "Content-Security-Policy: default-src 'self'" "frame-ancestors 'none'" \
                   'Strict-Transport-Security:'; do
            printf '%s\n' "$resposta" | grep -Fq -- "$cab" \
                || { echo "FALHOU: $par$caminho sem o cabeçalho '$cab'." >&2; exit 1; }
        done
    done
done
echo "# Sites estáticos: cabeçalhos de segurança no 200 e no 401"

# Limite de tentativas na autenticação básica. A zona `basica` conta todo
# pedido ao conteúdo, inclusive o 401; com burst de 120, o 121º em sequência
# do mesmo endereço volta 429 e a abertura normal do site (dezenas de pedidos)
# continua passando. Fica por último: a zona é compartilhada pelos dois sites.
limitado=0; passaram=0
i=0
while [ "$i" -lt 220 ]; do
    i=$((i + 1))
    obtido=$(codigo "$dominio_villa_rica" /)
    if [ "$obtido" = 429 ]; then
        limitado=$((limitado + 1))
    else
        passaram=$((passaram + 1))
    fi
done
if [ "$limitado" -lt 1 ] || [ "$passaram" -lt 100 ]; then
    echo "FALHOU: em 220 pedidos a $dominio_villa_rica/, $passaram passaram e $limitado deram 429; esperado >=100 e >=1." >&2
    exit 1
fi
echo "# Autenticação básica: $passaram pedidos passam (burst) e o excedente leva 429"
