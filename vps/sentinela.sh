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
# Um alerta por host
#
# Uma quebra costuma render dezenas de linhas em segundos. Agrupar por host
# transforma isso em uma mensagem por aplicação afetada, com a contagem por
# rota dentro -- que é a informação que orienta.
# --------------------------------------------------------------------------
hosts=$(printf '%s\n' "$novas" | grep -o 'host=[^ ]*' | cut -d= -f2 | sort -u)

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

upstream=- significa que o nginx nao chegou a falar com a aplicacao (worker
morto, contêiner parado); upstream com numero significa que a aplicacao
respondeu o erro por conta propria.

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
