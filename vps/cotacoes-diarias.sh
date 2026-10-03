#!/usr/bin/env bash
# Mantém em dia a série diária de cotações do Controle de Renda Variável, sem
# depender do PC Windows.
#
# As cotações ao vivo do CRV chegam só pelo agente RTD, que lê o ProfitChart
# aberto no Windows. A série diária (`quote_history`), que alimenta
# performance, risco e o histórico publicado, vinha desse mesmo agente e de um
# botão na tela de cotações: com o PC desligado, os dias ficavam sem
# fechamento. Este script roda `flask import-position-history --estrito` no
# contêiner `web` do CRV, que busca os fechamentos no Yahoo e preenche o que
# faltar. A leitura do RTD de um dia não é sobrescrita, porque é mais nova que
# a barra do Yahoo (ver `upsert_quote_history` no CRV).
#
# De terça a sábado, pela manhã: cada execução traz o fechamento do pregão
# anterior das duas bolsas, e domingo e segunda não teriam pregão novo. Uma
# execução perdida não deixa buraco, porque o comando reimporta o período
# inteiro de cada ticker.
#
# DESCOBRE, NÃO LISTA, como os irmãos desta pasta: o aplicativo é o checkout em
# ~/apps que traz `app/quotes/history_import.py`, e o contêiner é o do serviço
# `web` do projeto do Compose de mesmo nome.
#
# OS VAZIOS NÃO SÃO TODOS IGUAIS:
#   - nenhum checkout com o importador: a máquina não serve o CRV, e sair com
#     sucesso é o certo;
#   - checkout cujo comando ainda não aceita `--estrito`: rodar sem a opção
#     esconderia o Yahoo fora do ar, então é falha, que pede o deploy do CRV;
#   - checkout sem contêiner web: o CRV está aqui e a série não está sendo
#     mantida. Falha, e o `OnFailure=` da unidade alerta.

set -euo pipefail

DIR_APPS=${DIR_APPS:-/home/ubuntu/apps}
IMPORTADOR_REL=app/quotes/history_import.py

registrar() {
    printf '%s\n' "$*"
    logger -t cotacoes-diarias -- "$*" 2>/dev/null || true
}

falhas=0
executados=0
for importador in "$DIR_APPS"/*/"$IMPORTADOR_REL"; do
    [ -f "$importador" ] || continue
    checkout=${importador%/"$IMPORTADOR_REL"}
    projeto=$(basename -- "$checkout")

    if ! grep -q -- '--estrito' "$checkout/app/cli.py" 2>/dev/null; then
        registrar "ERRO: $projeto tem o importador, mas o comando ainda não aceita --estrito; implante o CRV"
        falhas=$((falhas + 1))
        continue
    fi

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
        registrar "ERRO: $projeto tem o importador de cotações, mas nenhum contêiner web em execução"
        falhas=$((falhas + 1))
        continue
    fi

    if saida=$(docker exec "$container" flask --app app:create_app import-position-history --estrito 2>&1); then
        registrar "$projeto: $saida"
        executados=$((executados + 1))
    else
        registrar "ERRO: $projeto: a importação falhou: $saida"
        falhas=$((falhas + 1))
    fi
done

if [ "$falhas" -gt 0 ]; then
    exit 1
fi
if [ "$executados" -eq 0 ]; then
    registrar "nenhum aplicativo com importador de cotações nesta máquina"
fi
