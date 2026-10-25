#!/usr/bin/env bash
# Sentinela de erro de aplicação: lê o log de 5xx do nginx e alerta.
#
#   ./sentinela.sh            drena o que chegou desde a última execução
#   ./sentinela.sh --estado   mostra o que faria, sem alertar e sem consumir
#
# O QUE ESTE SCRIPT COBRE, E QUE NADA MAIS COBRIA
#
# O restante do monitoramento vê QUEDA. O `vigia.sh` bate no `/health`, o
# UptimeRobot bate de fora, o `OnFailure=` avisa unidade que falhou. Uma rota
# que devolve 500 para todo mundo passa por tudo isso sem acender nada: o
# `/health` continua verde, porque consulta o banco e o banco está bem.
#
# A fonte é `/var/log/nginx/erro5xx.log`, que o `conf.d/00-comum.conf` faz o
# nginx escrever com `access_log ... if=`. Toda linha ali já é um incidente --
# não há o que filtrar, adivinhar ou casar com expressão regular.
#
# POR QUE NÃO ANEXO O LOG DO CONTÊINER À MENSAGEM
#
# Para achar o contêiner a partir do domínio seria preciso a tabela que liga
# apelido, diretório, porta e domínio -- e o `deploy.sh` declara, por escrito,
# ser o único lugar do repositório onde essa correspondência mora. Uma segunda
# cópia aqui envelheceria em silêncio, e a primeira vez que alguém notaria
# seria num alerta apontando para o app errado. A mensagem leva as próprias
# linhas do nginx, que já dizem host, rota, status e duração, e o operador
# segue de `~/deploy.sh --status`.

set -uo pipefail

ALERTA=${ALERTA:-/home/ubuntu/alerta.sh}
LOG=${LOG_5XX:-/var/log/nginx/erro5xx.log}
ESTADO_DIR=${ESTADO_DIR:-/home/ubuntu/.local/state/mspa-sentinela}
# Onde o `app-lock.sh` guarda um lock por aplicação. Segurado = deploy, rebuild
# ou backup em andamento naquele app.
APP_LOCK_DIR=${APP_LOCK_DIR:-/home/ubuntu/.local/state/mspa-app-locks}
MARCA="$ESTADO_DIR/posicao"

# Quantas linhas do incidente vão na mensagem. O `alerta.sh` corta em 3900
# caracteres; dez linhas cabem com folga e já mostram se o erro é numa rota só
# ou espalhado.
AMOSTRA=10

# Janela de repetição de meia hora. O timer roda a cada cinco minutos: com a
# janela padrão de quinze, uma quebra que dure uma hora renderia quatro
# mensagens iguais. Meia hora avisa, deixa tempo de agir e volta a avisar se
# ainda estiver quebrado.
JANELA=${SENTINELA_JANELA:-1800}

MODO="${1:-alertar}"

registrar() { logger -t sentinela -- "$*"; }

alertar() {
    if [ "$MODO" = "--estado" ]; then
        printf '  ALERTARIA: %s\n' "$1"
        return 0
    fi
    ALERTA_JANELA="$JANELA" "$ALERTA" "$1" "${2:-}" || true
}

# --------------------------------------------------------------------------
# O log existe e dá para ler?
#
# Esta verificação não é burocracia. O nginx do Ubuntu escreve seus logs como
# `root:adm`, e este script roda como `ubuntu`. Se um dia a associação de
# grupo mudar, o sentinela pararia de ver incidente nenhum e continuaria
# saindo com sucesso -- um monitor cego que se declara saudável é pior que
# monitor nenhum, porque compra silêncio. Então a cegueira também alerta.
# --------------------------------------------------------------------------
if [ ! -e "$LOG" ]; then
    # Arquivo ausente é o estado normal de quem nunca teve um 5xx: o nginx só
    # o cria na primeira ocorrência.
    [ "$MODO" = "--estado" ] && echo "log 5xx: ainda não existe (nenhum erro desde a instalação)"
    exit 0
fi

if [ ! -r "$LOG" ]; then
    registrar "ERRO: $LOG existe e não é legível por $(id -un)"
    alertar "SENTINELA CEGO: não consigo ler o log de erros" \
"O arquivo $LOG existe, mas $(id -un) não tem permissão de leitura.

Enquanto isso durar, nenhum erro 500 das aplicações será notificado.

