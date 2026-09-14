#!/usr/bin/env bash
# Cumpre, uma vez por dia, a retenção de contatos que o aviso de privacidade do
# portal publica.
#
# O portal declara o prazo (`CONTATO_RETENCAO_DIAS`) e tem o comando que o
# aplica (`manage.py expurgar_contatos`). Sem alguém que rode o comando, o prazo
# escrito no aviso é promessa; este script é quem roda, disparado pelo
# `expurgo-contatos.timer`.
#
# DESCOBRE, NÃO LISTA — como os outros scripts desta pasta. A mesma cópia roda
# no servidor que tem o portal e no que não tem:
#   - quem precisa de expurgo: os checkouts em ~/apps que trazem o comando;
#   - onde rodar: o contêiner em execução do serviço `web` do projeto do
#     Compose de mesmo nome do checkout.
#
# O VAZIO TEM DOIS SENTIDOS, e o script os separa:
#   - nenhum checkout com o comando: a máquina não serve o portal, e sair com
#     sucesso é o certo;
#   - checkout com o comando e nenhum contêiner para rodá-lo: o portal está
#     aqui e o prazo não está sendo cumprido. Isso é falha, e o `OnFailure=` da
#     unidade alerta.

set -euo pipefail

DIR_APPS=${DIR_APPS:-/home/ubuntu/apps}
COMANDO_REL=contatos/management/commands/expurgar_contatos.py

registrar() {
    printf '%s\n' "$*"
    logger -t expurgo-contatos -- "$*" 2>/dev/null || true
}

falhas=0
executados=0
for comando in "$DIR_APPS"/*/"$COMANDO_REL"; do
    [ -f "$comando" ] || continue
    checkout=${comando%/"$COMANDO_REL"}
    projeto=$(basename -- "$checkout")

    # Sem `| head`: com `pipefail`, uma falha do `docker ps` derrubaria o script
    # na atribuição, sem dizer por quê. Assim ela vira mensagem e falha contada.
    if ! nomes=$(docker ps \
        --filter "label=com.docker.compose.project=$projeto" \
        --filter "label=com.docker.compose.service=web" \
        --format '{{.Names}}'); then
        registrar "ERRO: $projeto: não foi possível consultar o Docker"
        falhas=$((falhas + 1))
        continue
    fi
    container=${nomes%%$'\n'*}
    if [ -z "$container" ]; then
        registrar "ERRO: $projeto tem o comando de expurgo, mas nenhum contêiner web em execução"
        falhas=$((falhas + 1))
        continue
    fi

    if saida=$(docker exec "$container" python manage.py expurgar_contatos 2>&1); then
        registrar "$projeto: $saida"
        executados=$((executados + 1))
    else
        registrar "ERRO: $projeto: o expurgo falhou: $saida"
        falhas=$((falhas + 1))
    fi
done

if [ "$falhas" -gt 0 ]; then
    exit 1
fi
if [ "$executados" -eq 0 ]; then
    registrar "nenhum aplicativo com expurgo de contatos nesta máquina"
fi
