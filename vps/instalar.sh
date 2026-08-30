#!/usr/bin/env bash
# Instala no VPS os artefatos versionados em `vps/`, a partir do clone local.
#
#   ./instalar.sh --check   mostra a diferença e não escreve nada
#   ./instalar.sh           instala o que estiver diferente
#
# POR QUE ESTE ARQUIVO EXISTE. Em 30/08/2026 comparou-se, arquivo a arquivo, o
# que roda no servidor com o que este repositório versiona. O `deploy.sh`
# instalado estava 160 linhas de código atrás do daqui — sem o registro do
# último SHA saudável, que o README descrevia como se existisse. Os outros
# artefatos batiam, mas por sorte: ninguém tinha mexido no código deles desde
# a cópia manual. Não havia mecanismo nenhum garantindo a igualdade, então a
# deriva era o estado padrão e não um acidente.
#
# É a mesma pergunta que os quatro aplicativos já respondem por construção — o
# `deploy.sh` atualiza só por fast-forward de `main` e recusa checkout sujo — e
# que a própria ferramenta não respondia sobre si.
#
# POR QUE OS DESTINOS VÊM DO AMBIENTE. `DESTINO_SCRIPTS`, `DESTINO_SYSTEMD`,
# `SYSTEMCTL` e `SUDO` são sobrescrevíveis para que `tests/instalar_test.sh`
# exercite ESTE arquivo, e não uma cópia adaptada. A lição vem do mesmo dia: o
# `deploy_test.sh` já dirigia o `deploy.sh` deste repositório por essas mesmas
# variáveis, e o servidor rodava uma versão que fixava os caminhos — a suíte
# passava verde sobre um arquivo que não era o que rodaria num incidente.
#
# POR QUE NÃO CLONA SOZINHO. O clone é pré-requisito, criado uma vez com a
# chave de deploy própria do repositório (`github-manutencao` no
# `~/.ssh/config`, mesmo padrão dos quatro aplicativos). Um instalador que
# também busca o código decidiria de onde vem a verdade; aqui a verdade é o
# checkout em que ele está, e `git pull` continua sendo passo separado e
# visível.
#
# O NGINX FICA DE FORA de propósito: tem instalador próprio
# (`nginx/instalar.sh`), que salva a configuração atual, roda `nginx -t` e
# restaura o backup se a validação falhar. Reimplementar isso aqui seria pior
# do que chamar aquilo. Este instalador apenas o entrega em
# `~/instalar-nginx.sh`, que é o nome pelo qual o servidor já o conhece.

set -euo pipefail

ORIGEM=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DESTINO_SCRIPTS=${DESTINO_SCRIPTS:-/home/ubuntu}
DESTINO_SYSTEMD=${DESTINO_SYSTEMD:-/etc/systemd/system}
SYSTEMCTL=${SYSTEMCTL:-systemctl}
SUDO=${SUDO-sudo}
# Dono de cada destino. Declarado, e nao herdado de quem roda o instalador:
# a primeira versao deste arquivo fazia `chown root:root` em tudo e deixou
# cinco scripts de /home/ubuntu com dono root e os outros quatro com dono
# ubuntu -- efeito colateral silencioso, e arvore inconsistente.
DONO_SCRIPTS=${DONO_SCRIPTS:-ubuntu:ubuntu}
DONO_SYSTEMD=${DONO_SYSTEMD:-root:root}

