#!/usr/bin/env bash
# Preenche, uma vez por dia, a série de câmbio do NetWorth.
#
# O NetWorth converte o patrimônio para reais pela taxa do dia da foto, e
# recusa uma taxa com mais de sete dias. Sem alguém que rode
# `manage.py atualizar_cambio` todo dia, o total em reais some da tela uma
# semana depois da última coleta. Este script é quem roda, disparado pelo
# `atualizar-cambio.timer`.
#
# DESCOBRE, NÃO LISTA — como o `expurgo-contatos.sh`, de que este é irmão:
#   - quem precisa de câmbio: os checkouts em ~/apps que trazem o comando;
#   - onde rodar: o contêiner em execução do serviço `web` do projeto do
#     Compose de mesmo nome do checkout.
#
# O VAZIO TEM DOIS SENTIDOS, e o script os separa:
#   - nenhum checkout com o comando: a máquina não serve o NetWorth, e sair
#     com sucesso é o certo;
#   - checkout com o comando e nenhum contêiner para rodá-lo: o NetWorth está
#     aqui e a série vai envelhecer calada. Isso é falha, e o `OnFailure=` da
#     unidade alerta.
#
# O comando não derruba a coleta por causa do Yahoo: se a fonte externa não
# responder, ele avisa e sai com sucesso, e a tela continua mostrando os
# totais por moeda sem converter. Falha aqui é o comando não rodar.
set -euo pipefail

DIR_APPS=${DIR_APPS:-/home/ubuntu/apps}
COMANDO_REL=consolidado/management/commands/atualizar_cambio.py

registrar() {
    printf '%s\n' "$*"
    logger -t atualizar-cambio -- "$*" 2>/dev/null || true
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
        registrar "ERRO: $projeto tem a coleta de câmbio, mas nenhum contêiner web em execução"
        falhas=$((falhas + 1))
        continue
    fi

    if saida=$(docker exec "$container" python manage.py atualizar_cambio 2>&1); then
        registrar "$projeto: $saida"
        executados=$((executados + 1))
    else
        registrar "ERRO: $projeto: a coleta de câmbio falhou: $saida"
        falhas=$((falhas + 1))
    fi
done

if [ "$falhas" -gt 0 ]; then
    exit 1
fi
if [ "$executados" -eq 0 ]; then
    registrar "nenhum aplicativo com coleta de câmbio nesta máquina"
fi