Conferir:
  ls -l $LOG
  id -nG $(id -un)

No Ubuntu o nginx grava como root:adm; o usuário precisa estar no grupo adm."
    exit 1
fi

mkdir -p "$ESTADO_DIR" 2>/dev/null

# --------------------------------------------------------------------------
# Onde parei da última vez
#
# A marca guarda três coisas, e cada uma cobre um jeito diferente de o arquivo
# deixar de ser o mesmo:
#
#   inode      O logrotate do nginx no Ubuntu rotaciona por `create`: o arquivo
#              antigo é renomeado e um NOVO nasce no lugar. Comparar só o
#              tamanho erraria quando o arquivo novo já passou da posição
#              antiga -- as linhas do meio sumiriam sem ninguém notar.
#
#   tamanho    Truncamento simples: ficou menor do que onde eu parei.
#
#   assinatura Um prefixo do arquivo, de tamanho FIXO gravado junto com ela.
#              É o que fecha o buraco que sobra: com `copytruncate`, o
#              logrotate esvazia o arquivo SEM trocar o inode, e se ele voltar
#              a crescer além da posição antiga dentro da mesma janela de cinco
#              minutos, inode e tamanho concordam com a marca e o conteúdo é
#              outro. A primeira linha começa por carimbo de tempo, então basta
#              ela mudar para a assinatura mudar.
#
#              O TAMANHO DO PREFIXO PRECISA SER GRAVADO, e não fixado em 256
#              aqui. Um arquivo com uma linha só tem menos de 256 bytes, então
#              "os primeiros 256 bytes" mudam quando uma linha é ACRESCENTADA
#              -- e o sentinela releria tudo, alertando de novo o que já tinha
#              alertado. Guardando o tamanho usado, a comparação seguinte olha
#              exatamente o mesmo pedaço.
#
#              Os dois casos foram encontrados por `tests/sentinela_test.sh`,
#              não em produção. São o tipo de defeito que não deixa rastro: um
#              perde alerta em silêncio, o outro repete alerta antigo como se
#              fosse novo.
# --------------------------------------------------------------------------
PREFIXO_MAX=256

inode_atual=$(stat -c %i "$LOG" 2>/dev/null || echo 0)
tamanho_atual=$(stat -c %s "$LOG" 2>/dev/null || echo 0)

inode_antigo=0
posicao=0
prefixo_antigo=0
assinatura_antiga=""
if [ -f "$MARCA" ]; then
    IFS=: read -r inode_antigo posicao prefixo_antigo assinatura_antiga < "$MARCA" 2>/dev/null || true
    inode_antigo=${inode_antigo:-0}
    posicao=${posicao:-0}
    prefixo_antigo=${prefixo_antigo:-0}
fi

assinatura_atual=$(head -c "$prefixo_antigo" "$LOG" 2>/dev/null | sha256sum | cut -c1-16)

if [ "$inode_atual" != "$inode_antigo" ] \
   || [ "$tamanho_atual" -lt "$posicao" ] \
   || [ "$assinatura_atual" != "$assinatura_antiga" ]; then
    # Arquivo trocado, truncado ou reescrito: recomeça do zero. Preferir reler
    # a perder -- repetição o `alerta.sh` suprime, linha perdida ninguém
    # recupera.
    posicao=0
fi

if [ "$tamanho_atual" -le "$posicao" ]; then
    [ "$MODO" = "--estado" ] && echo "log 5xx: nada novo desde a última execução"
    exit 0
fi

# `tail -c +N` conta a partir do byte N, com N começando em 1.
novas=$(tail -c "+$((posicao + 1))" "$LOG" 2>/dev/null)

if [ -z "$novas" ]; then
    [ "$MODO" = "--estado" ] && echo "log 5xx: nada novo desde a última execução"
    exit 0
fi