# Inventário: "origem relativa|destino absoluto|modo|dono".
#
# É a lista COMPLETA do que este repositório instala. O que não está aqui não é
# tocado -- o instalador nunca remove nem sobrescreve arquivo que não declarou.
#
# `nginx/instalar.sh` vira `instalar-nginx.sh` no destino: o servidor já o
# chama assim, e renomear no servidor quebraria a memória de quem opera.
INVENTARIO=(
    "alerta.sh|$DESTINO_SCRIPTS/alerta.sh|755|$DONO_SCRIPTS"
    "autocura.sh|$DESTINO_SCRIPTS/autocura.sh|755|$DONO_SCRIPTS"
    "backup-agent.sh|$DESTINO_SCRIPTS/backup-agent.sh|755|$DONO_SCRIPTS"
    "backup-db.sh|$DESTINO_SCRIPTS/backup-db.sh|755|$DONO_SCRIPTS"
    "deploy.sh|$DESTINO_SCRIPTS/deploy.sh|755|$DONO_SCRIPTS"
    "docker-prune.sh|$DESTINO_SCRIPTS/docker-prune.sh|755|$DONO_SCRIPTS"
    "uptimerobot-monitores.sh|$DESTINO_SCRIPTS/uptimerobot-monitores.sh|755|$DONO_SCRIPTS"
    "vigia.sh|$DESTINO_SCRIPTS/vigia.sh|755|$DONO_SCRIPTS"
    "nginx/instalar.sh|$DESTINO_SCRIPTS/instalar-nginx.sh|755|$DONO_SCRIPTS"
    "alerta@.service|$DESTINO_SYSTEMD/alerta@.service|644|$DONO_SYSTEMD"
    "autocura.service|$DESTINO_SYSTEMD/autocura.service|644|$DONO_SYSTEMD"
    "autocura.timer|$DESTINO_SYSTEMD/autocura.timer|644|$DONO_SYSTEMD"
    "backup-db.service|$DESTINO_SYSTEMD/backup-db.service|644|$DONO_SYSTEMD"
    "backup-db.timer|$DESTINO_SYSTEMD/backup-db.timer|644|$DONO_SYSTEMD"
    "docker-prune.service|$DESTINO_SYSTEMD/docker-prune.service|644|$DONO_SYSTEMD"
    "docker-prune.timer|$DESTINO_SYSTEMD/docker-prune.timer|644|$DONO_SYSTEMD"
    "vigia.service|$DESTINO_SYSTEMD/vigia.service|644|$DONO_SYSTEMD"
    "vigia.timer|$DESTINO_SYSTEMD/vigia.timer|644|$DONO_SYSTEMD"
    "certbot.service.d/alerta.conf|$DESTINO_SYSTEMD/certbot.service.d/alerta.conf|644|$DONO_SYSTEMD"
)

#: Timers a reiniciar quando a unidade correspondente mudar. `alerta@.service` é
#: template, instanciado sob demanda por quem alerta, e o drop-in do certbot
#: vale na próxima execução dele -- nenhum dos dois tem timer a reiniciar aqui.
declare -A TIMER_DE=(
    [autocura.service]=autocura.timer
    [autocura.timer]=autocura.timer
    [backup-db.service]=backup-db.timer
    [backup-db.timer]=backup-db.timer
    [docker-prune.service]=docker-prune.timer
    [docker-prune.timer]=docker-prune.timer
    [vigia.service]=vigia.timer
    [vigia.timer]=vigia.timer
)

modo_check=0
[ "${1:-}" = "--check" ] && modo_check=1
if [ -n "${1:-}" ] && [ "$1" != "--check" ]; then
    echo "Uso: $0 [--check]" >&2
    exit 2
fi

# --------------------------------------------------------------------------
# Guardas
# --------------------------------------------------------------------------

# Um `\r` num script instalado quebra o shebang de um jeito que a mensagem de
# erro não explica ("bad interpreter: /usr/bin/env bash^M"). Este repositório é
# editado em Windows, então o risco é real. Falha alto, e não em silêncio.
recusar_cr() {
    local arquivo=$1
    if LC_ALL=C grep -q $'\r' "$arquivo"; then
        echo "ERRO: $arquivo contém CR. O checkout precisa estar em LF." >&2
        return 1
    fi
}

# O servidor é espelho do `main`, como já vale para os aplicativos. Instalar a
# partir de um checkout sujo publicaria uma edição que ninguém revisou e que o
# `git` do servidor descartaria no próximo `pull`.
#
# Só no modo de instalação: `--check` precisa funcionar em qualquer estado,
# porque é exatamente a pergunta "o que está diferente?".
exigir_checkout_limpo() {
    local sujo
    if ! sujo=$(git -C "$ORIGEM" status --porcelain 2>/dev/null); then
        echo "ERRO: $ORIGEM não é um checkout git." >&2
        return 1
    fi
    if [ -n "$sujo" ]; then
        echo "ERRO: há alteração não commitada no checkout:" >&2
        printf '%s\n' "$sujo" | sed 's/^/  /' >&2
        echo "Commite ou descarte antes de instalar." >&2
        return 1
    fi
}

# --------------------------------------------------------------------------
# Comparação e instalação
# --------------------------------------------------------------------------

# 0 = já igual (conteúdo, modo e dono), 1 = precisa instalar.
#
# O dono entra na comparação porque entra na instalação: verificar só o que é
# barato de verificar deixaria um `chown` que falhou passar em silêncio, e a
# conferência final existe justamente para não confiar no que foi tentado.
esta_igual() {
    local origem=$1 destino=$2 modo=$3 dono=$4
    [ -f "$destino" ] || return 1
    cmp -s "$origem" "$destino" || return 1
    [ "$(stat -c '%a' "$destino" 2>/dev/null)" = "$modo" ] || return 1
    [ "$(stat -c '%U:%G' "$destino" 2>/dev/null)" = "$dono" ] || return 1
}

