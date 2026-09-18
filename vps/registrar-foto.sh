#!/usr/bin/env bash
# Tira, uma vez por dia, a foto do patrimônio no NetWorth.
#
# O histórico do NetWorth é desenhado a partir de uma foto por dia fechado.
# Sem alguém que rode `manage.py registrar_foto` todo dia, a curva para na
# última execução e ninguém percebe: o gráfico continua bonito, só que velho.
# Este script é quem roda, disparado pelo `registrar-foto.timer`.
#
# Sem argumento, o comando refaz os últimos sete dias fechados. Um lançamento
# de ontem pode ser registrado amanhã, e a foto de ontem precisa enxergá-lo.
#
# DESCOBRE, NÃO LISTA — como o `atualizar-cambio.sh`, de que este é irmão:
#   - quem tira foto: os checkouts em ~/apps que trazem o comando;
#   - onde rodar: o contêiner em execução do serviço `web` do projeto do
#     Compose de mesmo nome do checkout.
#
# O VAZIO TEM DOIS SENTIDOS, e o script os separa:
#   - nenhum checkout com o comando: a máquina não serve o NetWorth, e sair
#     com sucesso é o certo;
#   - checkout com o comando e nenhum contêiner para rodá-lo: o NetWorth está
#     aqui e o histórico vai parar calado. Isso é falha, e o `OnFailure=` da
#     unidade alerta.
#
# O comando termina com erro quando alguma data ficou sem foto (uma fonte fora
# do ar, ou uma posição sem cotação). Isso também é falha: é um buraco no
# histórico, e a execução do dia seguinte tenta de novo.
set -euo pipefail

DIR_APPS=${DIR_APPS:-/home/ubuntu/apps}
COMANDO_REL=consolidado/management/commands/registrar_foto.py

registrar() {
    printf '%s\n' "$*"
    logger -t registrar-foto -- "$*" 2>/dev/null || true
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
        registrar "ERRO: $projeto tem a foto do patrimônio, mas nenhum contêiner web em execução"
        falhas=$((falhas + 1))
        continue
    fi

    if saida=$(docker exec "$container" python manage.py registrar_foto 2>&1); then
        registrar "$projeto: $saida"
        executados=$((executados + 1))
    else
        registrar "ERRO: $projeto: a foto do patrimônio falhou: $saida"
        falhas=$((falhas + 1))
    fi
done

if [ "$falhas" -gt 0 ]; then
    exit 1
fi
if [ "$executados" -eq 0 ]; then
    registrar "nenhum aplicativo com foto do patrimônio nesta máquina"
fi