# --------------------------------------------------------------------------
# 5xx durante o deploy do mesmo domínio (25/10/2026)
#
# A troca de contêiner num deploy produz 502 por alguns segundos, e o coletor
# do CRV, que consulta a cada 30 s, caía nela quase sempre: de 18 a 24/10, mais
# da metade dos alertas de 5xx eram isso. O lock da aplicação (abaixo) só cala
# o sentinela se ele acordar DURANTE o deploy, o que quase nunca acontece. O
# `deploy.sh` registra cada janela (`marcar_janela`); a linha do MESMO domínio
# dentro dela, com margem, é descartada aqui. Outro domínio no mesmo minuto
# continua alertando, e o deploy que dá errado avisa por conta própria.
# --------------------------------------------------------------------------
JANELAS_DEPLOY=${JANELAS_DEPLOY:-/home/ubuntu/.local/state/mspa-deploy/janelas.log}
MARGEM_ANTES=30
MARGEM_DEPOIS=90
# Deploy sem `fim` registrado está em curso, ou morreu sem o trap (KILL).
# Este teto impede que um deploy morto cale o domínio para sempre.
JANELA_ABERTA_MAX=1800

# `2026-10-18T04:31:06+00:00` -> epoch. Sem `date -d` com fuso, que o busybox
# não entende: a hora vai como UTC e o deslocamento é aplicado à mão.
epoch_iso() {
    local data hora sinal oh om segundos
    [[ "$1" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}:[0-9]{2}:[0-9]{2})(Z|([+-])([0-9]{2}):([0-9]{2}))$ ]] \
        || return 1
    data=${BASH_REMATCH[1]} hora=${BASH_REMATCH[2]}
    sinal=${BASH_REMATCH[4]} oh=${BASH_REMATCH[5]} om=${BASH_REMATCH[6]}
    segundos=$(date -u -d "$data $hora" +%s 2>/dev/null) || return 1
    if [ -n "$sinal" ]; then
        if [ "$sinal" = "+" ]; then
            segundos=$(( segundos - 10#$oh * 3600 - 10#$om * 60 ))
        else
            segundos=$(( segundos + 10#$oh * 3600 + 10#$om * 60 ))
        fi
    fi
    printf '%s\n' "$segundos"
}

janelas=()
if [ -r "$JANELAS_DEPLOY" ]; then
    declare -A abertas=()
    while read -r evento dominio quando; do
        [[ "${quando:-}" =~ ^[0-9]+$ ]] || continue
        case "$evento" in
            inicio) abertas[$dominio]=$quando ;;
            fim)
                if [ -n "${abertas[$dominio]:-}" ]; then
                    janelas+=("$dominio ${abertas[$dominio]} $quando")
                    unset "abertas[$dominio]"
                fi ;;
        esac
    done <"$JANELAS_DEPLOY"
    agora=$(date +%s)
    for dominio in "${!abertas[@]}"; do
        inicio=${abertas[$dominio]}
        fim=$(( inicio + JANELA_ABERTA_MAX ))
        [ "$agora" -lt "$fim" ] && fim=$agora
        janelas+=("$dominio $inicio $fim")
    done
fi

if [ "${#janelas[@]}" -gt 0 ]; then
    mantidas=""
    descartadas_deploy=0
    dominios_deploy=""
    while IFS= read -r linha_5xx; do
        [ -n "$linha_5xx" ] || continue
        durante_deploy=0
        if [[ "$linha_5xx" =~ ^([^ ]+)\ host=([^ ]+)\  ]]; then
            host_linha=${BASH_REMATCH[2]}
            if quando_linha=$(epoch_iso "${BASH_REMATCH[1]}"); then
                for janela in "${janelas[@]}"; do
                    read -r dominio inicio fim <<<"$janela"
                    [ "$dominio" = "$host_linha" ] || continue
                    if [ "$quando_linha" -ge $((inicio - MARGEM_ANTES)) ] \
                       && [ "$quando_linha" -le $((fim + MARGEM_DEPOIS)) ]; then
                        durante_deploy=1
                        break
                    fi
                done
            fi
        fi
        if [ "$durante_deploy" -eq 1 ]; then
            descartadas_deploy=$((descartadas_deploy + 1))
            case " $dominios_deploy " in
                *" $host_linha "*) ;;
                *) dominios_deploy="${dominios_deploy:+$dominios_deploy }$host_linha" ;;
            esac
        else
            mantidas+="$linha_5xx"$'\n'
        fi
    done <<<"$novas"
    if [ "$descartadas_deploy" -gt 0 ]; then
        registrar "$descartadas_deploy linha(s) de 5xx durante deploy descartadas: $dominios_deploy"
        [ "$MODO" = "--estado" ] && printf 'durante deploy de %s: %s linha(s) de 5xx descartadas\n' \
            "$dominios_deploy" "$descartadas_deploy"
    fi
    novas=$mantidas