# Grava por arquivo temporário no MESMO diretório e renomeia: o `mv` dentro do
# filesystem é atômico, então nunca existe um script meio escrito -- que, num
# arquivo que o systemd pode disparar a qualquer segundo, seria pior do que a
# versão velha.
instalar_um() {
    local origem=$1 destino=$2 modo=$3 dono=$4 dir temporario
    dir=$(dirname -- "$destino")

    $SUDO install -d -m 755 "$dir"
    temporario=$($SUDO mktemp "$dir/.instalar.XXXXXX")
    $SUDO cp -- "$origem" "$temporario"
    $SUDO chmod "$modo" "$temporario"
    # Sem `|| true`: um dono errado é diferença de verdade, e a conferência
    # final o apanharia de todo jeito -- melhor falhar onde a causa está.
    $SUDO chown "$dono" "$temporario"
    $SUDO mv -f -- "$temporario" "$destino"
}

# --------------------------------------------------------------------------
# Execução
# --------------------------------------------------------------------------

[ "$modo_check" -eq 1 ] || exigir_checkout_limpo

declare -a diferentes=()
for item in "${INVENTARIO[@]}"; do
    IFS='|' read -r relativo destino modo dono <<<"$item"
    origem="$ORIGEM/$relativo"

    if [ ! -f "$origem" ]; then
        echo "ERRO: $relativo consta do inventário e não existe em $ORIGEM." >&2
        exit 1
    fi
    recusar_cr "$origem"

    if esta_igual "$origem" "$destino" "$modo" "$dono"; then
        printf '  igual      %s\n' "$destino"
    else
        printf '  DIFERENTE  %s\n' "$destino"
        diferentes+=("$item")
    fi
done

echo
if [ "${#diferentes[@]}" -eq 0 ]; then
    echo "Nada a fazer: o servidor já espelha $(git -C "$ORIGEM" rev-parse --short HEAD 2>/dev/null || echo 'este checkout')."
    exit 0
fi

if [ "$modo_check" -eq 1 ]; then
    echo "${#diferentes[@]} artefato(s) diferente(s). Rode sem --check para instalar."
    # Sai diferente de zero para que uma verificação periódica ou a CI consigam
    # distinguir "em dia" de "à deriva" sem interpretar texto.
    exit 1
fi

declare -a timers=()
recarregar_systemd=0
for item in "${diferentes[@]}"; do
    IFS='|' read -r relativo destino modo dono <<<"$item"
    instalar_um "$ORIGEM/$relativo" "$destino" "$modo" "$dono"
    echo "  instalado  $destino"

    case "$destino" in
        "$DESTINO_SYSTEMD"/*)
            recarregar_systemd=1
            nome=$(basename -- "$destino")
            timer=${TIMER_DE[$nome]:-}
            if [ -n "$timer" ] && [[ " ${timers[*]-} " != *" $timer "* ]]; then
                timers+=("$timer")
            fi
            ;;
    esac
done

if [ "$recarregar_systemd" -eq 1 ]; then
    echo
    echo "-- recarregando o systemd --"
    $SUDO "$SYSTEMCTL" daemon-reload
    for timer in "${timers[@]-}"; do
        [ -n "$timer" ] || continue
        echo "  reiniciando $timer"
        $SUDO "$SYSTEMCTL" restart "$timer"
    done
fi

# --------------------------------------------------------------------------
# Conferência final
# --------------------------------------------------------------------------
#
# Instalar e declarar feito é o erro que originou este arquivo. Aqui se mede o
# resultado: relê cada destino e só sai com sucesso se todos baterem.

echo
echo "-- conferindo --"
restaram=0
for item in "${INVENTARIO[@]}"; do
    IFS='|' read -r relativo destino modo dono <<<"$item"
    if ! esta_igual "$ORIGEM/$relativo" "$destino" "$modo" "$dono"; then
        echo "  AINDA DIFERENTE  $destino" >&2
        restaram=$((restaram + 1))
    fi
done

if [ "$restaram" -gt 0 ]; then
    echo "FALHOU: $restaram artefato(s) continuam diferentes." >&2
    exit 1
fi

echo "OK: os ${#INVENTARIO[@]} artefatos espelham $(git -C "$ORIGEM" rev-parse --short HEAD 2>/dev/null || echo 'o checkout')."
