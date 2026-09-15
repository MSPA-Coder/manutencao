#!/usr/bin/env bash
# Avisa quando chega solicitação nova pelo formulário de contato do portal.
#
# O portal grava o pedido e o põe na caixa de entrada, mas nada avisava
# ninguém: ele ficava na lista até alguém abrir `/painel/atendimento/`. Este
# script, disparado a cada 15 minutos pelo `aviso-contatos.timer`, roda
# `manage.py contatos_novos` no contêiner `web` e chama o `alerta.sh` quando a
# contagem passa de zero.
#
# SÓ A CONTAGEM SAI DAQUI. O comando do portal devolve `novos=` e `ate=`, e nada
# mais: nome, e-mail e telefone de quem escreveu não vão para o Telegram. Quem
# recebe o aviso abre o painel.
#
# ESTADO: o `ate` de cada chamada fica em $ESTADO_DIR/<projeto>.desde e volta
# como `--desde` na seguinte. Sem esse arquivo a chamada só inicializa, e a
# primeira execução num servidor não avisa sobre o que já estava na lista.
#
# DESCOBRE, NÃO LISTA — como o `expurgo-contatos.sh`, de que este é irmão:
#   - quem tem aviso: os checkouts em ~/apps que trazem o comando;
#   - onde rodar: o contêiner em execução do serviço `web` do projeto do
#     Compose de mesmo nome do checkout.
# Máquina sem checkout com o comando sai com sucesso. Portal presente sem
# contêiner, comando que falha e saída que não se lê são falha, e o
# `OnFailure=` da unidade alerta. Nesses casos o estado não anda: o que chegou
# enquanto isso é contado no primeiro ciclo que der certo.

set -euo pipefail

DIR_APPS=${DIR_APPS:-/home/ubuntu/apps}
ALERTA=${ALERTA:-/home/ubuntu/alerta.sh}
ESTADO_DIR=${ESTADO_DIR:-/home/ubuntu/.local/state/mspa-aviso-contatos}
COMANDO_REL=contatos/management/commands/contatos_novos.py

registrar() {
    printf '%s\n' "$*"
    logger -t aviso-contatos -- "$*" 2>/dev/null || true
}

# Valor de `chave=` na saída do comando; vazio quando a chave não aparece.
valor_de() {
    printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -n 1
}

mkdir -p "$ESTADO_DIR"
ERROS=$(mktemp)
trap 'rm -f -- "$ERROS"' EXIT

falhas=0
verificados=0
for comando in "$DIR_APPS"/*/"$COMANDO_REL"; do
    [ -f "$comando" ] || continue
    checkout=${comando%/"$COMANDO_REL"}
    projeto=$(basename -- "$checkout")
    estado="$ESTADO_DIR/$projeto.desde"

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
        registrar "ERRO: $projeto tem o aviso de chegada, mas nenhum contêiner web em execução"
        falhas=$((falhas + 1))
        continue
    fi

    argumentos=()
    if [ -s "$estado" ]; then
        argumentos=(--desde "$(cat -- "$estado")")
    fi

    # Só a saída padrão é lida. Um aviso de biblioteca na saída de erro não pode
    # ser tomado pela resposta; ele vai para o registro quando o comando falha.
    if ! saida=$(docker exec "$container" python manage.py contatos_novos \
                 "${argumentos[@]}" 2>"$ERROS"); then
        registrar "ERRO: $projeto: contatos_novos falhou: $(head -c 300 -- "$ERROS")"
        falhas=$((falhas + 1))
        continue
    fi

    novos=$(valor_de novos "$saida")
    ate=$(valor_de ate "$saida")
    if ! [[ "$novos" =~ ^[0-9]+$ ]] || [ -z "$ate" ]; then
        registrar "ERRO: $projeto: saída de contatos_novos ilegível: $(printf '%s' "$saida" | head -c 200)"
        falhas=$((falhas + 1))
        continue
    fi

    if [ "${#argumentos[@]}" -eq 0 ]; then
        registrar "$projeto: aviso de chegada inicializado em $ate"
    elif [ "$novos" -gt 0 ]; then
        if [ "$novos" -eq 1 ]; then
            titulo="PORTAL: 1 solicitação nova"
        else
            titulo="PORTAL: $novos solicitações novas"
        fi
        # `ALERTA_JANELA=0`: o antirrepetição do `alerta.sh` reconhece mensagem
        # pelo título, e dois pedidos avulsos com menos de 15 minutos entre eles
        # teriam o mesmo título -- o segundo seria engolido. Quem impede aviso
        # repetido aqui é o estado, não a janela.
        ALERTA_JANELA=0 "$ALERTA" "$titulo" \
"Chegou pelo formulário de contato do site ($projeto).

Para ver quem escreveu e atender: /painel/atendimento/"
        registrar "$projeto: $novos solicitação(ões) nova(s), aviso enviado"
    fi

    # Troca atômica: um estado truncado viraria um `--desde` ilegível, e o
    # comando passaria a recusar em todos os ciclos seguintes.
    printf '%s\n' "$ate" >"$estado.tmp"
    mv -f -- "$estado.tmp" "$estado"
    verificados=$((verificados + 1))
done

if [ "$falhas" -gt 0 ]; then
    exit 1
fi
if [ "$verificados" -eq 0 ]; then
    registrar "nenhum aplicativo com aviso de chegada nesta máquina"
fi