fi

# --------------------------------------------------------------------------
# Um alerta por host
#
# Uma quebra costuma render dezenas de linhas em segundos. Agrupar por host
# transforma isso em uma mensagem por aplicação afetada, com a contagem por
# rota dentro -- que é a informação que orienta.
# --------------------------------------------------------------------------
hosts=$(printf '%s\n' "$novas" | grep -o 'host=[^ ]*' | cut -d= -f2 | sort -u)

# --------------------------------------------------------------------------
# Janela de operação
#
# Trocar o contêiner de um app devolve 502 por alguns segundos, e isso é o
# esperado. Alertar "5xx em <host>" no meio de um deploy treina o operador a
# ignorar o sentinela. Se algum app está com o lock da operação segurado, os
# 5xx lidos agora são registrados no journal e descartados: a marca avança
# como se tivessem sido tratados, porque o que importa é o erro que continua
# DEPOIS do deploy, e esse chega em outra leitura. Deploy que quebra de
# verdade já tem alerta próprio no `deploy.sh` ("DEPLOY REVERTIDO", "DEPLOY
# QUEBRADO"). Sem o lock (nada em andamento), o comportamento é o de sempre.
# --------------------------------------------------------------------------
em_operacao=""
if [ -d "$APP_LOCK_DIR" ]; then
    for arquivo in "$APP_LOCK_DIR"/*.lock; do
        [ -e "$arquivo" ] || continue
        if ! ( flock -n 9 ) 9<"$arquivo" 2>/dev/null; then
            em_operacao="${em_operacao:+$em_operacao }$(basename "$arquivo" .lock)"
        fi
    done
fi
if [ -n "$em_operacao" ]; then
    descartadas=$(printf '%s\n' "$novas" | grep -c .)
    registrar "$descartadas linha(s) de 5xx descartadas: operação em curso em $em_operacao"
    [ "$MODO" = "--estado" ] && printf 'operação em curso em %s: %s linha(s) de 5xx seriam descartadas\n' "$em_operacao" "$descartadas"
    hosts=""
fi

for host in $hosts; do
    linhas=$(printf '%s\n' "$novas" | grep -F "host=$host ")
    total=$(printf '%s\n' "$linhas" | grep -c .)

    por_rota=$(
        printf '%s\n' "$linhas" \
        | grep -o 'status=[0-9]* .*rota=[^ ]*' \
        | sed 's/ metodo=[A-Z]*//' \
        | sort | uniq -c | sort -rn | head -n "$AMOSTRA"
    )

    if [ "$MODO" = "--estado" ]; then
        printf '%s: %s erro(s) 5xx\n%s\n' "$host" "$total" "$por_rota"
    fi

    alertar "5xx em $host" \
"$total resposta(s) 5xx desde a verificação anterior.

Por status e rota (as $AMOSTRA maiores):
$por_rota

Primeiras linhas:
$(printf '%s\n' "$linhas" | head -n "$AMOSTRA")

Como ler o campo upstream:
  upstream=502  o nginx tentou e nao conseguiu conectar -- contêiner parado
                ou worker morto. Comece pelo estado da frota, abaixo.
  upstream=500  a aplicacao estava viva e respondeu o erro. O motivo esta no
                log dela, nao aqui.
  upstream=-    o nginx respondeu sozinho, sem tentar a aplicacao.

Estado da frota:  ~/deploy.sh --status"
done

# Só avança a marca depois de processar. Se o script morrer no meio, a
# próxima execução relê -- repetir alerta é aceitável, perder não é. E o
# `alerta.sh` já suprime repetição dentro da janela.
if [ "$MODO" != "--estado" ]; then
    # O prefixo assinado nunca passa do tamanho atual: assinar bytes que ainda
    # não existem faria a assinatura mudar sozinha na próxima linha gravada.
    prefixo=$PREFIXO_MAX
    [ "$tamanho_atual" -lt "$prefixo" ] && prefixo=$tamanho_atual
    printf '%s:%s:%s:%s\n' "$inode_atual" "$tamanho_atual" "$prefixo" \
        "$(head -c "$prefixo" "$LOG" 2>/dev/null | sha256sum | cut -c1-16)" > "$MARCA"
fi

exit 0
